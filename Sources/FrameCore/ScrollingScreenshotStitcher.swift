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
    case resourceLimitExceeded
}

public struct ScrollingScreenshotAccumulatorConfiguration: Equatable {
    public let maximumCanvasBytes: Int
    public let maximumHistoricalFingerprints: Int

    public init(
        maximumCanvasBytes: Int = 256 * 1_024 * 1_024,
        maximumHistoricalFingerprints: Int = 256
    ) {
        self.maximumCanvasBytes = max(1, maximumCanvasBytes)
        self.maximumHistoricalFingerprints = max(1, maximumHistoricalFingerprints)
    }
}

public enum ScrollingScreenshotIngestState: Equatable {
    case initialized
    case appended
    case noProgress
    case historicalRepeat
    case unreliableOverlap
}

public struct ScrollingScreenshotIngestResult: Equatable {
    public let state: ScrollingScreenshotIngestState
    public let appendedPixelHeight: Int
    public let totalPixelHeight: Int
    public let verticalDisplacement: Int?
    public let confidence: Double

    public init(
        state: ScrollingScreenshotIngestState,
        appendedPixelHeight: Int,
        totalPixelHeight: Int,
        verticalDisplacement: Int?,
        confidence: Double
    ) {
        self.state = state
        self.appendedPixelHeight = appendedPixelHeight
        self.totalPixelHeight = totalPixelHeight
        self.verticalDisplacement = verticalDisplacement
        self.confidence = confidence
    }
}

public final class ScrollingScreenshotAccumulator {
    private let configuration: ScrollingScreenshotAccumulatorConfiguration
    private var outputPixels: [UInt8] = []
    private var outputWidth = 0
    private var previousAcceptedFrame: PixelFrame?
    private var historicalFingerprints: [PixelFrameFingerprint] = []

    public private(set) var totalPixelHeight = 0
    public private(set) var hasScrollProgress = false
    var retainedHistoricalFingerprintCountForTesting: Int {
        historicalFingerprints.count
    }

    public init(configuration: ScrollingScreenshotAccumulatorConfiguration = .init()) {
        self.configuration = configuration
    }

