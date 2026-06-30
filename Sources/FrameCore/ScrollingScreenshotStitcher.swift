import CoreGraphics
import Foundation

public struct ScrollingScreenshotFrame {
    public let image: CGImage
    public let scale: CGFloat

    public init(image: CGImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }
}

public enum ScrollingScreenshotStitchingError: Error, Equatable {
    case insufficientFrames
    case noScrollProgress
    case noReliableOverlap
    case outputEncodingFailed
}

public final class ScrollingScreenshotStitcher {
    public init() {}

    public func stitch(_ frames: [ScrollingScreenshotFrame]) throws -> CGImage {
        guard frames.count >= 2 else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        var acceptedFrames: [PixelFrame] = []
        for frame in try frames.map(PixelFrame.init) {
            guard let previousFrame = acceptedFrames.last else {
                acceptedFrames.append(frame)
                continue
            }

            if previousFrame.hasSamePixels(as: frame) {
                continue
            }

            acceptedFrames.append(frame)
        }

        guard acceptedFrames.count >= 2 else {
            throw ScrollingScreenshotStitchingError.noScrollProgress
        }

        var outputPixels = acceptedFrames[0].pixels
        var outputHeight = acceptedFrames[0].height
        let outputWidth = acceptedFrames[0].width

        for frameIndex in acceptedFrames.indices.dropFirst() {
            let originalFrame = acceptedFrames[frameIndex]
            guard originalFrame.width == outputWidth else {
                throw ScrollingScreenshotStitchingError.noReliableOverlap
            }

            let previousOriginalFrame = acceptedFrames[frameIndex - 1]
            let fixedTopRows = previousOriginalFrame.commonTopRowCount(with: originalFrame)
            let frame = originalFrame.droppingTopRows(fixedTopRows)
            if PixelFrame.recentRows(in: outputPixels, width: outputWidth, height: outputHeight, contain: frame) {
                continue
            }

            let preferredOverlap = PixelFrame.preferredOverlap(for: originalFrame.height, fixedTopRows: fixedTopRows)
            let appendCandidate = PixelFrame.verticalOverlap(
                betweenPreviousPixels: outputPixels,
                previousWidth: outputWidth,
                previousHeight: outputHeight,
                and: frame,
                preferredOverlap: preferredOverlap
            )

            let prependCandidate = PixelFrame.verticalPrependOverlap(
                betweenPreviousPixels: outputPixels,
                previousWidth: outputWidth,
                previousHeight: outputHeight,
                fixedTopRows: fixedTopRows,
                and: frame,
                preferredOverlap: preferredOverlap
            )

            if let appendCandidate,
               appendCandidate.isBetter(than: prependCandidate) {
                outputPixels.append(contentsOf: frame.pixels(fromRow: appendCandidate.overlap))
                outputHeight += frame.height - appendCandidate.overlap
                continue
            }

            if let prependCandidate {
                outputPixels = PixelFrame.prepending(
                    frame.pixels(upToRow: frame.height - prependCandidate.overlap),
                    to: outputPixels,
                    width: outputWidth,
                    fixedTopRows: fixedTopRows
                )
                outputHeight += frame.height - prependCandidate.overlap
                continue
            }

            throw ScrollingScreenshotStitchingError.noReliableOverlap
        }

        return try makeImage(width: outputWidth, height: outputHeight, pixels: &outputPixels)
    }

    private func makeImage(width: Int, height: Int, pixels: inout [UInt8]) throws -> CGImage {
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * PixelFrame.bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
            let image = context.makeImage()
        else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }

        return image
    }
}

private struct PixelFrame {
    static let bytesPerPixel = 4
    static let maximumAverageChannelDifference: Double = 6
    static let maximumAverageIdenticalChannelDifference: Double = 2
    static let candidateDifferenceTieTolerance: Double = 0.25
    static let expectedScrollFraction: Double = 0.45

    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(_ frame: ScrollingScreenshotFrame) throws {
        width = frame.image.width
        height = frame.image.height
        let bytesPerRow = width * Self.bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }

        context.draw(frame.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.pixels = pixels
    }

