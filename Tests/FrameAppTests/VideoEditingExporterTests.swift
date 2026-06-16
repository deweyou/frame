import AVFoundation
import XCTest
@testable import FrameApp
@testable import FrameCore

final class VideoEditingExporterTests: XCTestCase {
    func testExporterRejectsGIFInput() async throws {
        let exporter = VideoEditingExporter()
        let gifURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameVideoEditingExporterTests-\(UUID().uuidString).gif")
        try Data([1, 2, 3]).write(to: gifURL)
        defer {
            try? FileManager.default.removeItem(at: gifURL)
        }

        var state = try VideoEditingState(sourceDuration: 2)
        try state.setTrimRange(start: 0, end: 1)

        do {
            _ = try await exporter.export(sourceURL: gifURL, format: .gif, editingState: state)
            XCTFail("Expected GIF export to fail")
        } catch let error as VideoEditingExportError {
            XCTAssertEqual(error, .unsupportedFormat)
        }
    }

    func testExporterTrimsAndScalesMP4Duration() async throws {
        let sourceURL = try Self.makeTestMP4(duration: 2)
        defer {
            try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent())
        }

        var state = try VideoEditingState(sourceDuration: 2)
        try state.setTrimRange(start: 0.5, end: 1.5)
        try state.setSpeed(.double)

        let exported = try await VideoEditingExporter().export(
            sourceURL: sourceURL,
            format: .mp4,
            editingState: state
        )
        defer {
            try? FileManager.default.removeItem(at: exported)
        }

        let asset = AVURLAsset(url: exported)
        let assetDuration: CMTime = try await asset.load(.duration)
        let duration = assetDuration.seconds
        XCTAssertEqual(duration, 0.5, accuracy: 0.18)
    }

    private static func makeTestMP4(duration: TimeInterval) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameVideoEditingExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("source.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let size = CGSize(width: 16, height: 16)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ]
        )
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        writer.add(input)

        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<Int(duration * 10) {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(
                kCFAllocatorDefault,
                Int(size.width),
                Int(size.height),
                kCVPixelFormatType_32BGRA,
                nil,
                &buffer
            )
            guard let buffer else {
                throw NSError(domain: "VideoEditingExporterTests", code: 1)
            }

            CVPixelBufferLockBaseAddress(buffer, [])
            if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
                memset(baseAddress, Int32(frameIndex % 255), CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])

            while !input.isReadyForMoreMediaData {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }

            XCTAssertTrue(adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 10)
            ))
        }

        input.markAsFinished()
        let expectation = XCTestExpectation(description: "finish writing")
        writer.finishWriting {
            expectation.fulfill()
        }
        XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(writer.status, .completed)

        return url
    }
}