    public func ingest(_ frame: ScrollingScreenshotFrame) throws -> ScrollingScreenshotIngestResult {
        let pixelFrame = try PixelFrame(frame)
        guard let previousAcceptedFrame else {
            try validateCanvasSize(width: pixelFrame.width, height: pixelFrame.height)
            outputPixels = pixelFrame.pixels
            outputWidth = pixelFrame.width
            totalPixelHeight = pixelFrame.height
            self.previousAcceptedFrame = pixelFrame
            rememberFingerprint(of: pixelFrame)
            return progress(
                state: .initialized,
                appendedPixelHeight: pixelFrame.height,
                verticalDisplacement: nil,
                confidence: 1
            )
        }

        guard pixelFrame.width == outputWidth,
              pixelFrame.height > 1 else {
            return progress(state: .unreliableOverlap)
        }

        if previousAcceptedFrame.hasSamePixels(as: pixelFrame) {
            return progress(state: .noProgress, confidence: 1)
        }

        let fingerprint = PixelFrameFingerprint(pixelFrame)
        if historicalFingerprints.dropLast().contains(where: { $0.matches(fingerprint) }) {
            return progress(state: .historicalRepeat, confidence: 1)
        }

        let maximumStaticTopRows = max(1, pixelFrame.height / 3)
        let fixedTopRows = min(
            previousAcceptedFrame.commonTopRowCount(with: pixelFrame),
            maximumStaticTopRows
        )
        let maximumStaticBottomRows = max(1, pixelFrame.height / 4)
        let fixedBottomRows = min(
            previousAcceptedFrame.commonBottomRowCount(with: pixelFrame),
            maximumStaticBottomRows
        )
        let contentFrame = pixelFrame.droppingEdgeRows(
            top: fixedTopRows,
            bottom: fixedBottomRows
        )
        guard contentFrame.height > 1 else {
            return progress(state: .noProgress, confidence: 1)
        }

        let bytesPerRow = outputWidth * PixelFrame.bytesPerPixel
        let fixedBottomByteCount = min(
            fixedBottomRows * bytesPerRow,
            outputPixels.count
        )
        let outputContentHeight = totalPixelHeight - fixedBottomRows

        if PixelFrame.recentRows(
            in: outputPixels,
            width: outputWidth,
            height: outputContentHeight,
            contain: contentFrame
        ) {
            return progress(state: .historicalRepeat, confidence: 1)
        }

        let preferredOverlap = PixelFrame.preferredOverlap(
            for: pixelFrame.height - fixedBottomRows,
            fixedTopRows: fixedTopRows
        )
        let appendCandidate = PixelFrame.verticalOverlap(
            betweenPreviousPixels: outputPixels,
            previousWidth: outputWidth,
            previousHeight: outputContentHeight,
            and: contentFrame,
            preferredOverlap: preferredOverlap
        )
        let prependCandidate = PixelFrame.verticalPrependOverlap(
            betweenPreviousPixels: outputPixels,
            previousWidth: outputWidth,
            previousHeight: outputContentHeight,
            fixedTopRows: fixedTopRows,
            and: contentFrame,
            preferredOverlap: preferredOverlap
        )

        if let appendCandidate,
           appendCandidate.isBetter(than: prependCandidate) {
            let newContentRowCount = contentFrame.height - appendCandidate.overlap
            let nextHeight = outputContentHeight + newContentRowCount + fixedBottomRows
            try validateCanvasSize(width: outputWidth, height: nextHeight)

            if fixedBottomByteCount > 0 {
                outputPixels.removeLast(fixedBottomByteCount)
            }
            outputPixels.append(contentsOf: contentFrame.pixels(fromRow: appendCandidate.overlap))
            if fixedBottomRows > 0 {
                outputPixels.append(
                    contentsOf: pixelFrame.pixels(fromRow: pixelFrame.height - fixedBottomRows)
                )
            }
            accept(
                pixelFrame,
                outputPixels: outputPixels,
                outputHeight: nextHeight,
                fingerprint: fingerprint
            )
            return progress(
                state: .appended,
                appendedPixelHeight: newContentRowCount,
                verticalDisplacement: newContentRowCount,
                confidence: appendCandidate.confidence
            )
        }

        if let prependCandidate {
            let newContentRowCount = contentFrame.height - prependCandidate.overlap
            let nextHeight = totalPixelHeight + newContentRowCount
            try validateCanvasSize(width: outputWidth, height: nextHeight)
            let prependedPixels = contentFrame.pixels(
                upToRow: contentFrame.height - prependCandidate.overlap
            )
            let nextPixels = PixelFrame.prepending(
                prependedPixels,
                to: outputPixels,
                width: outputWidth,
                fixedTopRows: fixedTopRows
            )
            accept(
                pixelFrame,
                outputPixels: nextPixels,
                outputHeight: nextHeight,
                fingerprint: fingerprint
            )
            return progress(
                state: .appended,
                appendedPixelHeight: newContentRowCount,
                verticalDisplacement: -newContentRowCount,
                confidence: prependCandidate.confidence
            )
        }

        return progress(state: .unreliableOverlap)
    }

    public func makeImage() throws -> CGImage {
        guard outputWidth > 0,
              totalPixelHeight > 0,
              !outputPixels.isEmpty else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        var pixels = outputPixels
        guard let context = CGContext(
            data: &pixels,
            width: outputWidth,
            height: totalPixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: outputWidth * PixelFrame.bytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw ScrollingScreenshotStitchingError.outputEncodingFailed
        }
        return image
    }

