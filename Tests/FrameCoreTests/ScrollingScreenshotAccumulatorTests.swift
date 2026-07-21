import CoreGraphics
import XCTest
@testable import FrameCore

final class ScrollingScreenshotAccumulatorTests: XCTestCase {
    func testInitialFrameCreatesCanvasWithoutReportingScrollProgress() throws {
        let accumulator = ScrollingScreenshotAccumulator()
        let frame = try makeFrame(rows: [.red, .green, .blue, .yellow])

        let progress = try accumulator.ingest(frame)

        XCTAssertEqual(progress.state, .initialized)
        XCTAssertEqual(progress.appendedPixelHeight, 4)
        XCTAssertEqual(progress.totalPixelHeight, 4)
        XCTAssertNil(progress.verticalDisplacement)
        XCTAssertFalse(accumulator.hasScrollProgress)
    }

    func testReliableFrameAppendsOnlyNewRows() throws {
        let accumulator = ScrollingScreenshotAccumulator()
        _ = try accumulator.ingest(try makeFrame(rows: [.red, .green, .blue, .yellow]))

        let progress = try accumulator.ingest(
            try makeFrame(rows: [.blue, .yellow, .cyan, .magenta])
        )

        XCTAssertEqual(progress.state, .appended)
        XCTAssertEqual(progress.appendedPixelHeight, 2)
        XCTAssertEqual(progress.totalPixelHeight, 6)
        XCTAssertEqual(progress.verticalDisplacement, 2)
        XCTAssertGreaterThan(progress.confidence, 0.9)
        XCTAssertTrue(accumulator.hasScrollProgress)
        XCTAssertEqual(
            try rowColors(in: accumulator.makeImage()),
            [.red, .green, .blue, .yellow, .cyan, .magenta]
        )
    }

    func testIdenticalFrameReportsNoProgressWithoutChangingCanvas() throws {
        let accumulator = ScrollingScreenshotAccumulator()
        let frame = try makeFrame(rows: [.red, .green, .blue, .yellow])
        _ = try accumulator.ingest(frame)

        let progress = try accumulator.ingest(frame)

        XCTAssertEqual(progress.state, .noProgress)
        XCTAssertEqual(progress.appendedPixelHeight, 0)
        XCTAssertEqual(progress.totalPixelHeight, 4)
        XCTAssertEqual(try rowColors(in: accumulator.makeImage()), [.red, .green, .blue, .yellow])
    }

    func testUnmatchedFrameDoesNotPoisonAcceptedCanvas() throws {
        let accumulator = ScrollingScreenshotAccumulator()
        _ = try accumulator.ingest(try makeFrame(rows: [.red, .green, .blue, .yellow]))

        let rejected = try accumulator.ingest(
            try makeFrame(rows: [.white, .black, .cyan, .magenta])
        )
        let recovered = try accumulator.ingest(
            try makeFrame(rows: [.blue, .yellow, .cyan, .magenta])
        )

        XCTAssertEqual(rejected.state, .unreliableOverlap)
        XCTAssertEqual(rejected.totalPixelHeight, 4)
        XCTAssertEqual(recovered.state, .appended)
        XCTAssertEqual(
            try rowColors(in: accumulator.makeImage()),
            [.red, .green, .blue, .yellow, .cyan, .magenta]
        )
    }

    func testPreviouslyAcceptedFrameReportsHistoricalRepeat() throws {
        let accumulator = ScrollingScreenshotAccumulator()
        let first = try makeFrame(rows: [.red, .green, .blue, .yellow])
        _ = try accumulator.ingest(first)
        _ = try accumulator.ingest(try makeFrame(rows: [.blue, .yellow, .cyan, .magenta]))

        let progress = try accumulator.ingest(first)

        XCTAssertEqual(progress.state, .historicalRepeat)
        XCTAssertEqual(progress.totalPixelHeight, 6)
        XCTAssertEqual(
            try rowColors(in: accumulator.makeImage()),
            [.red, .green, .blue, .yellow, .cyan, .magenta]
        )
    }

