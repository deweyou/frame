import AppKit
import XCTest
@testable import FrameApp

final class ScrollingScreenshotIncrementalPipelineTests: XCTestCase {
    func testIngestCanRunFromDetachedBackgroundTask() async throws {
        let pipeline = UncheckedSendableBox(
            ScrollingScreenshotIncrementalPipeline(previewMaximumPixelWidth: 4)
        )
        let frame = try makeFrame(rows: [.red, .green, .blue, .yellow])

        let sample = try await Task.detached {
            try pipeline.value.ingest(frame)
        }.value

        XCTAssertEqual(sample.progress.state, .initialized)
        XCTAssertNotNil(sample.previewImage)
    }

    func testAcceptedFramesProducePreviewAndFinishEncodesAcceptedCanvas() throws {
        let pipeline = ScrollingScreenshotIncrementalPipeline(previewMaximumPixelWidth: 4)
        let first = try makeFrame(rows: [.red, .green, .blue, .yellow])
        let second = try makeFrame(rows: [.blue, .yellow, .cyan, .magenta])

        let initial = try pipeline.ingest(first)
        let appended = try pipeline.ingest(second)
        let output = try pipeline.finish(outputID: UUID())

        XCTAssertEqual(initial.progress.state, .initialized)
        XCTAssertNotNil(initial.previewImage)
        XCTAssertEqual(appended.progress.state, .appended)
        XCTAssertEqual(appended.progress.totalPixelHeight, 6)
        XCTAssertNotNil(appended.previewImage)
        XCTAssertFalse(output.pngData.isEmpty)
        XCTAssertEqual(output.image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 6)
    }

    func testRejectedFramePreservesLastAcceptedPreviewAndFinalCanvas() throws {
        let pipeline = ScrollingScreenshotIncrementalPipeline(previewMaximumPixelWidth: 4)
        _ = try pipeline.ingest(try makeFrame(rows: [.red, .green, .blue, .yellow]))

        let rejected = try pipeline.ingest(
            try makeFrame(rows: [.white, .black, .cyan, .magenta])
        )
        let output = try pipeline.finish(outputID: UUID())

        XCTAssertEqual(rejected.progress.state, .unreliableOverlap)
        XCTAssertNil(rejected.previewImage)
        XCTAssertEqual(output.image.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height, 4)
    }

    private func makeFrame(rows: [TestColor], width: Int = 4) throws -> ScrollingScreenshotProcessingFrame {
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
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: rows.count,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw TestError.imageCreationFailed
        }
        return ScrollingScreenshotProcessingFrame(
            image: image,
            scale: 1,
            rect: CGRect(x: 10, y: 20, width: width, height: rows.count)
        )
    }
}

private struct TestColor {
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

private final class UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