    private func validateCanvasSize(width: Int, height: Int) throws {
        let (pixelCount, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (byteCount, byteOverflow) = pixelCount.multipliedReportingOverflow(by: PixelFrame.bytesPerPixel)
        guard !pixelOverflow,
              !byteOverflow,
              byteCount <= configuration.maximumCanvasBytes else {
            throw ScrollingScreenshotStitchingError.resourceLimitExceeded
        }
    }

    private func accept(
        _ frame: PixelFrame,
        outputPixels: [UInt8],
        outputHeight: Int,
        fingerprint: PixelFrameFingerprint
    ) {
        self.outputPixels = outputPixels
        totalPixelHeight = outputHeight
        previousAcceptedFrame = frame
        hasScrollProgress = true
        historicalFingerprints.append(fingerprint)
        if historicalFingerprints.count > configuration.maximumHistoricalFingerprints {
            historicalFingerprints.removeFirst(
                historicalFingerprints.count - configuration.maximumHistoricalFingerprints
            )
        }
    }

    private func rememberFingerprint(of frame: PixelFrame) {
        historicalFingerprints = [PixelFrameFingerprint(frame)]
    }

    private func progress(
        state: ScrollingScreenshotIngestState,
        appendedPixelHeight: Int = 0,
        verticalDisplacement: Int? = nil,
        confidence: Double = 0
    ) -> ScrollingScreenshotIngestResult {
        ScrollingScreenshotIngestResult(
            state: state,
            appendedPixelHeight: appendedPixelHeight,
            totalPixelHeight: totalPixelHeight,
            verticalDisplacement: verticalDisplacement,
            confidence: confidence
        )
    }
}

public final class ScrollingScreenshotStitcher {
    public init() {}

    public func stitch(_ frames: [ScrollingScreenshotFrame]) throws -> CGImage {
        try stitch(frames, maximumSkippedFrames: 0, requiresRecentFrame: false)
    }

    public func stitchRecovering(
        _ frames: [ScrollingScreenshotFrame],
        maximumSkippedFrames: Int
    ) throws -> CGImage {
        try stitch(
            frames,
            maximumSkippedFrames: max(0, maximumSkippedFrames),
            requiresRecentFrame: true
        )
    }

