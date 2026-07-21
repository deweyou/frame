import AppKit
import FrameCore

struct ScrollingScreenshotProcessingFrame: @unchecked Sendable {
    let image: CGImage
    let scale: CGFloat
    let rect: CGRect
}

struct ScrollingScreenshotProcessedSample: @unchecked Sendable {
    let progress: ScrollingScreenshotIngestResult
    let previewImage: NSImage?
}

protocol ScrollingScreenshotIncrementalProcessing: AnyObject, Sendable {
    func ingest(_ frame: ScrollingScreenshotProcessingFrame) throws -> ScrollingScreenshotProcessedSample
    func finish(outputID: UUID) throws -> CapturedScreenshot
}

final class ScrollingScreenshotIncrementalPipeline: ScrollingScreenshotIncrementalProcessing, @unchecked Sendable {
    private let previewMaximumPixelWidth: Int
    private let fullResolutionAccumulator: ScrollingScreenshotAccumulator
    private let previewConfiguration: ScrollingScreenshotAccumulatorConfiguration
    private var previewAccumulator: ScrollingScreenshotAccumulator
    private var firstFrameScale: CGFloat?
    private var selectionRect: CGRect?

    init(
        previewMaximumPixelWidth: Int = 440,
        fullResolutionConfiguration: ScrollingScreenshotAccumulatorConfiguration = .init(),
        previewConfiguration: ScrollingScreenshotAccumulatorConfiguration = .init(
            maximumCanvasBytes: 64 * 1_024 * 1_024,
            maximumHistoricalFingerprints: 256
        )
    ) {
        self.previewMaximumPixelWidth = max(1, previewMaximumPixelWidth)
        self.previewConfiguration = previewConfiguration
        fullResolutionAccumulator = ScrollingScreenshotAccumulator(
            configuration: fullResolutionConfiguration
        )
        previewAccumulator = ScrollingScreenshotAccumulator(
            configuration: previewConfiguration
        )
    }

    func ingest(_ frame: ScrollingScreenshotProcessingFrame) throws -> ScrollingScreenshotProcessedSample {
        if firstFrameScale == nil {
            firstFrameScale = max(frame.scale, 0.001)
            selectionRect = frame.rect
        }

        let progress = try fullResolutionAccumulator.ingest(
            ScrollingScreenshotFrame(image: frame.image, scale: frame.scale)
        )
        guard progress.state == .initialized || progress.state == .appended else {
            return ScrollingScreenshotProcessedSample(progress: progress, previewImage: nil)
        }

        let previewImage = (try? updatePreviewAccumulator(with: frame.image))
            ?? (try? rebuildPreviewFromAcceptedCanvas())

        return ScrollingScreenshotProcessedSample(
            progress: progress,
            previewImage: previewImage
        )
    }

    func finish(outputID: UUID) throws -> CapturedScreenshot {
        guard let selectionRect,
              let firstFrameScale else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        let stitchedImage = try fullResolutionAccumulator.makeImage()
        let imageSize = CGSize(
            width: CGFloat(stitchedImage.width) / firstFrameScale,
            height: CGFloat(stitchedImage.height) / firstFrameScale
        )
        let image = NSImage(cgImage: stitchedImage, size: imageSize)
        let bitmapRepresentation = NSBitmapImageRep(cgImage: stitchedImage)
        guard let pngData = bitmapRepresentation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }

        return CapturedScreenshot(
            id: outputID,
            pngData: pngData,
            image: image,
            rect: CGRect(origin: selectionRect.origin, size: imageSize)
        )
    }

    private func downsampleForPreview(_ image: CGImage) throws -> CGImage {
        let scale = min(
            1,
            CGFloat(previewMaximumPixelWidth) / CGFloat(max(image.width, 1))
        )
        guard scale < 1 else {
            return image
        }

        let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(image.height) * scale).rounded()))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let downsampledImage = context.makeImage() else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }
        return downsampledImage
    }

    private func updatePreviewAccumulator(with image: CGImage) throws -> NSImage? {
        let previewFrameImage = try downsampleForPreview(image)
        let previewProgress = try previewAccumulator.ingest(
            ScrollingScreenshotFrame(image: previewFrameImage, scale: 1)
        )
        guard previewProgress.state == .initialized || previewProgress.state == .appended else {
            return nil
        }

        let stitchedPreview = try previewAccumulator.makeImage()
        return NSImage(
            cgImage: stitchedPreview,
            size: CGSize(width: stitchedPreview.width, height: stitchedPreview.height)
        )
    }

    private func rebuildPreviewFromAcceptedCanvas() throws -> NSImage {
        let fullResolutionImage = try fullResolutionAccumulator.makeImage()
        let previewImage = try downsampleForPreview(fullResolutionImage)
        previewAccumulator = ScrollingScreenshotAccumulator(
            configuration: previewConfiguration
        )
        _ = try previewAccumulator.ingest(
            ScrollingScreenshotFrame(image: previewImage, scale: 1)
        )
        return NSImage(
            cgImage: previewImage,
            size: CGSize(width: previewImage.width, height: previewImage.height)
        )
    }
}