    func testStaticBottomBandIsKeptOnceAndExcludedFromOverlap() throws {
        let accumulator = ScrollingScreenshotAccumulator()
        _ = try accumulator.ingest(
            try makeFrame(rows: [.red, .green, .blue, .yellow, .black])
        )

        let progress = try accumulator.ingest(
            try makeFrame(rows: [.blue, .yellow, .cyan, .magenta, .black])
        )

        XCTAssertEqual(progress.state, .appended)
        XCTAssertEqual(
            try rowColors(in: accumulator.makeImage()),
            [.red, .green, .blue, .yellow, .cyan, .magenta, .black]
        )
    }

    func testResourceLimitRejectsAppendWithoutChangingCanvas() throws {
        let accumulator = ScrollingScreenshotAccumulator(
            configuration: ScrollingScreenshotAccumulatorConfiguration(
                maximumCanvasBytes: 80,
                maximumHistoricalFingerprints: 8
            )
        )
        _ = try accumulator.ingest(try makeFrame(rows: [.red, .green, .blue, .yellow]))

        XCTAssertThrowsError(
            try accumulator.ingest(
                try makeFrame(rows: [.blue, .yellow, .cyan, .magenta])
            )
        ) { error in
            XCTAssertEqual(error as? ScrollingScreenshotStitchingError, .resourceLimitExceeded)
        }
        XCTAssertEqual(accumulator.totalPixelHeight, 4)
        XCTAssertEqual(try rowColors(in: accumulator.makeImage()), [.red, .green, .blue, .yellow])
    }

    func testLongCaptureKeepsHistoricalMetadataBounded() throws {
        let accumulator = ScrollingScreenshotAccumulator(
            configuration: ScrollingScreenshotAccumulatorConfiguration(
                maximumCanvasBytes: 1_024 * 1_024,
                maximumHistoricalFingerprints: 4
            )
        )

        for startRow in stride(from: 0, through: 80, by: 5) {
            var rows: [TestColor] = []
            for value in startRow..<(startRow + 20) {
                rows.append(TestColor(
                    r: UInt8(value),
                    g: UInt8(255 - value),
                    b: UInt8((value * 3) % 255)
                ))
            }
            _ = try accumulator.ingest(try makeFrame(rows: rows, width: 8))
        }

        XCTAssertEqual(accumulator.totalPixelHeight, 100)
        XCTAssertEqual(accumulator.retainedHistoricalFingerprintCountForTesting, 4)
    }

    private func makeFrame(rows: [TestColor], width: Int = 4) throws -> ScrollingScreenshotFrame {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: rows.count * bytesPerRow)
        for (rowIndex, color) in rows.enumerated() {
            for column in 0..<width {
                let offset = rowIndex * bytesPerRow + column * bytesPerPixel
                pixels[offset] = color.r
                pixels[offset + 1] = color.g
                pixels[offset + 2] = color.b
                pixels[offset + 3] = 255
            }
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: rows.count,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw TestError.imageCreationFailed
        }
        return ScrollingScreenshotFrame(image: image, scale: 1)
    }

    private func rowColors(in image: CGImage) throws -> [TestColor] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        guard let context = CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestError.imageCreationFailed
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return (0..<image.height).map { row in
            let offset = row * bytesPerRow
            return TestColor(
                r: pixels[offset],
                g: pixels[offset + 1],
                b: pixels[offset + 2]
            )
        }
    }
}

private struct TestColor: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    static let red = TestColor(r: 255, g: 0, b: 0)
    static let green = TestColor(r: 0, g: 255, b: 0)
    static let blue = TestColor(r: 0, g: 0, b: 255)
    static let yellow = TestColor(r: 255, g: 255, b: 0)
    static let cyan = TestColor(r: 0, g: 255, b: 255)
    static let magenta = TestColor(r: 255, g: 0, b: 255)
    static let black = TestColor(r: 0, g: 0, b: 0)
    static let white = TestColor(r: 255, g: 255, b: 255)
}

private enum TestError: Error {
    case imageCreationFailed
}