    init(width: Int, height: Int, pixels: [UInt8]) {
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    func hasSamePixels(as otherFrame: PixelFrame) -> Bool {
        guard width == otherFrame.width,
              height == otherFrame.height else {
            return false
        }

        return averageChannelDifference(from: pixels, to: otherFrame.pixels) <= Self.maximumAverageIdenticalChannelDifference
    }

    static func verticalOverlap(
        betweenPreviousPixels previousPixels: [UInt8],
        previousWidth: Int,
        previousHeight: Int,
        and nextFrame: PixelFrame,
        preferredOverlap: Int? = nil
    ) -> OverlapCandidate? {
        guard previousWidth == nextFrame.width else {
            return nil
        }

        let maximumOverlap = min(previousHeight, nextFrame.height) - 1
        guard maximumOverlap > 0 else {
            return nil
        }

        var bestCandidate: OverlapCandidate?
        for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
            guard rowsMatch(
                previousPixels,
                row: previousHeight - overlap,
                otherPixels: nextFrame.pixels,
                otherRow: 0,
                width: previousWidth
            ),
                rowsMatch(
                    previousPixels,
                    row: previousHeight - 1,
                    otherPixels: nextFrame.pixels,
                    otherRow: overlap - 1,
                    width: previousWidth
                )
            else {
                continue
            }

            let difference = averageChannelDifference(
                from: previousPixels,
                startRow: previousHeight - overlap,
                to: nextFrame.pixels,
                otherStartRow: 0,
                rowCount: overlap,
                width: previousWidth
            )
            guard difference <= Self.maximumAverageChannelDifference else {
                continue
            }

            let candidate = OverlapCandidate(
                overlap: overlap,
                difference: difference,
                preferredDistance: preferredOverlap.map { abs(overlap - $0) } ?? 0
            )
            if candidate.isBetter(than: bestCandidate) {
                bestCandidate = candidate
            }
        }

        return bestCandidate
    }

    static func verticalPrependOverlap(
        betweenPreviousPixels previousPixels: [UInt8],
        previousWidth: Int,
        previousHeight: Int,
        fixedTopRows: Int,
        and nextFrame: PixelFrame,
        preferredOverlap: Int? = nil
    ) -> OverlapCandidate? {
        guard previousWidth == nextFrame.width else {
            return nil
        }

        let contentStartRow = min(max(fixedTopRows, 0), previousHeight)
        let contentHeight = previousHeight - contentStartRow
        let maximumOverlap = min(contentHeight, nextFrame.height) - 1
        guard maximumOverlap > 0 else {
            return nil
        }

        var bestCandidate: OverlapCandidate?
        for overlap in stride(from: maximumOverlap, through: 1, by: -1) {
            guard rowsMatch(
                nextFrame.pixels,
                row: nextFrame.height - overlap,
                otherPixels: previousPixels,
                otherRow: contentStartRow,
                width: previousWidth
            ),
                rowsMatch(
                    nextFrame.pixels,
                    row: nextFrame.height - 1,
                    otherPixels: previousPixels,
                    otherRow: contentStartRow + overlap - 1,
                    width: previousWidth
                )
            else {
                continue
            }

            let difference = averageChannelDifference(
                from: nextFrame.pixels,
                startRow: nextFrame.height - overlap,
                to: previousPixels,
                otherStartRow: contentStartRow,
                rowCount: overlap,
                width: previousWidth
            )
            guard difference <= Self.maximumAverageChannelDifference else {
                continue
            }

            let candidate = OverlapCandidate(
                overlap: overlap,
                difference: difference,
                preferredDistance: preferredOverlap.map { abs(overlap - $0) } ?? 0
            )
            if candidate.isBetter(than: bestCandidate) {
                bestCandidate = candidate
            }
        }

        return bestCandidate
    }

    static func preferredOverlap(for originalHeight: Int, fixedTopRows: Int) -> Int? {
        let scrolledRows = max(1, Int((Double(originalHeight) * expectedScrollFraction).rounded()))
        let overlap = originalHeight - fixedTopRows - scrolledRows
        guard overlap > 0 else {
            return nil
        }

        return overlap
    }

    func commonTopRowCount(with otherFrame: PixelFrame) -> Int {
        guard width == otherFrame.width else {
            return 0
        }

        let maximumRows = min(height, otherFrame.height) - 1
        guard maximumRows > 0 else {
            return 0
        }

        var commonRows = 0
        for row in 0..<maximumRows {
            if Self.averageChannelDifference(
                from: pixels,
                startRow: row,
                to: otherFrame.pixels,
                otherStartRow: row,
                rowCount: 1,
                width: width
            ) <= Self.maximumAverageIdenticalChannelDifference {
                commonRows += 1
            } else {
                break
            }
        }

        return commonRows
    }

    func droppingTopRows(_ rowCount: Int) -> PixelFrame {
        guard rowCount > 0, rowCount < height else {
            return self
        }

        return PixelFrame(
            width: width,
            height: height - rowCount,
            pixels: pixels(fromRow: rowCount)
        )
    }