    private func stitch(
        _ frames: [ScrollingScreenshotFrame],
        maximumSkippedFrames: Int,
        requiresRecentFrame: Bool
    ) throws -> CGImage {
        guard frames.count >= 2 else {
            throw ScrollingScreenshotStitchingError.insufficientFrames
        }

        var acceptedFrames: [(sourceIndex: Int, frame: PixelFrame)] = []
        var resolvedSourceIndexes: Set<Int> = []
        for (sourceIndex, frame) in try frames.map(PixelFrame.init).enumerated() {
            guard !acceptedFrames.isEmpty else {
                acceptedFrames.append((sourceIndex, frame))
                resolvedSourceIndexes.insert(sourceIndex)
                continue
            }

            // A page can jump back to an earlier position after reaching its end.
            // Deduplicating only the adjacent sample lets that entire cycle be appended again.
            if acceptedFrames.contains(where: { $0.frame.hasSamePixels(as: frame) }) {
                resolvedSourceIndexes.insert(sourceIndex)
                continue
            }

            acceptedFrames.append((sourceIndex, frame))
        }

        guard acceptedFrames.count >= 2 else {
            throw ScrollingScreenshotStitchingError.noScrollProgress
        }

        var outputPixels = acceptedFrames[0].frame.pixels
        var outputHeight = acceptedFrames[0].frame.height
        let outputWidth = acceptedFrames[0].frame.width
        var previousResolvedFrame = acceptedFrames[0].frame
        var skippedFrameCount = 0
        var hasOutputProgress = false

        for acceptedFrame in acceptedFrames.dropFirst() {
            let originalFrame = acceptedFrame.frame
            guard originalFrame.width == outputWidth else {
                guard skippedFrameCount < maximumSkippedFrames else {
                    throw ScrollingScreenshotStitchingError.noReliableOverlap
                }
                skippedFrameCount += 1
                continue
            }

            let fixedTopRows = previousResolvedFrame.commonTopRowCount(with: originalFrame)
            let frame = originalFrame.droppingTopRows(fixedTopRows)
            if PixelFrame.recentRows(in: outputPixels, width: outputWidth, height: outputHeight, contain: frame) {
                previousResolvedFrame = originalFrame
                resolvedSourceIndexes.insert(acceptedFrame.sourceIndex)
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
                previousResolvedFrame = originalFrame
                resolvedSourceIndexes.insert(acceptedFrame.sourceIndex)
                hasOutputProgress = true
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
                previousResolvedFrame = originalFrame
                resolvedSourceIndexes.insert(acceptedFrame.sourceIndex)
                hasOutputProgress = true
                continue
            }

            guard skippedFrameCount < maximumSkippedFrames else {
                throw ScrollingScreenshotStitchingError.noReliableOverlap
            }
            skippedFrameCount += 1
        }

        guard hasOutputProgress else {
            throw ScrollingScreenshotStitchingError.noScrollProgress
        }

        if requiresRecentFrame {
            let recentStartIndex = max(0, frames.count - 2)
            guard (recentStartIndex..<frames.count).contains(where: resolvedSourceIndexes.contains) else {
                throw ScrollingScreenshotStitchingError.noReliableOverlap
            }
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
    static let maximumAverageContainedChannelDifference: Double = 2
    static let meaningfulPixelDifference = 16
    static let maximumIdenticalFrameChangedPixelFraction = 0.00005
    static let maximumContainedFrameChangedPixelFraction = 0.00005
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

        return Self.regionsAreNearlyIdentical(
            pixels,
            startRow: 0,
            to: otherFrame.pixels,
            otherStartRow: 0,
            rowCount: height,
            width: width,
            maximumAverageDifference: Self.maximumAverageIdenticalChannelDifference,
            maximumChangedPixelFraction: Self.maximumIdenticalFrameChangedPixelFraction
        )
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
        let minimumOverlap = min(
            maximumOverlap,
            max(1, nextFrame.height / 20)
        )

        let candidateOverlaps = prioritizedOverlaps(
            previousPixels: previousPixels,
            previousStartRow: max(0, previousHeight - maximumOverlap),
            previousHeight: maximumOverlap,
            nextPixels: nextFrame.pixels,
            nextStartRow: 0,
            nextHeight: nextFrame.height,
            width: previousWidth,
            minimumOverlap: minimumOverlap,
            maximumOverlap: maximumOverlap,
            preferredOverlap: preferredOverlap
        )

        var bestCandidate: OverlapCandidate?
        for overlap in candidateOverlaps {
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
        let minimumOverlap = min(
            maximumOverlap,
            max(1, nextFrame.height / 20)
        )

        let candidateOverlaps = prioritizedOverlaps(
            previousPixels: nextFrame.pixels,
            previousStartRow: nextFrame.height - maximumOverlap,
            previousHeight: maximumOverlap,
            nextPixels: previousPixels,
            nextStartRow: contentStartRow,
            nextHeight: contentHeight,
            width: previousWidth,
            minimumOverlap: minimumOverlap,
            maximumOverlap: maximumOverlap,
            preferredOverlap: preferredOverlap
        )

        var bestCandidate: OverlapCandidate?
        for overlap in candidateOverlaps {
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

    private static func prioritizedOverlaps(
        previousPixels: [UInt8],
        previousStartRow: Int,
        previousHeight: Int,
        nextPixels: [UInt8],
        nextStartRow: Int,
        nextHeight: Int,
        width: Int,
        minimumOverlap: Int,
        maximumOverlap: Int,
        preferredOverlap: Int?
    ) -> [Int] {
        let previousSignatures = rowSignatures(
            in: previousPixels,
            width: width,
            startRow: previousStartRow,
            rowCount: previousHeight
        )
        let nextSignatures = rowSignatures(
            in: nextPixels,
            width: width,
            startRow: nextStartRow,
            rowCount: nextHeight
        )
        guard previousSignatures.count >= maximumOverlap,
              nextSignatures.count >= maximumOverlap else {
            return Array(stride(from: maximumOverlap, through: minimumOverlap, by: -1))
        }

        var ranked: [RowSignatureOverlapCandidate] = []
        for overlap in minimumOverlap...maximumOverlap {
            let previousOffset = previousSignatures.count - overlap
            var totalDifference = 0
            for row in 0..<overlap {
                totalDifference += previousSignatures[previousOffset + row]
                    .difference(from: nextSignatures[row])
            }
            let candidate = RowSignatureOverlapCandidate(
                overlap: overlap,
                averageDifference: Double(totalDifference) / Double(overlap),
                preferredDistance: preferredOverlap.map { abs(overlap - $0) } ?? 0
            )
            ranked.append(candidate)
        }

        ranked.sort()
        var selected = ranked.prefix(maximumDetailedOverlapCandidates).map(\.overlap)
        if let preferredOverlap {
            selected.append(min(max(preferredOverlap, minimumOverlap), maximumOverlap))
        }
        return Array(Set(selected)).sorted(by: >)
    }

    private static func rowSignatures(
        in pixels: [UInt8],
        width: Int,
        startRow: Int,
        rowCount: Int
    ) -> [RowSignature] {
        guard width > 0,
              startRow >= 0,
              rowCount > 0,
              (startRow + rowCount) * width * bytesPerPixel <= pixels.count else {
            return []
        }

        let bytesPerRow = width * bytesPerPixel
        return (0..<rowCount).map { relativeRow in
            let rowStart = (startRow + relativeRow) * bytesPerRow
            var red = 0
            var green = 0
            var blue = 0
            var alpha = 0
            for pixelOffset in stride(from: rowStart, to: rowStart + bytesPerRow, by: bytesPerPixel) {
                red += Int(pixels[pixelOffset])
                green += Int(pixels[pixelOffset + 1])
                blue += Int(pixels[pixelOffset + 2])
                alpha += Int(pixels[pixelOffset + 3])
            }
            return RowSignature(
                red: red / width,
                green: green / width,
                blue: blue / width,
                alpha: alpha / width
            )
        }
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

    func commonBottomRowCount(with otherFrame: PixelFrame) -> Int {
        guard width == otherFrame.width else {
            return 0
        }

        let maximumRows = min(height, otherFrame.height) - 1
        guard maximumRows > 0 else {
            return 0
        }

        var commonRows = 0
        for offset in 0..<maximumRows {
            let row = height - offset - 1
            let otherRow = otherFrame.height - offset - 1
            if Self.averageChannelDifference(
                from: pixels,
                startRow: row,
                to: otherFrame.pixels,
                otherStartRow: otherRow,
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

    func droppingEdgeRows(top: Int, bottom: Int) -> PixelFrame {
        let topRowCount = min(max(top, 0), height)
        let bottomRowCount = min(max(bottom, 0), height - topRowCount)
        let remainingHeight = height - topRowCount - bottomRowCount
        guard remainingHeight > 0 else {
            return PixelFrame(width: width, height: 0, pixels: [])
        }

        let bytesPerRow = width * Self.bytesPerPixel
        let startOffset = topRowCount * bytesPerRow
        let endOffset = startOffset + remainingHeight * bytesPerRow
        return PixelFrame(
            width: width,
            height: remainingHeight,
            pixels: Array(pixels[startOffset..<endOffset])
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

            if regionsAreNearlyIdentical(
                previousPixels,
                startRow: startRow,
                to: otherFrame.pixels,
                otherStartRow: 0,
                rowCount: otherFrame.height,
                width: width,
                maximumAverageDifference: Self.maximumAverageContainedChannelDifference,
                maximumChangedPixelFraction: Self.maximumContainedFrameChangedPixelFraction
            ) {
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

    private static func regionsAreNearlyIdentical(
        _ firstPixels: [UInt8],
        startRow: Int,
        to secondPixels: [UInt8],
        otherStartRow: Int,
        rowCount: Int,
        width: Int,
        maximumAverageDifference: Double,
        maximumChangedPixelFraction: Double
    ) -> Bool {
        guard startRow >= 0,
              otherStartRow >= 0,
              rowCount > 0 else {
            return false
        }

        let bytesPerRow = width * bytesPerPixel
        let startOffset = startRow * bytesPerRow
        let otherStartOffset = otherStartRow * bytesPerRow
        let byteCount = rowCount * bytesPerRow
        guard startOffset + byteCount <= firstPixels.count,
              otherStartOffset + byteCount <= secondPixels.count else {
            return false
        }

        let maximumTotalDifference = Int(maximumAverageDifference * Double(byteCount))
        let maximumChangedPixelCount = Int(Double(width * rowCount) * maximumChangedPixelFraction)
        var totalDifference = 0
        var changedPixelCount = 0
        for relativePixelOffset in stride(from: 0, to: byteCount, by: bytesPerPixel) {
            var hasMeaningfulDifference = false
            for channelOffset in 0..<bytesPerPixel {
                let firstIndex = startOffset + relativePixelOffset + channelOffset
                let secondIndex = otherStartOffset + relativePixelOffset + channelOffset
                let difference = abs(Int(firstPixels[firstIndex]) - Int(secondPixels[secondIndex]))
                totalDifference += difference
                hasMeaningfulDifference = hasMeaningfulDifference || difference > meaningfulPixelDifference
            }
            if totalDifference > maximumTotalDifference {
                return false
            }
            if hasMeaningfulDifference {
                changedPixelCount += 1
                if changedPixelCount > maximumChangedPixelCount {
                    return false
                }
            }
        }

        return true
    }

    struct OverlapCandidate {
        let overlap: Int
        let difference: Double
        let preferredDistance: Int

        var confidence: Double {
            max(0, min(1, 1 - difference / maximumAverageChannelDifference))
        }

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

    private struct RowSignature {
        let red: Int
        let green: Int
        let blue: Int
        let alpha: Int

        func difference(from other: RowSignature) -> Int {
            abs(red - other.red)
                + abs(green - other.green)
                + abs(blue - other.blue)
                + abs(alpha - other.alpha)
        }
    }

    private struct RowSignatureOverlapCandidate: Comparable {
        let overlap: Int
        let averageDifference: Double
        let preferredDistance: Int

        static func < (lhs: RowSignatureOverlapCandidate, rhs: RowSignatureOverlapCandidate) -> Bool {
            if abs(lhs.averageDifference - rhs.averageDifference) > candidateDifferenceTieTolerance {
                return lhs.averageDifference < rhs.averageDifference
            }
            return lhs.preferredDistance < rhs.preferredDistance
        }
    }

    private static let maximumDetailedOverlapCandidates = 8
}

private struct PixelFrameFingerprint {
    private static let sampleColumns = 32
    private static let sampleRows = 32
    private static let maximumAverageDifference: Double = 3
    private static let maximumChangedSampleFraction: Double = 0.05
    private static let meaningfulDifference = 12

    let width: Int
    let height: Int
    let samples: [UInt8]

    init(_ frame: PixelFrame) {
        width = frame.width
        height = frame.height
        guard frame.width > 0,
              frame.height > 0 else {
            samples = []
            return
        }

        let columnCount = min(Self.sampleColumns, frame.width)
        let rowCount = min(Self.sampleRows, frame.height)
        var samples: [UInt8] = []
        samples.reserveCapacity(columnCount * rowCount * PixelFrame.bytesPerPixel)
        for sampleRow in 0..<rowCount {
            let row = min(frame.height - 1, sampleRow * frame.height / rowCount)
            for sampleColumn in 0..<columnCount {
                let column = min(frame.width - 1, sampleColumn * frame.width / columnCount)
                let offset = (row * frame.width + column) * PixelFrame.bytesPerPixel
                samples.append(contentsOf: frame.pixels[offset..<(offset + PixelFrame.bytesPerPixel)])
            }
        }
        self.samples = samples
    }

    func matches(_ other: PixelFrameFingerprint) -> Bool {
        guard width == other.width,
              height == other.height,
              samples.count == other.samples.count,
              !samples.isEmpty else {
            return false
        }

        let maximumTotalDifference = Int(
            Self.maximumAverageDifference * Double(samples.count)
        )
        let samplePixelCount = samples.count / PixelFrame.bytesPerPixel
        let maximumChangedSampleCount = Int(
            Double(samplePixelCount) * Self.maximumChangedSampleFraction
        )
        var totalDifference = 0
        var changedSampleCount = 0
        for offset in stride(from: 0, to: samples.count, by: PixelFrame.bytesPerPixel) {
            var hasMeaningfulDifference = false
            for channel in 0..<PixelFrame.bytesPerPixel {
                let difference = abs(Int(samples[offset + channel]) - Int(other.samples[offset + channel]))
                totalDifference += difference
                hasMeaningfulDifference = hasMeaningfulDifference || difference > Self.meaningfulDifference
            }
            if totalDifference > maximumTotalDifference {
                return false
            }
            if hasMeaningfulDifference {
                changedSampleCount += 1
                if changedSampleCount > maximumChangedSampleCount {
                    return false
                }
            }
        }
        return true
    }
}
