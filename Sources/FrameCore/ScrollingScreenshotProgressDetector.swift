import CoreGraphics
import Foundation

public final class ScrollingScreenshotProgressDetector {
    private let sampleSize: Int
    private let progressDifferenceThreshold: Double

    public init(
        sampleSize: Int = 32,
        progressDifferenceThreshold: Double = 8
    ) {
        self.sampleSize = sampleSize
        self.progressDifferenceThreshold = progressDifferenceThreshold
    }

    public func hasScrollProgress(
        from previousFrame: ScrollingScreenshotFrame,
        to nextFrame: ScrollingScreenshotFrame
    ) -> Bool {
        guard let previousSample = samplePixels(in: previousFrame.image),
              let nextSample = samplePixels(in: nextFrame.image),
              previousSample.count == nextSample.count
        else {
            return true
        }

        return averageChannelDifference(from: previousSample, to: nextSample) > progressDifferenceThreshold
    }

    private func samplePixels(in image: CGImage) -> [UInt8]? {
        let sampleWidth = min(sampleSize, max(image.width, 1))
        let sampleHeight = min(sampleSize, max(image.height, 1))
        let bytesPerPixel = 4
        let bytesPerRow = sampleWidth * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: sampleHeight * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: sampleWidth,
            height: sampleHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
        return pixels
    }

    private func averageChannelDifference(from firstPixels: [UInt8], to secondPixels: [UInt8]) -> Double {
        guard firstPixels.count == secondPixels.count,
              !firstPixels.isEmpty else {
            return .infinity
        }

        var totalDifference = 0
        for index in firstPixels.indices {
            totalDifference += abs(Int(firstPixels[index]) - Int(secondPixels[index]))
        }
        return Double(totalDifference) / Double(firstPixels.count)
    }
}