    static func recentRows(
        in previousPixels: [UInt8],
        width: Int,
        height: Int,
        contain otherFrame: PixelFrame
    ) -> Bool {
        guard width == otherFrame.width,
              otherFrame.height <= height else {
            return false
        }

        let searchHeight = min(height, otherFrame.height * 3)
        let firstSearchRow = height - searchHeight
        let maximumStartRow = height - otherFrame.height
        guard firstSearchRow <= maximumStartRow else {
            return false
        }

        for startRow in firstSearchRow...maximumStartRow {
            guard rowsMatch(
                previousPixels,
                row: startRow,
                otherPixels: otherFrame.pixels,
                otherRow: 0,
                width: width
            ),
                rowsMatch(
                    previousPixels,
                    row: startRow + otherFrame.height - 1,
                    otherPixels: otherFrame.pixels,
                    otherRow: otherFrame.height - 1,
                    width: width
                ),
                rowsMatch(
                    previousPixels,
                    row: startRow + otherFrame.height / 2,
                    otherPixels: otherFrame.pixels,
                    otherRow: otherFrame.height / 2,
                    width: width
                )
            else {
                continue
            }

            if averageChannelDifference(
                from: previousPixels,
                startRow: startRow,
                to: otherFrame.pixels,
                otherStartRow: 0,
                rowCount: otherFrame.height,
                width: width
            ) <= Self.maximumAverageIdenticalChannelDifference {
                return true
            }
        }

        return false
    }

    func pixels(fromRow firstRow: Int) -> [UInt8] {
        let bytesPerRow = width * Self.bytesPerPixel
        let startOffset = firstRow * bytesPerRow
        guard startOffset < pixels.count else {
            return []
        }

        return Array(pixels[startOffset...])
    }

    func pixels(upToRow lastExcludedRow: Int) -> [UInt8] {
        let rowCount = min(max(lastExcludedRow, 0), height)
        guard rowCount > 0 else {
            return []
        }

        return Array(pixels[..<(rowCount * width * Self.bytesPerPixel)])
    }

    static func prepending(
        _ prependedPixels: [UInt8],
        to outputPixels: [UInt8],
        width: Int,
        fixedTopRows: Int
    ) -> [UInt8] {
        guard !prependedPixels.isEmpty else {
            return outputPixels
        }

        let fixedByteCount = min(max(fixedTopRows, 0) * width * bytesPerPixel, outputPixels.count)
        return Array(outputPixels[..<fixedByteCount])
            + prependedPixels
            + Array(outputPixels[fixedByteCount...])
    }

    private static func rowsMatch(
        _ firstPixels: [UInt8],
        row: Int,
        otherPixels: [UInt8],
        otherRow: Int,
        width: Int
    ) -> Bool {
        averageChannelDifference(
            from: firstPixels,
            startRow: row,
            to: otherPixels,
            otherStartRow: otherRow,
            rowCount: 1,
            width: width
        ) <= maximumAverageChannelDifference
    }

    private static func averageChannelDifference(
        from firstPixels: [UInt8],
        startRow: Int,
        to secondPixels: [UInt8],
        otherStartRow: Int,
        rowCount: Int,
        width: Int
    ) -> Double {
        guard startRow >= 0,
              otherStartRow >= 0,
              rowCount > 0 else {
            return .infinity
        }

        let bytesPerRow = width * Self.bytesPerPixel
        let startOffset = startRow * bytesPerRow
        let otherStartOffset = otherStartRow * bytesPerRow
        let byteCount = rowCount * bytesPerRow
        guard startOffset + byteCount <= firstPixels.count,
              otherStartOffset + byteCount <= secondPixels.count else {
            return .infinity
        }

        var totalDifference = 0
        for offset in 0..<byteCount {
            totalDifference += abs(Int(firstPixels[startOffset + offset]) - Int(secondPixels[otherStartOffset + offset]))
        }

        return Double(totalDifference) / Double(byteCount)
    }

    private func averageChannelDifference(from firstPixels: [UInt8], to secondPixels: [UInt8]) -> Double {
        guard firstPixels.count == secondPixels.count,
              !firstPixels.isEmpty else {
            return .infinity
        }

        let totalDifference = zip(firstPixels, secondPixels).reduce(0) { partialResult, channels in
            partialResult + abs(Int(channels.0) - Int(channels.1))
        }
        return Double(totalDifference) / Double(firstPixels.count)
    }

    struct OverlapCandidate {
        let overlap: Int
        let difference: Double
        let preferredDistance: Int

        func isBetter(than other: OverlapCandidate?) -> Bool {
            guard let other else {
                return true
            }

            if difference + candidateDifferenceTieTolerance < other.difference {
                return true
            }

            if abs(difference - other.difference) <= candidateDifferenceTieTolerance {
                return preferredDistance < other.preferredDistance
            }

            return false
        }
    }
}
