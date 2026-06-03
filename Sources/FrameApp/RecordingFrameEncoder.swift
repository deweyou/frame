import AVFoundation
import CoreImage
import CoreMedia
import Foundation
import FrameCore
import ImageIO
import UniformTypeIdentifiers

protocol RecordingFrameEncoding: AnyObject {
    func append(_ sampleBuffer: CMSampleBuffer) throws
    func finish() async throws -> URL
}

final class MP4RecordingFrameEncoder: RecordingFrameEncoding {
    private let outputURL: URL
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var didStartSession = false

    init(outputURL: URL, pixelSize: CGSize) throws {
        self.outputURL = outputURL
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: max(1, Int(pixelSize.width.rounded())),
                AVVideoHeightKey: max(1, Int(pixelSize.height.rounded())),
            ]
        )
        input.expectsMediaDataInRealTime = true
        guard writer.canAdd(input) else {
            throw RecordingServiceError.outputFailed("无法创建 MP4 写入器。")
        }
        writer.add(input)
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if writer.status == .unknown {
            guard writer.startWriting() else {
                throw RecordingServiceError.outputFailed(writer.error?.localizedDescription ?? "MP4 写入启动失败。")
            }
        }

        if !didStartSession {
            writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            didStartSession = true
        }

        guard writer.status == .writing else {
            throw RecordingServiceError.outputFailed(writer.error?.localizedDescription ?? "MP4 写入失败。")
        }

        if input.isReadyForMoreMediaData {
            input.append(sampleBuffer)
        }
    }

    func finish() async throws -> URL {
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw RecordingServiceError.outputFailed(writer.error?.localizedDescription ?? "MP4 写入完成失败。")
        }
        return outputURL
    }
}

final class GIFRecordingFrameEncoder: RecordingFrameEncoding {
    private let outputURL: URL
    private let context = CIContext()
    private var frames: [(image: CGImage, delay: TimeInterval)] = []
    private var lastFrameTime: CMTime?

    init(outputURL: URL) throws {
        self.outputURL = outputURL
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let delay = lastFrameTime.map { max(0.02, presentationTime.seconds - $0.seconds) } ?? 0.08
        lastFrameTime = presentationTime

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return
        }

        frames.append((image: cgImage, delay: delay))
    }

    func finish() async throws -> URL {
        guard !frames.isEmpty else {
            throw RecordingServiceError.outputFailed("GIF 没有可写入的录屏帧。")
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.gif.identifier as CFString,
            frames.count,
            nil
        ) else {
            throw RecordingServiceError.outputFailed("无法创建 GIF 写入器。")
        }

        CGImageDestinationSetProperties(
            destination,
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0,
                ],
            ] as CFDictionary
        )

        for frame in frames {
            CGImageDestinationAddImage(
                destination,
                frame.image,
                [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: frame.delay,
                    ],
                ] as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw RecordingServiceError.outputFailed("GIF 写入完成失败。")
        }

        return outputURL
    }
}
