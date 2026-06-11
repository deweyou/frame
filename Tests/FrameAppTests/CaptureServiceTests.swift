import AppKit
import ScreenCaptureKit
import XCTest
@testable import FrameApp

final class CaptureServiceTests: XCTestCase {
    func testSoftBackdropDecorationAddsCanvasAroundWindowImage() throws {
        let sourceImage = try makeSolidImage(width: 20, height: 12, red: 40, green: 50, blue: 60, alpha: 255)
        let decoratedImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .softBackdrop
        ))

        XCTAssertGreaterThan(decoratedImage.width, sourceImage.width)
        XCTAssertGreaterThan(decoratedImage.height, sourceImage.height)
        XCTAssertNotEqual(try pixel(at: CGPoint(x: 0, y: 0), in: decoratedImage).alpha, 0)
    }

    func testSoftBackdropDecorationScalesWindowToRevealBackground() throws {
        let sourceImage = try makeSolidImage(width: 1000, height: 600, red: 40, green: 50, blue: 60, alpha: 255)
        let decoratedImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .softBackdrop
        ))

        XCTAssertNotEqual(
            try pixel(at: CGPoint(x: 60, y: decoratedImage.height / 2), in: decoratedImage),
            TestPixel(red: 40, green: 50, blue: 60, alpha: 255)
        )
    }

    func testSoftBackdropDecorationUsesVisibleRoundedWindowCorners() throws {
        let sourceImage = try makeSolidImage(width: 1000, height: 600, red: 40, green: 50, blue: 60, alpha: 255)
        let decoratedImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .softBackdrop
        ))

        XCTAssertNotEqual(
            try pixel(at: CGPoint(x: 85, y: decoratedImage.height - 77), in: decoratedImage),
            TestPixel(red: 40, green: 50, blue: 60, alpha: 255)
        )
    }

    func testSoftBackdropDecorationShowsShadowBelowLargeWindow() throws {
        let sourceImage = try makeSolidImage(width: 1000, height: 600, red: 40, green: 50, blue: 60, alpha: 255)
        let decoratedImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .softBackdrop
        ))

        let backgroundPixel = try pixel(at: CGPoint(x: 60, y: decoratedImage.height / 2), in: decoratedImage)
        let shadowPixel = try pixel(at: CGPoint(x: decoratedImage.width / 2, y: 65), in: decoratedImage)

        XCTAssertNotEqual(shadowPixel, backgroundPixel)
    }

    func testDecorationStylesUseConsistentCanvasGeometry() throws {
        let sourceImage = try makeSolidImage(width: 1000, height: 600, red: 40, green: 50, blue: 60, alpha: 255)
        let softImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .softBackdrop
        ))
        let canvasImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .canvasGlow
        ))

        XCTAssertEqual(canvasImage.width, softImage.width)
        XCTAssertEqual(canvasImage.height, softImage.height)
        XCTAssertNotEqual(
            try pixel(at: CGPoint(x: 0, y: 0), in: canvasImage),
            try pixel(at: CGPoint(x: 0, y: 0), in: softImage)
        )
    }

    func testDecorationStylesUseConsistentWindowContentScale() {
        let sourceSize = CGSize(width: 1000, height: 600)
        let softLayout = WindowScreenshotDecorationLayout(sourceSize: sourceSize, style: .softBackdrop)
        let canvasLayout = WindowScreenshotDecorationLayout(sourceSize: sourceSize, style: .canvasGlow)
        let transparentLayout = WindowScreenshotDecorationLayout(sourceSize: sourceSize, style: .transparentShadow)

        XCTAssertEqual(canvasLayout.canvasSize, softLayout.canvasSize)
        XCTAssertEqual(transparentLayout.canvasSize, softLayout.canvasSize)
        XCTAssertEqual(canvasLayout.imageRect, softLayout.imageRect)
        XCTAssertEqual(transparentLayout.imageRect, softLayout.imageRect)
        XCTAssertEqual(canvasLayout.imageRect.size, softLayout.imageRect.size)
        XCTAssertEqual(transparentLayout.imageRect.size, softLayout.imageRect.size)
    }

    func testTransparentShadowDecorationKeepsCanvasCornersTransparent() throws {
        let sourceImage = try makeSolidImage(width: 20, height: 12, red: 40, green: 50, blue: 60, alpha: 255)
        let decoratedImage = try XCTUnwrap(WindowScreenshotDecorator().decoratedImage(
            from: sourceImage,
            style: .transparentShadow
        ))

        XCTAssertGreaterThan(decoratedImage.width, sourceImage.width)
        XCTAssertGreaterThan(decoratedImage.height, sourceImage.height)
        XCTAssertEqual(try pixel(at: CGPoint(x: 0, y: 0), in: decoratedImage).alpha, 0)
    }

    func testCroppedToVisibleContentRemovesTransparentWindowMargins() throws {
        let image = try makeImageWithTransparentMargins()
        let croppedImage = try XCTUnwrap(croppedToVisibleContent(image))

        XCTAssertEqual(croppedImage.width, 6)
        XCTAssertEqual(croppedImage.height, 5)
        try assertOpaqueWhiteEdges(croppedImage)
    }

    func testCroppedToVisibleContentRemovesTransparentWindowShadowMargins() throws {
        let image = try makeImageWithTransparentShadowMargins()
        let croppedImage = try XCTUnwrap(croppedToVisibleContent(image))

        XCTAssertEqual(croppedImage.width, 6)
        XCTAssertEqual(croppedImage.height, 5)
        try assertOpaqueWhiteEdges(croppedImage)
    }

    func testCroppedToVisibleContentRejectsFullyTransparentImages() throws {
        let image = try makeTransparentImage(width: 8, height: 8)

        XCTAssertNil(croppedToVisibleContent(image))
    }

    func testSingleWindowCaptureConfigurationIgnoresWindowShadows() {
        let configuration = makeSingleWindowCaptureConfiguration(
            rect: CGRect(x: 0, y: 0, width: 240, height: 160),
            scale: 2
        )

        XCTAssertEqual(configuration.width, 480)
        XCTAssertEqual(configuration.height, 320)
        XCTAssertFalse(configuration.showsCursor)
        XCTAssertTrue(configuration.ignoreShadowsSingleWindow)
    }

    func testFullScreenRectsPreserveOneRectPerScreen() {
        let screenFrames = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 1440, y: -180, width: 1280, height: 720),
        ]

        XCTAssertEqual(CaptureService.fullScreenRects(from: screenFrames), screenFrames)
    }

    private func makeImageWithTransparentMargins() throws -> CGImage {
        let width = 10
        let height = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 1..<6 {
            for x in 2..<8 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = 255
            }
        }

        return try makeImage(width: width, height: height, pixels: &pixels)
    }

    private func makeImageWithTransparentShadowMargins() throws -> CGImage {
        let width = 10
        let height = 8
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 48
            }
        }

        for y in 1..<6 {
            for x in 2..<8 {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = 255
                pixels[offset + 1] = 255
                pixels[offset + 2] = 255
                pixels[offset + 3] = 255
            }
        }

        return try makeImage(width: width, height: height, pixels: &pixels)
    }

    private func makeTransparentImage(width: Int, height: Int) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        return try makeImage(width: width, height: height, pixels: &pixels)
    }

    private func makeSolidImage(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8,
        alpha: UInt8
    ) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue
                pixels[offset + 3] = alpha
            }
        }

        return try makeImage(width: width, height: height, pixels: &pixels)
    }

    private func makeImage(width: Int, height: Int, pixels: inout [UInt8]) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        return try XCTUnwrap(context.makeImage())
    }

    private func assertOpaqueWhiteEdges(_ image: CGImage) throws {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        for y in 0..<height {
            for x in [0, width - 1] {
                try assertOpaqueWhitePixel(pixels, x: x, y: y, bytesPerRow: bytesPerRow)
            }
        }

        for x in 0..<width {
            for y in [0, height - 1] {
                try assertOpaqueWhitePixel(pixels, x: x, y: y, bytesPerRow: bytesPerRow)
            }
        }
    }

    private func assertOpaqueWhitePixel(_ pixels: [UInt8], x: Int, y: Int, bytesPerRow: Int) throws {
        let offset = y * bytesPerRow + x * 4
        XCTAssertEqual(pixels[offset], 255)
        XCTAssertEqual(pixels[offset + 1], 255)
        XCTAssertEqual(pixels[offset + 2], 255)
        XCTAssertEqual(pixels[offset + 3], 255)
    }

    private func pixel(at point: CGPoint, in image: CGImage) throws -> TestPixel {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = try XCTUnwrap(CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let x = Int(point.x)
        let y = Int(point.y)
        let offset = y * bytesPerRow + x * bytesPerPixel
        return TestPixel(
            red: pixels[offset],
            green: pixels[offset + 1],
            blue: pixels[offset + 2],
            alpha: pixels[offset + 3]
        )
    }
}

private struct TestPixel: Equatable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}
