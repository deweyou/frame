import CoreGraphics
import XCTest
@testable import FrameCore

final class ScrollingScreenshotStitcherTests: XCTestCase {
    func testStitchesTwoFramesWithKnownVerticalOverlap() throws {
        let first = try makeStripedImage(rows: [
            .red, .green, .blue, .yellow,
        ])
        let second = try makeStripedImage(rows: [
            .blue, .yellow, .cyan, .magenta,
        ])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
        ])

        XCTAssertEqual(output.width, first.width)
        XCTAssertEqual(output.height, 6)
        XCTAssertEqual(try rowColors(in: output), [.red, .green, .blue, .yellow, .cyan, .magenta])
    }

    func testStitchesMultipleFramesWithRepeatedOverlap() throws {
        let first = try makeStripedImage(rows: [.red, .green, .blue, .yellow])
        let second = try makeStripedImage(rows: [.blue, .yellow, .cyan, .magenta])
        let third = try makeStripedImage(rows: [.cyan, .magenta, .white, .black])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
            ScrollingScreenshotFrame(image: third, scale: 1),
        ])

        XCTAssertEqual(try rowColors(in: output), [
            .red, .green, .blue, .yellow, .cyan, .magenta, .white, .black,
        ])
    }

    func testStitchesFramesWhenUserScrollsUp() throws {
        let first = try makeStripedImage(rows: [.blue, .yellow, .cyan, .magenta])
        let second = try makeStripedImage(rows: [.red, .green, .blue, .yellow])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
        ])

        XCTAssertEqual(try rowColors(in: output), [.red, .green, .blue, .yellow, .cyan, .magenta])
    }

    func testStitchesMultipleFramesWhenUserScrollsUp() throws {
        let first = try makeSparseMarkerImage(markerColumns: [50, 60, 70, 80, 90, 100])
        let second = try makeSparseMarkerImage(markerColumns: [30, 40, 50, 60, 70, 80])
        let third = try makeSparseMarkerImage(markerColumns: [10, 20, 30, 40, 50, 60])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
            ScrollingScreenshotFrame(image: third, scale: 1),
        ])

        XCTAssertEqual(try markerColumns(in: output), [10, 20, 30, 40, 50, 60, 70, 80, 90, 100])
    }

    func testSkipsIdenticalFramesAsNoProgress() throws {
        let first = try makeStripedImage(rows: [.red, .green, .blue])
        let third = try makeStripedImage(rows: [.blue, .yellow, .cyan])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: third, scale: 1),
        ])

        XCTAssertEqual(try rowColors(in: output), [.red, .green, .blue, .yellow, .cyan])
    }

    func testStitchesFramesWhenOverlapHasMinorPixelNoise() throws {
        let first = try makeStripedImage(rows: [.red, .green, .blue, .yellow])
        let second = try makeStripedImage(rows: [.blue, .yellow, .cyan, .magenta], pixelNoise: 2, noisyRows: 0..<2)
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
        ])

        XCTAssertEqual(output.height, 6)
        XCTAssertEqual(try rowColors(in: output), [.red, .green, .blue, .yellow, .cyan, .magenta])
    }

    func testStitchesFramesWithRepeatedFixedTopChrome() throws {
        let first = try makeStripedImage(rows: [.white, .black, .red, .green, .blue, .yellow])
        let second = try makeStripedImage(rows: [.white, .black, .blue, .yellow, .cyan, .magenta])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
        ])

        XCTAssertEqual(output.height, 8)
        XCTAssertEqual(try rowColors(in: output), [.white, .black, .red, .green, .blue, .yellow, .cyan, .magenta])
    }

    func testStitchesFramesWhenUserScrollsUpWithRepeatedFixedTopChrome() throws {
        let first = try makeStripedImage(rows: [.white, .black, .blue, .yellow, .cyan, .magenta])
        let second = try makeStripedImage(rows: [.white, .black, .red, .green, .blue, .yellow])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
        ])

        XCTAssertEqual(output.height, 8)
        XCTAssertEqual(try rowColors(in: output), [.white, .black, .red, .green, .blue, .yellow, .cyan, .magenta])
    }

    func testChoosesLowestDifferenceOverlapForSparseTextRows() throws {
        let first = try makeSparseMarkerImage(markerColumns: [10, 30, 50, 70, 90, 110])
        let second = try makeSparseMarkerImage(markerColumns: [70, 90, 110, 20, 40, 60])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
        ])

        XCTAssertEqual(output.height, 9)
        XCTAssertEqual(try markerColumns(in: output), [10, 30, 50, 70, 90, 110, 20, 40, 60])
    }

    func testSkipsFrameAlreadyContainedInOutputAfterRubberBandBounce() throws {
        let first = try makeStripedImage(rows: [.white, .black, .red, .green, .blue, .yellow])
        let second = try makeStripedImage(rows: [.white, .black, .blue, .yellow, .cyan, .magenta])
        let bouncedBack = try makeStripedImage(rows: [.white, .black, .green, .blue, .yellow, .cyan])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
            ScrollingScreenshotFrame(image: bouncedBack, scale: 1),
        ])

        XCTAssertEqual(output.height, 8)
        XCTAssertEqual(try rowColors(in: output), [.white, .black, .red, .green, .blue, .yellow, .cyan, .magenta])
    }

    func testSkipsFrameAlreadyContainedNearTopAfterUpwardRubberBandBounce() throws {
        let first = try makeStripedImage(rows: [.cyan, .magenta, .white, .black])
        let second = try makeStripedImage(rows: [.blue, .yellow, .cyan, .magenta])
        let bouncedBack = try makeStripedImage(rows: [.yellow, .cyan, .magenta, .white])
        let stitcher = ScrollingScreenshotStitcher()

        let output = try stitcher.stitch([
            ScrollingScreenshotFrame(image: first, scale: 1),
            ScrollingScreenshotFrame(image: second, scale: 1),
            ScrollingScreenshotFrame(image: bouncedBack, scale: 1),
        ])

        XCTAssertEqual(try rowColors(in: output), [.blue, .yellow, .cyan, .magenta, .white, .black])
    }

    func testSkipsNearlyIdenticalFramesAsNoProgress() throws {
        let image = try makeStripedImage(rows: [.red, .green, .blue])
        let noisyImage = try makeStripedImage(rows: [.red, .green, .blue], pixelNoise: 2, noisyRows: 0..<3)
        let stitcher = ScrollingScreenshotStitcher()

        XCTAssertThrowsError(try stitcher.stitch([
            ScrollingScreenshotFrame(image: image, scale: 1),
            ScrollingScreenshotFrame(image: noisyImage, scale: 1),
        ])) { error in
            XCTAssertEqual(error as? ScrollingScreenshotStitchingError, .noScrollProgress)
        }
    }

    func testFailsWithFewerThanTwoFrames() throws {
        let stitcher = ScrollingScreenshotStitcher()

        XCTAssertThrowsError(try stitcher.stitch([
            ScrollingScreenshotFrame(image: try makeStripedImage(rows: [.red, .green]), scale: 1),
        ])) { error in
            XCTAssertEqual(error as? ScrollingScreenshotStitchingError, .insufficientFrames)
        }
    }

    func testFailsWhenThereIsNoScrollProgress() throws {
        let image = try makeStripedImage(rows: [.red, .green, .blue])
        let stitcher = ScrollingScreenshotStitcher()

        XCTAssertThrowsError(try stitcher.stitch([
            ScrollingScreenshotFrame(image: image, scale: 1),
            ScrollingScreenshotFrame(image: image, scale: 1),
        ])) { error in
            XCTAssertEqual(error as? ScrollingScreenshotStitchingError, .noScrollProgress)
        }
    }

    func testFailsWhenThereIsNoReliableOverlap() throws {
        let stitcher = ScrollingScreenshotStitcher()

        XCTAssertThrowsError(try stitcher.stitch([
            ScrollingScreenshotFrame(image: try makeStripedImage(rows: [.red, .green]), scale: 1),
            ScrollingScreenshotFrame(image: try makeStripedImage(rows: [.cyan, .magenta]), scale: 1),
        ])) { error in
            XCTAssertEqual(error as? ScrollingScreenshotStitchingError, .noReliableOverlap)
        }
    }

    func testProgressDetectorReportsChangedContentWithoutUsingStitching() throws {
        let previousImage = try makeStripedImage(rows: [.red, .green, .blue, .yellow], width: 40)
        let nextImage = try makeStripedImage(rows: [.blue, .yellow, .cyan, .magenta], width: 40)
        let detector = ScrollingScreenshotProgressDetector()

        XCTAssertTrue(detector.hasScrollProgress(
            from: ScrollingScreenshotFrame(image: previousImage, scale: 1),
            to: ScrollingScreenshotFrame(image: nextImage, scale: 1)
        ))
    }

    func testProgressDetectorRejectsNearlyIdenticalContent() throws {
        let image = try makeStripedImage(rows: [.red, .green, .blue, .yellow], width: 40)
        let noisyImage = try makeStripedImage(
            rows: [.red, .green, .blue, .yellow],
            width: 40,
            pixelNoise: 2,
            noisyRows: 0..<4
        )
        let detector = ScrollingScreenshotProgressDetector()

        XCTAssertFalse(detector.hasScrollProgress(
            from: ScrollingScreenshotFrame(image: image, scale: 1),
            to: ScrollingScreenshotFrame(image: noisyImage, scale: 1)
        ))
    }

    private func makeStripedImage(
        rows: [TestColor],
        width: Int = 3,
        pixelNoise: UInt8 = 0,
        noisyRows: Range<Int> = 0..<0
    ) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels: [UInt8] = []
        pixels.reserveCapacity(rows.count * bytesPerRow)
        for (rowIndex, color) in rows.enumerated() {
            for _ in 0..<width {
                if noisyRows.contains(rowIndex) {
                    pixels.append(contentsOf: color.rgba.map { channel in
                        channel == 255 ? 255 : min(255, channel + pixelNoise)
                    })
                } else {
                    pixels.append(contentsOf: color.rgba)
                }
            }
        }

        return try makeImage(width: width, height: rows.count, pixels: &pixels)
    }

    private func makeSparseMarkerImage(markerColumns: [Int], width: Int = 120) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 255, count: markerColumns.count * bytesPerRow)
        for (row, column) in markerColumns.enumerated() {
            let offset = row * bytesPerRow + column * bytesPerPixel
            pixels[offset] = 0
            pixels[offset + 1] = 0
            pixels[offset + 2] = 0
            pixels[offset + 3] = 255
        }

        return try makeImage(width: width, height: markerColumns.count, pixels: &pixels)
    }

    private func rowColors(in image: CGImage) throws -> [TestColor] {
        let pixels = try pixels(in: image)
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        return try (0..<image.height).map { row in
            let offset = row * bytesPerRow
            let rgba = Array(pixels[offset..<(offset + bytesPerPixel)])
            return try XCTUnwrap(TestColor(rgba: rgba))
        }
    }

    private func markerColumns(in image: CGImage) throws -> [Int] {
        let pixels = try pixels(in: image)
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        return (0..<image.height).compactMap { row in
            for column in 0..<image.width {
                let offset = row * bytesPerRow + column * bytesPerPixel
                if pixels[offset] == 0,
                   pixels[offset + 1] == 0,
                   pixels[offset + 2] == 0 {
                    return column
                }
            }

            return nil
        }
    }

    private func makeImage(width: Int, height: Int, pixels: inout [UInt8]) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func pixels(in image: CGImage) throws -> [UInt8] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: image.height * bytesPerRow)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}

private enum TestColor: Equatable {
    case red
    case green
    case blue
    case yellow
    case cyan
    case magenta
    case white
    case black

    init?(rgba: [UInt8]) {
        switch rgba {
        case Self.red.rgba: self = .red
        case Self.green.rgba: self = .green
        case Self.blue.rgba: self = .blue
        case Self.yellow.rgba: self = .yellow
        case Self.cyan.rgba: self = .cyan
        case Self.magenta.rgba: self = .magenta
        case Self.white.rgba: self = .white
        case Self.black.rgba: self = .black
        default: return nil
        }
    }

    var rgba: [UInt8] {
        switch self {
        case .red: [255, 0, 0, 255]
        case .green: [0, 255, 0, 255]
        case .blue: [0, 0, 255, 255]
        case .yellow: [255, 255, 0, 255]
        case .cyan: [0, 255, 255, 255]
        case .magenta: [255, 0, 255, 255]
        case .white: [255, 255, 255, 255]
        case .black: [0, 0, 0, 255]
        }
    }
}
