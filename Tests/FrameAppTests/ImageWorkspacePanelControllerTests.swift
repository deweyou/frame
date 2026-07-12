import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class ImageWorkspacePanelControllerTests: XCTestCase {
    private var retainedControllers: [ImageWorkspacePanelController] = []
    private var temporaryDefaultsSuiteNames: [String] = []

    override func tearDown() async throws {
        for suiteName in temporaryDefaultsSuiteNames {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        temporaryDefaultsSuiteNames.removeAll()
        retainedControllers.removeAll()
    }

    func testImageAnnotationRendererPreservesScreenshotIDAndChangesPixels() throws {
        let screenshotID = UUID()
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .shape(.rectangle),
            bounds: CGRect(x: 12, y: 12, width: 28, height: 24),
            style: ImageAnnotationStyle(
                strokeColor: .red,
                fillColor: .red.withAlpha(1),
                lineWidth: 4,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 10,
                mosaicStrength: 0.8
            )
        ))

        let screenshot = try makeSolidScreenshot(id: screenshotID, color: .white)
        let rendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: document,
            preservingID: true
        )

        XCTAssertEqual(rendered.id, screenshotID)
        XCTAssertNotEqual(rendered.pngData, screenshot.pngData)
        XCTAssertNotEqual(try pixelColor(in: rendered.pngData, x: 18, y: 18), try pixelColor(in: screenshot.pngData, x: 18, y: 18))
    }

    func testImageAnnotationRendererAppliesMosaicBlocks() throws {
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .mosaic(.rectangle),
            bounds: CGRect(x: 0, y: 0, width: 32, height: 32),
            style: ImageAnnotationStyle(
                strokeColor: .blue,
                lineWidth: 4,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 16,
                mosaicStrength: 1
            )
        ))

        let screenshot = try makeGradientScreenshot()
        let rendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: document,
            preservingID: true
        )

        XCTAssertEqual(try pixelColor(in: rendered.pngData, x: 2, y: 2), try pixelColor(in: rendered.pngData, x: 14, y: 14))
        XCTAssertNotEqual(try pixelColor(in: screenshot.pngData, x: 2, y: 2), try pixelColor(in: screenshot.pngData, x: 14, y: 14))

        var largeBlockDocument = ImageAnnotationDocument()
        largeBlockDocument.add(ImageAnnotationElement(
            kind: .mosaic(.rectangle),
            bounds: CGRect(x: 0, y: 0, width: 32, height: 32),
            style: ImageAnnotationStyle(
                strokeColor: .blue,
                lineWidth: 4,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 32,
                mosaicStrength: 1
            )
        ))
        let largeBlockRendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: largeBlockDocument,
            preservingID: true
        )
        XCTAssertNotEqual(try pixelColor(in: rendered.pngData, x: 2, y: 2), try pixelColor(in: largeBlockRendered.pngData, x: 2, y: 2))
    }

    func testImageAnnotationRendererAveragesPixelsBeforeNearestUpscale() throws {
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .mosaic(.rectangle),
            bounds: CGRect(x: 0, y: 0, width: 32, height: 32),
            style: ImageAnnotationStyle(
                strokeColor: .blue,
                lineWidth: 4,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 16,
                mosaicStrength: 1
            )
        ))

        let screenshot = try makeCheckerboardScreenshot(size: CGSize(width: 32, height: 32))
        let rendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: document,
            preservingID: true
        )
        let color = try pixelColor(in: rendered.pngData, x: 4, y: 4)

        XCTAssertTrue((80...175).contains(Int(color[0])))
        XCTAssertTrue((80...175).contains(Int(color[1])))
        XCTAssertTrue((80...175).contains(Int(color[2])))
    }

    func testImageAnnotationRendererBrushMosaicUsesContinuousStrokeMask() throws {
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .mosaic(.brush),
            bounds: CGRect(x: 0, y: 4, width: 32, height: 24),
            points: [CGPoint(x: 4, y: 16), CGPoint(x: 28, y: 16)],
            style: ImageAnnotationStyle(
                strokeColor: .blue,
                lineWidth: 4,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 8,
                mosaicStrength: 1
            )
        ))

        let screenshot = try makeCheckerboardScreenshot(size: CGSize(width: 32, height: 32))
        let rendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: document,
            preservingID: true
        )

        XCTAssertNotEqual(try pixelColor(in: rendered.pngData, x: 16, y: 16), try pixelColor(in: screenshot.pngData, x: 16, y: 16))
        XCTAssertEqual(try pixelColor(in: rendered.pngData, x: 16, y: 31), try pixelColor(in: screenshot.pngData, x: 16, y: 31))
    }

    func testImageAnnotationCanvasPreviewsMosaicAsPixelBlocks() throws {
        let screenshot = try makeGradientScreenshot(size: CGSize(width: 32, height: 32))
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .mosaic(.rectangle),
            bounds: CGRect(x: 0, y: 0, width: 32, height: 32),
            style: ImageAnnotationStyle(
                strokeColor: .blue,
                lineWidth: 4,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 16,
                mosaicStrength: 1
            )
        ))

        let canvas = ImageAnnotationCanvasView(
            image: screenshot.image,
            document: document
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 32, height: 32)

        XCTAssertEqual(try pixelColor(in: canvas, x: 4, y: 4), try pixelColor(in: canvas, x: 12, y: 12))
        XCTAssertNotEqual(try pixelColor(in: screenshot.pngData, x: 4, y: 4), try pixelColor(in: screenshot.pngData, x: 12, y: 12))
    }

    func testImageAnnotationCanvasDefersRectangleMosaicPixelationUntilMouseUp() throws {
        let screenshot = try makeGradientScreenshot(size: CGSize(width: 32, height: 32))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 32, height: 32),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: screenshot.image,
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 32, height: 32)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.mosaic)
        canvas.setMosaicMode(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 0, y: 0), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 31, y: 31), panel: panel))

        XCTAssertNotEqual(try pixelColor(in: canvas, x: 4, y: 4), try pixelColor(in: canvas, x: 12, y: 12))

        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 31, y: 31), panel: panel))

        XCTAssertEqual(try pixelColor(in: canvas, x: 4, y: 4), try pixelColor(in: canvas, x: 12, y: 12))
    }

    func testImageAnnotationCanvasDrawsScaledShapeDraftUnderMouse() throws {
        let screenshot = try makeSolidScreenshot(color: .white, size: CGSize(width: 32, height: 24))
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 48),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: screenshot.image,
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 64, height: 48)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        var style = ImageAnnotationStyle.default
        style.fillColor = .red.withAlpha(1)
        canvas.setStyle(style)
        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.magnify(with: FakeMagnifyEvent(magnification: 1, locationInWindow: canvas.convert(canvas.bounds.center, to: nil)))
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 16), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 52, y: 36), panel: panel))

        let pixelUnderDrag = try pixelColor(in: canvas, x: 36, y: 26)
        XCTAssertGreaterThan(pixelUnderDrag[0], 180)
        XCTAssertLessThan(pixelUnderDrag[1], 180)
        XCTAssertLessThan(pixelUnderDrag[2], 180)
    }

    func testImageAnnotationCanvasStoresArrowFromMouseStartToEnd() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.arrow)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 140, y: 120), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 40, y: 60), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 40, y: 60), panel: panel))

        let arrow = try XCTUnwrap(canvas.documentForTesting.elements.first)
        XCTAssertEqual(arrow.kind, .shape(.arrow))
        XCTAssertEqual(arrow.bounds, CGRect(x: 40, y: 60, width: 100, height: 60))
        XCTAssertEqual(arrow.points, [CGPoint(x: 140, y: 120), CGPoint(x: 40, y: 60)])
    }

    func testImageAnnotationCanvasConstrainsRectangleAndEllipseWithShift() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel, modifiers: .shift))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 70), panel: panel, modifiers: .shift))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 70), panel: panel, modifiers: .shift))

        canvas.setShapeKind(.ellipse)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 160, y: 30), panel: panel, modifiers: .shift))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 210, y: 100), panel: panel, modifiers: .shift))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 210, y: 100), panel: panel, modifiers: .shift))

        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 20, y: 20, width: 80, height: 80))
        XCTAssertEqual(canvas.documentForTesting.elements[1].bounds, CGRect(x: 160, y: 30, width: 70, height: 70))
    }

    func testImageAnnotationCanvasConstrainsLineAndArrowAnglesWithShift() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.line)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel, modifiers: .shift))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 36), panel: panel, modifiers: .shift))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 36), panel: panel, modifiers: .shift))

        canvas.setShapeKind(.arrow)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 140, y: 40), panel: panel, modifiers: .shift))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 200, y: 110), panel: panel, modifiers: .shift))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 200, y: 110), panel: panel, modifiers: .shift))

        XCTAssertEqual(canvas.documentForTesting.elements[0].points, [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 20)])
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 20, y: 20, width: 80, height: 2))
        XCTAssertEqual(canvas.documentForTesting.elements[1].points, [CGPoint(x: 140, y: 40), CGPoint(x: 210, y: 110)])
        XCTAssertEqual(canvas.documentForTesting.elements[1].bounds, CGRect(x: 140, y: 40, width: 70, height: 70))
    }

    func testImageAnnotationRendererUsesStoredArrowDirectionAndBoldStyle() throws {
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .shape(.arrow),
            bounds: CGRect(x: 8, y: 24, width: 48, height: 1),
            points: [CGPoint(x: 56, y: 24), CGPoint(x: 8, y: 24)],
            style: ImageAnnotationStyle(
                strokeColor: .red,
                lineWidth: 1,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 20,
                mosaicStrength: 0.8
            )
        ))

        let screenshot = try makeSolidScreenshot(color: .white, size: CGSize(width: 64, height: 48))
        let rendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: document,
            preservingID: true
        )
        let redPixelsAcrossBody = try (16...32).filter { y in
            try isRedAnnotationPixel(pixelColor(in: rendered.pngData, x: 32, y: y))
        }.count
        let arrowHeadPixel = try pixelColor(in: rendered.pngData, x: 12, y: 24)

        XCTAssertGreaterThanOrEqual(redPixelsAcrossBody, 4)
        XCTAssertTrue(isRedAnnotationPixel(arrowHeadPixel))
    }

    func testImageAnnotationRendererDrawsStraightEdgedWedgeArrowWithoutLengthInflatedWidth() throws {
        var document = ImageAnnotationDocument()
        document.add(ImageAnnotationElement(
            kind: .shape(.arrow),
            bounds: CGRect(x: 16, y: 70, width: 200, height: 1),
            points: [CGPoint(x: 16, y: 70), CGPoint(x: 216, y: 70)],
            style: ImageAnnotationStyle(
                strokeColor: .red,
                lineWidth: 6,
                fontSize: 16,
                fontWeight: .regular,
                mosaicBlockSize: 20,
                mosaicStrength: 0.8
            )
        ))

        let screenshot = try makeSolidScreenshot(color: .white, size: CGSize(width: 240, height: 140))
        let rendered = try ImageAnnotationRenderer().render(
            screenshot: screenshot,
            document: document,
            preservingID: true
        )
        let tailWidth = try redPixelCount(in: rendered.pngData, x: 32, yRange: 32...108)
        let midBodyWidth = try redPixelCount(in: rendered.pngData, x: 96, yRange: 32...108)
        let headwardBodyWidth = try redPixelCount(in: rendered.pngData, x: 164, yRange: 32...108)
        let headBaseWidth = try redPixelCount(in: rendered.pngData, x: 186, yRange: 32...108)

        XCTAssertGreaterThanOrEqual(tailWidth, 2)
        XCTAssertGreaterThan(midBodyWidth, tailWidth + 3)
        XCTAssertGreaterThan(headwardBodyWidth, midBodyWidth + 3)
        XCTAssertLessThanOrEqual(headwardBodyWidth, 24)
        XCTAssertGreaterThan(headBaseWidth, headwardBodyWidth + 14)
        XCTAssertLessThanOrEqual(headBaseWidth, 46)
    }

    func testImageAnnotationCanvasMovesSelectedShapeWhileShapeToolRemainsActive() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 40), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 60, y: 55), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 60, y: 55), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 40, y: 35, width: 80, height: 60))
    }

    func testImageAnnotationCanvasSingleClickMovesExistingArrowWhileArrowToolRemainsActive() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.arrow)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 60), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 140, y: 120), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 140, y: 120), panel: panel))
        let arrowID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 260, y: 200), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 260, y: 200), panel: panel))
        XCTAssertNil(canvas.documentForTesting.selectedElementID)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 80), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 95), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 95), panel: panel))

        let movedArrow = try XCTUnwrap(canvas.documentForTesting.elements.first { $0.id == arrowID })
        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(movedArrow.bounds, CGRect(x: 60, y: 75, width: 100, height: 60))
        XCTAssertEqual(movedArrow.points, [CGPoint(x: 60, y: 75), CGPoint(x: 160, y: 135)])
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
    }

    func testImageAnnotationCanvasSingleClickMovesExistingArrowWhileBrushToolIsActive() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.arrow)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 60), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 140, y: 120), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 140, y: 120), panel: panel))
        let arrowID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 260, y: 200), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 260, y: 200), panel: panel))
        canvas.selectTool(.brush)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 80), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 95), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 95), panel: panel))

        let movedArrow = try XCTUnwrap(canvas.documentForTesting.elements.first { $0.id == arrowID })
        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(movedArrow.bounds, CGRect(x: 60, y: 75, width: 100, height: 60))
        XCTAssertEqual(movedArrow.points, [CGPoint(x: 60, y: 75), CGPoint(x: 160, y: 135)])
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .brush)
    }

    func testImageAnnotationCanvasResizesSelectedMosaicWhileMosaicToolRemainsActive() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.mosaic)
        canvas.setMosaicMode(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.selectedTool, .mosaic)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 130, y: 100), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 130, y: 100), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 20, y: 20, width: 110, height: 80))
    }

    func testImageAnnotationCanvasDoesNotDrawSelectedElementResizeAnchor() throws {
        let image = NSImage(size: NSSize(width: 320, height: 240))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        var document = ImageAnnotationDocument()
        let element = ImageAnnotationElement(
            kind: .mosaic(.rectangle),
            bounds: CGRect(x: 20, y: 20, width: 80, height: 60),
            style: document.editingOptions.style
        )
        document.add(element)
        document.selectElement(id: element.id)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(image: image, document: document)
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        let anchorPixel = try pixelColor(in: canvas, x: 103, y: 83)

        XCTAssertGreaterThan(anchorPixel[0], 240)
        XCTAssertGreaterThan(anchorPixel[1], 240)
        XCTAssertGreaterThan(anchorPixel[2], 240)
    }

    func testImageAnnotationCanvasDoubleClickSelectsExistingShapeWhileShapeToolRemainsActive() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))
        let firstShapeID = try XCTUnwrap(canvas.documentForTesting.elements.first?.id)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 150, y: 120), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 220, y: 180), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 220, y: 180), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 2)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 40), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 40, y: 40), panel: panel))
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 40), panel: panel, clickCount: 2))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 40, y: 40), panel: panel, clickCount: 2))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 2)
        XCTAssertEqual(canvas.documentForTesting.selectedElementID, firstShapeID)
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
    }

    func testImageAnnotationCanvasDoubleClickSelectsExistingMosaicWhileMosaicToolRemainsActive() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.mosaic)
        canvas.setMosaicMode(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))
        let firstMosaicID = try XCTUnwrap(canvas.documentForTesting.elements.first?.id)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 150, y: 120), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 220, y: 180), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 220, y: 180), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 2)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 40), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 40, y: 40), panel: panel))
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 40), panel: panel, clickCount: 2))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 40, y: 40), panel: panel, clickCount: 2))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 2)
        XCTAssertEqual(canvas.documentForTesting.selectedElementID, firstMosaicID)
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .mosaic)
    }

    func testImageAnnotationCanvasDeletesSelectedElementWithEscape() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)

        canvas.keyDown(with: try makeKeyEvent("\u{1b}", modifiers: [], panel: panel, keyCode: 53))

        XCTAssertTrue(canvas.documentForTesting.elements.isEmpty)
    }

    func testImageAnnotationCanvasClickingBlankCancelsSelectedShapeWithoutCreatingPoint() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertNotNil(canvas.documentForTesting.selectedElementID)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 240, y: 200), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 240, y: 200), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertNil(canvas.documentForTesting.selectedElementID)
    }

    func testImageAnnotationCanvasClickingBlankCancelsSelectedMosaicWithoutCreatingPoint() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.mosaic)
        canvas.setMosaicMode(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertNotNil(canvas.documentForTesting.selectedElementID)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 240, y: 200), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 240, y: 200), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertNil(canvas.documentForTesting.selectedElementID)
    }

    func testImageAnnotationCanvasSingleClickDoesNotCreateBrushPoint() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.brush)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 120, y: 120), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 120, y: 120), panel: panel))

        XCTAssertTrue(canvas.documentForTesting.elements.isEmpty)
    }

    func testImageAnnotationCanvasDoesNotDecodeBitmapWhenSelectingMosaicWithoutMosaicContent() throws {
        let image = TIFFAccessCountingImage(size: NSSize(width: 64, height: 48))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 48).fill()
        image.unlockFocus()
        image.tiffAccessCount = 0

        let canvas = ImageAnnotationCanvasView(
            image: image,
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 64, height: 48)
        canvas.selectTool(.mosaic)

        _ = try pixelColor(in: canvas, x: 4, y: 4)

        XCTAssertEqual(image.tiffAccessCount, 0)
    }

    func testImageAnnotationCanvasCreatesMovesResizesDeletesAndUndoesShape() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.shape)
        canvas.setShapeKind(.rectangle)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 20, y: 20), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 100, y: 80), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 100, y: 80), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 20, y: 20, width: 80, height: 60))

        canvas.selectTool(.select)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 40), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 60, y: 55), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 70, y: 65), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 70, y: 65), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 50, y: 45, width: 80, height: 60))
        canvas.undo()
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 20, y: 20, width: 80, height: 60))
        canvas.redo()
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 50, y: 45, width: 80, height: 60))

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 130, y: 105), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 150, y: 120), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 150, y: 120), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 50, y: 45, width: 100, height: 75))

        canvas.keyDown(with: try makeKeyEvent("\u{7f}", modifiers: [], panel: panel, keyCode: 51))

        XCTAssertTrue(canvas.documentForTesting.elements.isEmpty)
        canvas.undo()
        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.elements[0].bounds, CGRect(x: 50, y: 45, width: 100, height: 75))
    }

    func testImageAnnotationCanvasSupportsMosaicBrushAndTextReEditing() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.mosaic)
        canvas.setMosaicMode(.brush)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 30, y: 30), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 60, y: 60), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 60, y: 60), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.last?.kind, .mosaic(.brush))
        XCTAssertEqual(canvas.documentForTesting.elements.last?.points.count, 2)

        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 90), panel: panel))
        canvas.commitActiveTextForTesting("Hello")

        let textID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)
        XCTAssertEqual(canvas.documentForTesting.elements.last?.kind, .text("Hello"))

        canvas.selectTool(.select)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 82, y: 92), panel: panel, clickCount: 2))
        XCTAssertTrue(canvas.isEditingTextForTesting)

        canvas.commitActiveTextForTesting("Frame")
        XCTAssertEqual(canvas.documentForTesting.elements.first { $0.id == textID }?.kind, .text("Frame"))

        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 180, y: 120), panel: panel))
        XCTAssertNil(canvas.documentForTesting.selectedElementID)
        XCTAssertEqual(canvas.documentForTesting.elements.count, 2)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 180, y: 120), panel: panel))
        canvas.commitActiveTextForTesting("Second")

        let textValues = canvas.documentForTesting.elements.compactMap { element -> String? in
            guard case let .text(text) = element.kind else {
                return nil
            }

            return text
        }
        XCTAssertEqual(textValues, ["Frame", "Second"])
    }

    func testImageAnnotationTextEditorScalesFontToMatchRenderedPreview() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 160, height: 120)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        var style = ImageAnnotationStyle.default
        style.fontSize = 22
        canvas.setStyle(style)
        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 40, y: 45), panel: panel))

        let editorFontSize = try XCTUnwrap(canvas.activeTextEditorFontSizeForTesting)
        XCTAssertEqual(editorFontSize, 11, accuracy: 0.1)
    }

    func testImageAnnotationTextEditingUsesInPlaceTransparentFinalObject() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 90), panel: panel))

        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        XCTAssertFalse(editor.drawsBackground)
        XCTAssertEqual(editor.textContainerInset, .zero)
        XCTAssertEqual(editor.textContainer?.lineFragmentPadding, 0)
        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        let textElementID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)
        XCTAssertEqual(canvas.documentForTesting.elements.first?.id, textElementID)
        XCTAssertEqual(canvas.documentForTesting.elements.first?.kind, .text(""))

        canvas.editActiveTextForTesting("Frame")

        let liveTextElement = try XCTUnwrap(canvas.documentForTesting.elements.first)
        XCTAssertEqual(liveTextElement.id, textElementID)
        XCTAssertEqual(liveTextElement.kind, .text("Frame"))
        XCTAssertEqual(liveTextElement.bounds.origin.x, editor.frame.origin.x, accuracy: 0.5)
        XCTAssertEqual(liveTextElement.bounds.origin.y, editor.frame.origin.y, accuracy: 0.5)
        XCTAssertEqual(liveTextElement.bounds.width, editor.frame.width, accuracy: 0.5)
        XCTAssertEqual(liveTextElement.bounds.height, editor.frame.height, accuracy: 0.5)

        let liveBounds = liveTextElement.bounds
        canvas.commitActiveTextForTesting("Frame")

        let committedTextElement = try XCTUnwrap(canvas.documentForTesting.elements.first)
        XCTAssertEqual(committedTextElement.id, textElementID)
        XCTAssertEqual(committedTextElement.kind, .text("Frame"))
        XCTAssertEqual(committedTextElement.bounds, liveBounds)
        XCTAssertTrue(canvas.subviews.compactMap { $0 as? NSTextView }.isEmpty)
    }

    func testImageAnnotationTextToolBlankClickClearsSelectedTextWithoutCreatingAnotherText() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 90), panel: panel))
        canvas.commitActiveTextForTesting("Frame")

        let textElementID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)
        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 240, y: 190), panel: panel))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.elements.first?.id, textElementID)
        XCTAssertNil(canvas.documentForTesting.selectedElementID)
        XCTAssertFalse(canvas.isEditingTextForTesting)
    }

    func testImageAnnotationTextToolSingleClickMovesSelectedText() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 90), panel: panel))
        canvas.commitActiveTextForTesting("Frame")

        let textElementID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)
        let originalBounds = try XCTUnwrap(canvas.documentForTesting.elements.first?.bounds)

        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 82, y: 92), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: NSPoint(x: 122, y: 112), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: NSPoint(x: 122, y: 112), panel: panel))

        let movedText = try XCTUnwrap(canvas.documentForTesting.elements.first { $0.id == textElementID })
        XCTAssertEqual(movedText.bounds.origin.x, originalBounds.origin.x + 40, accuracy: 0.1)
        XCTAssertEqual(movedText.bounds.origin.y, originalBounds.origin.y + 20, accuracy: 0.1)
        XCTAssertEqual(movedText.kind, .text("Frame"))
        XCTAssertFalse(canvas.isEditingTextForTesting)
    }

    func testImageAnnotationTextToolDoubleClickEditsExistingText() throws {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let canvas = ImageAnnotationCanvasView(
            image: NSImage(size: NSSize(width: 320, height: 240)),
            document: ImageAnnotationDocument()
        )
        canvas.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = canvas
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 80, y: 90), panel: panel))
        canvas.commitActiveTextForTesting("Frame")

        let textElementID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: NSPoint(x: 82, y: 92), panel: panel, clickCount: 2))

        XCTAssertTrue(canvas.isEditingTextForTesting)
        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.selectedElementID, textElementID)

        canvas.commitActiveTextForTesting("Updated")

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.elements.first?.id, textElementID)
        XCTAssertEqual(canvas.documentForTesting.elements.first?.kind, .text("Updated"))
    }

    func testImageAnnotationTextEditorReceivesStandardEditShortcutsFromPanel() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        canvas.selectTool(.text)
        canvas.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 80, y: 90)),
            panel: panel
        ))
        canvas.editActiveTextForTesting("Frame")

        let editor = try XCTUnwrap(canvas.subviews.compactMap { $0 as? NSTextView }.first)
        editor.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertTrue(panel.performKeyEquivalent(with: try makeKeyEvent("a", modifiers: .command, panel: panel)))
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 5))

        NSPasteboard.general.clearContents()
        XCTAssertTrue(panel.performKeyEquivalent(with: try makeKeyEvent("c", modifiers: .command, panel: panel)))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Frame")

        NSPasteboard.general.clearContents()
        XCTAssertTrue(panel.performKeyEquivalent(with: try makeKeyEvent("x", modifiers: .command, panel: panel)))
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "Frame")
        XCTAssertEqual(editor.string, "")
        XCTAssertEqual(canvas.documentForTesting.elements.first?.kind, .text(""))

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("Clip", forType: .string)
        XCTAssertTrue(panel.performKeyEquivalent(with: try makeKeyEvent("v", modifiers: .command, panel: panel)))
        XCTAssertEqual(editor.string, "Clip")
        XCTAssertEqual(canvas.documentForTesting.elements.first?.kind, .text("Clip"))
    }

    func testWorkspaceToolbarEnablesEditingToolsAndDropdownOptions() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        let selectButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select"))
        let rectangleButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Rectangle"))
        let ovalButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Oval"))
        let lineButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Line"))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))
        let mosaicButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic"))
        let brushButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Brush"))
        let textButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Text"))
        let highlightButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Highlight"))
        for button in [selectButton, rectangleButton, ovalButton, lineButton, arrowButton, mosaicButton, brushButton, textButton, highlightButton] {
            XCTAssertTrue(button.isEnabled)
        }

        XCTAssertNil(rectangleButton.menu)
        XCTAssertNil(ovalButton.menu)
        XCTAssertNil(lineButton.menu)
        XCTAssertNil(arrowButton.menu)
        XCTAssertNil(mosaicButton.menu)
        XCTAssertEqual(selectButton.state, .on)
        XCTAssertEqual([selectButton, rectangleButton, ovalButton, lineButton, arrowButton, brushButton, textButton, highlightButton, mosaicButton].map {
            $0.convert($0.bounds, to: contentView).minX
        }, [selectButton, rectangleButton, ovalButton, lineButton, arrowButton, brushButton, textButton, highlightButton, mosaicButton].map {
            $0.convert($0.bounds, to: contentView).minX
        }.sorted())

        let mosaicOptionsButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic Options"))
        let styleControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Shape"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Shape Options"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Text Options"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Color"))
        XCTAssertNil(findSlider(in: contentView, accessibilityLabel: "Thickness"))
        XCTAssertTrue(styleControl.isHidden)
        XCTAssertEqual(mosaicOptionsButton.menu?.items.map(\.title), [
            "Region", "Brush",
        ])
        XCTAssertEqual(mosaicOptionsButton.menu?.item(withTitle: "Region")?.state, .on)
        XCTAssertEqual(mosaicOptionsButton.menu?.item(withTitle: "Brush")?.state, .off)
        XCTAssertTrue(mosaicOptionsButton.menu?.items.filter { !$0.isSeparatorItem }.allSatisfy { $0.image != nil } == true)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(rectangleButton.action), to: rectangleButton.target, from: rectangleButton))
        XCTAssertFalse(styleControl.isHidden)
        let colorOptionsButton = try XCTUnwrap(findButton(in: styleControl, accessibilityLabel: "Color"))
        XCTAssertEqual(colorOptionsButton.title, "")
        XCTAssertEqual(colorOptionsButton.toolTip, "Red")
        let paletteView = try XCTUnwrap(colorOptionsButton.menu?.items.first?.view)
        paletteView.layoutSubtreeIfNeeded()
        XCTAssertEqual(orderedButtonTitles(in: paletteView), Array(repeating: "", count: 6))
        XCTAssertEqual(orderedButtonAccessibilityLabels(in: paletteView), ["Red", "Yellow", "Blue", "Green", "White", "Black"])
        let thicknessSlider = try XCTUnwrap(findSlider(in: styleControl, accessibilityLabel: "Thickness"))
        XCTAssertGreaterThan(thicknessSlider.frame.width, 100)
        XCTAssertEqual(thicknessSlider.numberOfTickMarks, 7)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(textButton.action), to: textButton.target, from: textButton))
        let fontSizeSlider = try XCTUnwrap(findSlider(in: styleControl, accessibilityLabel: "Font Size"))
        XCTAssertEqual(fontSizeSlider.numberOfTickMarks, 11)
        XCTAssertEqual(fontSizeSlider.doubleValue, 2)

        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .text)
        let canvasMenu = try XCTUnwrap(canvas.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))
        let textSelectionOverlay = try XCTUnwrap(findTextSelectionOverlay(in: contentView))
        XCTAssertNotNil(canvasMenu.item(withTitle: "Copy"))
        XCTAssertTrue(textSelectionOverlay.isHidden)
    }

    func testWorkspaceToolbarUsesProvidedLocalizedStrings() throws {
        let panel = try showWorkspace(
            strings: AppStrings(language: .zhHans),
            copy: { _ in true },
            save: { _ in true }
        )
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        let rectangleButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "矩形"))
        let ovalButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "椭圆"))
        let lineButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "直线"))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "箭头"))
        let mosaicOptionsButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "马赛克选项"))
        let styleControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        let saveCurrentButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "保存当前稿"))
        let contextMenu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))

        XCTAssertFalse(saveCurrentButton.isEnabled)
        XCTAssertNotNil(contextMenu.item(withTitle: "保存当前稿"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "形状"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "形状选项"))
        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "文本选项"))
        XCTAssertTrue([rectangleButton, ovalButton, lineButton, arrowButton].allSatisfy(\.isEnabled))
        XCTAssertEqual(mosaicOptionsButton.menu?.items.map(\.title), ["区域", "画笔"])
        XCTAssertTrue(styleControl.isHidden)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(rectangleButton.action), to: rectangleButton.target, from: rectangleButton))
        XCTAssertFalse(styleControl.isHidden)
        let colorOptionsButton = try XCTUnwrap(findButton(in: styleControl, accessibilityLabel: "颜色"))
        XCTAssertEqual(colorOptionsButton.title, "")
        XCTAssertEqual(colorOptionsButton.toolTip, "红色")
        let paletteView = try XCTUnwrap(colorOptionsButton.menu?.items.first?.view)
        paletteView.layoutSubtreeIfNeeded()
        XCTAssertEqual(orderedButtonTitles(in: paletteView), Array(repeating: "", count: 6))
        XCTAssertEqual(orderedButtonAccessibilityLabels(in: paletteView), [
            "红色", "黄色", "蓝色", "绿色", "白色", "黑色",
        ])
        XCTAssertNotNil(findSlider(in: styleControl, accessibilityLabel: "粗细"))
    }

    func testHeaderStyleControlReflectsSelectedColor() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))

        let styleControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        let colorButton = try XCTUnwrap(findButton(in: styleControl, accessibilityLabel: "Color"))
        let originalImage = try XCTUnwrap(colorButton.image)
        XCTAssertEqual(originalImage.size, NSSize(width: 20, height: 20))
        let originalIcon = try XCTUnwrap(originalImage.pngDataForTesting())
        let paletteView = try XCTUnwrap(colorButton.menu?.items.first?.view)
        paletteView.layoutSubtreeIfNeeded()
        let blueButton = try XCTUnwrap(findButton(in: paletteView, accessibilityLabel: "Blue"))

        XCTAssertEqual(colorButton.title, "")
        XCTAssertEqual(colorButton.toolTip, "Red")
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(blueButton.action), to: blueButton.target, from: blueButton))

        XCTAssertEqual(colorButton.title, "")
        XCTAssertEqual(colorButton.toolTip, "Blue")
        XCTAssertEqual(colorButton.image?.size, NSSize(width: 20, height: 20))
        XCTAssertNotEqual(colorButton.image?.pngDataForTesting(), originalIcon)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.strokeColor, .blue)
    }

    func testWorkspaceToolbarPersistsLastAnnotationOptions() throws {
        let suiteName = "FrameTests.ImageWorkspaceOptions.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let firstPanel = try showWorkspace(
            editingOptionsDefaults: defaults,
            copy: { _ in true },
            save: { _ in true }
        )
        let firstContentView = try XCTUnwrap(firstPanel.contentView)
        firstContentView.layoutSubtreeIfNeeded()

        let arrowButton = try XCTUnwrap(findButton(in: firstContentView, accessibilityLabel: "Arrow"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))

        let mosaicOptionsButton = try XCTUnwrap(findButton(in: firstContentView, accessibilityLabel: "Mosaic Options"))
        let brushMosaicItem = try XCTUnwrap(mosaicOptionsButton.menu?.item(withTitle: "Brush"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(brushMosaicItem.action), to: brushMosaicItem.target, from: brushMosaicItem))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))

        let styleControl = try XCTUnwrap(findView(in: firstContentView, accessibilityLabel: "Image Workspace Header Style Control"))
        let colorButton = try XCTUnwrap(findButton(in: styleControl, accessibilityLabel: "Color"))
        let paletteView = try XCTUnwrap(colorButton.menu?.items.first?.view)
        paletteView.layoutSubtreeIfNeeded()
        let blueButton = try XCTUnwrap(findButton(in: paletteView, accessibilityLabel: "Blue"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(blueButton.action), to: blueButton.target, from: blueButton))

        let thicknessSlider = try XCTUnwrap(findSlider(in: styleControl, accessibilityLabel: "Thickness"))
        thicknessSlider.doubleValue = 5
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(thicknessSlider.action), to: thicknessSlider.target, from: thicknessSlider))

        let textButton = try XCTUnwrap(findButton(in: firstContentView, accessibilityLabel: "Text"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(textButton.action), to: textButton.target, from: textButton))
        let fontSizeSlider = try XCTUnwrap(findSlider(in: styleControl, accessibilityLabel: "Font Size"))
        fontSizeSlider.doubleValue = 5
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(fontSizeSlider.action), to: fontSizeSlider.target, from: fontSizeSlider))

        closePanel(firstPanel)

        let secondPanel = try showWorkspace(
            editingOptionsDefaults: defaults,
            copy: { _ in true },
            save: { _ in true }
        )
        defer {
            closePanel(secondPanel)
        }
        let secondContentView = try XCTUnwrap(secondPanel.contentView)
        secondContentView.layoutSubtreeIfNeeded()

        let canvas = try XCTUnwrap(findAnnotationCanvas(in: secondContentView))
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .select)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.shapeKind, .arrow)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.mosaicMode, .brush)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.strokeColor, .blue)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.lineWidth, 16)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.fontSize, 28)

        let restoredMosaicOptionsButton = try XCTUnwrap(findButton(in: secondContentView, accessibilityLabel: "Mosaic Options"))
        XCTAssertEqual(restoredMosaicOptionsButton.menu?.item(withTitle: "Region")?.state, .off)
        XCTAssertEqual(restoredMosaicOptionsButton.menu?.item(withTitle: "Brush")?.state, .on)

        XCTAssertNil(findButton(in: secondContentView, accessibilityLabel: "Color"))
        let restoredArrowButton = try XCTUnwrap(findButton(in: secondContentView, accessibilityLabel: "Arrow"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(restoredArrowButton.action), to: restoredArrowButton.target, from: restoredArrowButton))
        let restoredStyleControl = try XCTUnwrap(findView(in: secondContentView, accessibilityLabel: "Image Workspace Header Style Control"))
        let restoredColorButton = try XCTUnwrap(findButton(in: restoredStyleControl, accessibilityLabel: "Color"))
        XCTAssertEqual(restoredColorButton.title, "")
        XCTAssertEqual(restoredColorButton.toolTip, "Blue")
        let restoredThicknessSlider = try XCTUnwrap(findSlider(in: restoredStyleControl, accessibilityLabel: "Thickness"))
        XCTAssertEqual(restoredThicknessSlider.doubleValue, 5)
    }

    func testFlatShapeToolbarButtonsSelectShapeKind() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        let rectangleButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Rectangle"))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(rectangleButton.action), to: rectangleButton.target, from: rectangleButton))
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.shapeKind, .rectangle)
        XCTAssertEqual(rectangleButton.state, .on)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.shapeKind, .arrow)
        XCTAssertEqual(rectangleButton.state, .off)
        XCTAssertEqual(arrowButton.state, .on)
    }

    func testWorkspaceCanvasKeyboardShortcutsSelectToolsAndAdjustSize() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let rectangleButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Rectangle"))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))
        let brushButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Brush"))
        let textButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Text"))

        canvas.keyDown(with: try makeKeyEvent("a", modifiers: [], panel: panel))

        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.shapeKind, .arrow)
        XCTAssertEqual(rectangleButton.state, .off)
        XCTAssertEqual(arrowButton.state, .on)

        canvas.keyDown(with: try makeKeyEvent("t", modifiers: [], panel: panel))
        canvas.keyDown(with: try makeKeyEvent("]", modifiers: [], panel: panel))

        XCTAssertEqual(canvas.documentForTesting.selectedTool, .text)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.fontSize, 18)
        XCTAssertEqual(textButton.state, .on)

        canvas.keyDown(with: try makeKeyEvent("b", modifiers: [], panel: panel))
        canvas.keyDown(with: try makeKeyEvent("]", modifiers: [], panel: panel))

        XCTAssertEqual(canvas.documentForTesting.selectedTool, .brush)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.lineWidth, 8)
        XCTAssertEqual(brushButton.state, .on)

        canvas.keyDown(with: try makeKeyEvent("[", modifiers: [], panel: panel))
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.lineWidth, 4)
    }

    func testWorkspaceHeaderStyleControlUpdatesColorAndLineWidthWithoutChangingTool() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))

        let styleControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        XCTAssertFalse(styleControl.isHidden)
        let colorSelector = try XCTUnwrap(findButton(in: styleControl, accessibilityLabel: "Color"))
        XCTAssertEqual(colorSelector.title, "")
        XCTAssertEqual(colorSelector.toolTip, "Red")
        let paletteView = try XCTUnwrap(colorSelector.menu?.items.first?.view)
        paletteView.layoutSubtreeIfNeeded()
        XCTAssertEqual(orderedButtonTitles(in: paletteView), Array(repeating: "", count: 6))
        XCTAssertEqual(orderedButtonAccessibilityLabels(in: paletteView), ["Red", "Yellow", "Blue", "Green", "White", "Black"])
        let blueSwatch = try XCTUnwrap(findButton(in: paletteView, accessibilityLabel: "Blue"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(blueSwatch.action), to: blueSwatch.target, from: blueSwatch))
        XCTAssertEqual(colorSelector.title, "")
        XCTAssertEqual(colorSelector.toolTip, "Blue")

        let sizeSlider = try XCTUnwrap(findSlider(in: styleControl, accessibilityLabel: "Thickness"))
        XCTAssertGreaterThan(sizeSlider.frame.width, 100)
        sizeSlider.doubleValue = 3
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(sizeSlider.action), to: sizeSlider.target, from: sizeSlider))

        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.shapeKind, .arrow)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.strokeColor, .blue)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.style.lineWidth, 8)
        XCTAssertEqual(arrowButton.state, .on)
    }

    func testWorkspaceHeaderStyleControlOnlyShowsForStyleContexts() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let styleControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))
        let mosaicButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic"))
        let textButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Text"))

        XCTAssertTrue(styleControl.isHidden)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))
        XCTAssertFalse(styleControl.isHidden)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(mosaicButton.action), to: mosaicButton.target, from: mosaicButton))
        XCTAssertTrue(styleControl.isHidden)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(textButton.action), to: textButton.target, from: textButton))
        XCTAssertFalse(styleControl.isHidden)
        XCTAssertNotNil(findSlider(in: styleControl, accessibilityLabel: "Font Size"))
    }

    func testWorkspaceCanvasDoubleClickArrowSwitchesToolbarToArrowContext() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let arrowButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Arrow"))
        let brushButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Brush"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(arrowButton.action), to: arrowButton.target, from: arrowButton))
        canvas.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)),
            panel: panel
        ))
        canvas.mouseDragged(with: try makeMouseButtonEvent(
            type: .leftMouseDragged,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)),
            panel: panel
        ))
        canvas.mouseUp(with: try makeMouseButtonEvent(
            type: .leftMouseUp,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)),
            panel: panel
        ))
        let arrowID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(brushButton.action), to: brushButton.target, from: brushButton))
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .brush)

        canvas.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 70, y: 55)),
            panel: panel,
            clickCount: 2
        ))
        canvas.mouseUp(with: try makeMouseButtonEvent(
            type: .leftMouseUp,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 70, y: 55)),
            panel: panel,
            clickCount: 2
        ))

        XCTAssertEqual(canvas.documentForTesting.elements.count, 1)
        XCTAssertEqual(canvas.documentForTesting.selectedElementID, arrowID)
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)
        XCTAssertEqual(canvas.documentForTesting.editingOptions.shapeKind, .arrow)
        XCTAssertEqual(arrowButton.state, .on)
        XCTAssertEqual(brushButton.state, .off)
    }

    func testWorkspaceCanvasDoubleClickTextSwitchesToolbarToTextEditing() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let rectangleButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Rectangle"))
        let textButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Text"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(textButton.action), to: textButton.target, from: textButton))
        canvas.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 70, y: 80)),
            panel: panel
        ))
        canvas.commitActiveTextForTesting("Note")
        let textID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(rectangleButton.action), to: rectangleButton.target, from: rectangleButton))
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .shape)

        canvas.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 72, y: 82)),
            panel: panel,
            clickCount: 2
        ))

        XCTAssertEqual(canvas.documentForTesting.selectedElementID, textID)
        XCTAssertEqual(canvas.documentForTesting.selectedTool, .text)
        XCTAssertTrue(canvas.isEditingTextForTesting)
        XCTAssertEqual(textButton.state, .on)
        XCTAssertEqual(rectangleButton.state, .off)
    }

    func testWorkspaceFontSizeSliderUpdatesSelectedText() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let textButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Text"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(textButton.action), to: textButton.target, from: textButton))
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 80, y: 90)), panel: panel))
        canvas.commitActiveTextForTesting("Frame")
        let textID = try XCTUnwrap(canvas.documentForTesting.selectedElementID)
        let originalBounds = try XCTUnwrap(canvas.documentForTesting.elements.first?.bounds)

        let styleControl = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        let fontSizeSlider = try XCTUnwrap(findSlider(in: styleControl, accessibilityLabel: "Font Size"))
        fontSizeSlider.doubleValue = 10
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(fontSizeSlider.action), to: fontSizeSlider.target, from: fontSizeSlider))

        let updatedText = try XCTUnwrap(canvas.documentForTesting.elements.first { $0.id == textID })
        XCTAssertEqual(updatedText.style.fontSize, 96)
        XCTAssertGreaterThan(updatedText.bounds.height, originalBounds.height)
    }

    func testWorkspaceUndoRedoButtonsTrackDocumentHistory() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let undoButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Undo"))
        let redoButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Redo"))

        XCTAssertFalse(undoButton.isEnabled)
        XCTAssertFalse(redoButton.isEnabled)

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))

        XCTAssertTrue(undoButton.isEnabled)
        XCTAssertFalse(redoButton.isEnabled)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(undoButton.action), to: undoButton.target, from: undoButton))

        XCTAssertFalse(undoButton.isEnabled)
        XCTAssertTrue(redoButton.isEnabled)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(redoButton.action), to: redoButton.target, from: redoButton))

        XCTAssertTrue(undoButton.isEnabled)
        XCTAssertFalse(redoButton.isEnabled)
    }

    func testWorkspaceOutputUsesRenderedEditsAndSaveCurrentResetsDocument() throws {
        var copiedScreenshot: CapturedScreenshot?
        var savedScreenshot: CapturedScreenshot?
        var replacedScreenshot: CapturedScreenshot?
        let panel = try showWorkspace(
            copy: { screenshot in
                copiedScreenshot = screenshot
                return true
            },
            save: { screenshot in
                savedScreenshot = screenshot
                return true
            },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            }
        )
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let originalPNGData = canvas.currentScreenshotForTesting.pngData

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))

        let saveCurrentButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save Current"))
        let editedContextMenu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))
        let editedSaveMenuItem = try XCTUnwrap(editedContextMenu.item(withTitle: "Save Current"))
        XCTAssertTrue(saveCurrentButton.isEnabled)
        XCTAssertEqual(saveCurrentButton.menu?.items.map(\.title), ["Replace Current", "Save As New"])
        XCTAssertTrue(editedSaveMenuItem.isEnabled)
        let replaceCurrentItem = try XCTUnwrap(saveCurrentButton.menu?.item(withTitle: "Replace Current"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(replaceCurrentItem.action), to: replaceCurrentItem.target, from: replaceCurrentItem))
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(canvas.documentForTesting.elements.isEmpty)
        XCTAssertNotEqual(canvas.currentScreenshotForTesting.pngData, originalPNGData)
        XCTAssertEqual(replacedScreenshot?.pngData, canvas.currentScreenshotForTesting.pngData)
        XCTAssertNil(savedScreenshot)
        let committedContextMenu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))
        let committedSaveMenuItem = try XCTUnwrap(committedContextMenu.item(withTitle: "Save Current"))
        XCTAssertFalse(committedSaveMenuItem.isEnabled)

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 30, y: 30)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 80, y: 70)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 80, y: 70)), panel: panel))

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertNotNil(copiedScreenshot)
        XCTAssertNotEqual(copiedScreenshot?.pngData, canvas.currentScreenshotForTesting.pngData)
    }

    func testWorkspaceSaveCurrentMenuCanCreateNewQuickAccessPreviewWithoutClosing() throws {
        var savedScreenshot: CapturedScreenshot?
        var newPreviewScreenshot: CapturedScreenshot?
        let panel = try showWorkspace(
            copy: { _ in true },
            save: { screenshot in
                savedScreenshot = screenshot
                return true
            },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            }
        )
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let originalPNGData = canvas.currentScreenshotForTesting.pngData

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))

        let saveCurrentButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save Current"))
        let saveAsNewItem = try XCTUnwrap(saveCurrentButton.menu?.item(withTitle: "Save As New"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(saveAsNewItem.action), to: saveAsNewItem.target, from: saveAsNewItem))
        XCTAssertNil(savedScreenshot)
        XCTAssertNotNil(newPreviewScreenshot)
        XCTAssertNotEqual(newPreviewScreenshot?.pngData, originalPNGData)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(canvas.documentForTesting.hasUncommittedEdits)
    }

    func testWorkspaceSaveCurrentPrimaryClickReplacesCurrentWhenConfigured() throws {
        var replacedScreenshot: CapturedScreenshot?
        var newPreviewScreenshot: CapturedScreenshot?
        let panel = try showWorkspace(
            saveCurrentBehavior: .replaceCurrent,
            copy: { _ in true },
            save: { _ in true },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            }
        )
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let originalPNGData = canvas.currentScreenshotForTesting.pngData

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))

        let saveCurrentButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save Current"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(saveCurrentButton.action), to: saveCurrentButton.target, from: saveCurrentButton))

        XCTAssertNotNil(replacedScreenshot)
        XCTAssertNil(newPreviewScreenshot)
        XCTAssertNotEqual(canvas.currentScreenshotForTesting.pngData, originalPNGData)
        XCTAssertTrue(canvas.documentForTesting.elements.isEmpty)
        XCTAssertTrue(panel.isVisible)
    }

    func testWorkspaceSaveCurrentPrimaryClickSavesAsNewWhenConfigured() throws {
        var replacedScreenshot: CapturedScreenshot?
        var newPreviewScreenshot: CapturedScreenshot?
        let panel = try showWorkspace(
            saveCurrentBehavior: .saveAsNew,
            copy: { _ in true },
            save: { _ in true },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            }
        )
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let originalPNGData = canvas.currentScreenshotForTesting.pngData

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))

        let saveCurrentButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save Current"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(saveCurrentButton.action), to: saveCurrentButton.target, from: saveCurrentButton))

        XCTAssertNil(replacedScreenshot)
        XCTAssertNotNil(newPreviewScreenshot)
        XCTAssertNotEqual(newPreviewScreenshot?.pngData, originalPNGData)
        XCTAssertEqual(canvas.currentScreenshotForTesting.pngData, originalPNGData)
        XCTAssertTrue(canvas.documentForTesting.hasUncommittedEdits)
        XCTAssertTrue(panel.isVisible)
    }

    func testWorkspaceSaveCurrentPrimaryClickAsksEveryTimeWhenConfigured() throws {
        var replacedScreenshot: CapturedScreenshot?
        var newPreviewScreenshot: CapturedScreenshot?
        var didPresentSaveCurrentMenu = false
        let panel = try showWorkspace(
            saveCurrentBehavior: .askEveryTime,
            presentSaveCurrentMenu: { menu, sender in
                didPresentSaveCurrentMenu = true
                XCTAssertTrue(menu.items.contains { $0.title == "Replace Current" })
                XCTAssertTrue(menu.items.contains { $0.title == "Save As New" })
                XCTAssertEqual(sender.accessibilityLabel(), "Save Current")
            },
            copy: { _ in true },
            save: { _ in true },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            }
        )
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))

        canvas.selectTool(.shape)
        canvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 20, y: 20)), panel: panel))
        canvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))
        canvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: canvas, imagePoint: CGPoint(x: 120, y: 90)), panel: panel))

        let saveCurrentButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save Current"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(saveCurrentButton.action), to: saveCurrentButton.target, from: saveCurrentButton))

        XCTAssertNil(replacedScreenshot)
        XCTAssertNil(newPreviewScreenshot)
        XCTAssertTrue(didPresentSaveCurrentMenu)
        XCTAssertTrue(canvas.documentForTesting.hasUncommittedEdits)
        XCTAssertTrue(panel.isVisible)
    }

    func testWorkspaceCloseWithUnsavedEditsSavesUsingConfiguredDefaultOrDiscardsOrCancels() throws {
        var replacedScreenshot: CapturedScreenshot?
        var newPreviewScreenshot: CapturedScreenshot?

        let replacePanel = try showWorkspace(
            saveCurrentBehavior: .replaceCurrent,
            copy: { _ in true },
            save: { _ in true },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            },
            closeSaveChoice: { .save }
        )
        let replaceCanvas = try XCTUnwrap(findAnnotationCanvas(in: try XCTUnwrap(replacePanel.contentView)))
        replaceCanvas.selectTool(.shape)
        replaceCanvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: replaceCanvas, imagePoint: CGPoint(x: 20, y: 20)), panel: replacePanel))
        replaceCanvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: replaceCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: replacePanel))
        replaceCanvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: replaceCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: replacePanel))

        replacePanel.close()

        XCTAssertFalse(replacePanel.isVisible)
        XCTAssertNotNil(replacedScreenshot)
        XCTAssertNil(newPreviewScreenshot)

        let saveAsNewPanel = try showWorkspace(
            saveCurrentBehavior: .saveAsNew,
            copy: { _ in true },
            save: { _ in true },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            },
            closeSaveChoice: { .save }
        )
        let saveAsNewCanvas = try XCTUnwrap(findAnnotationCanvas(in: try XCTUnwrap(saveAsNewPanel.contentView)))
        saveAsNewCanvas.selectTool(.shape)
        saveAsNewCanvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: saveAsNewCanvas, imagePoint: CGPoint(x: 20, y: 20)), panel: saveAsNewPanel))
        saveAsNewCanvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: saveAsNewCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: saveAsNewPanel))
        saveAsNewCanvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: saveAsNewCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: saveAsNewPanel))

        saveAsNewPanel.close()

        XCTAssertFalse(saveAsNewPanel.isVisible)
        XCTAssertNotNil(newPreviewScreenshot)

        let discardPanel = try showWorkspace(
            copy: { _ in true },
            save: { _ in true },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            },
            closeSaveChoice: { .discard }
        )
        let discardCanvas = try XCTUnwrap(findAnnotationCanvas(in: try XCTUnwrap(discardPanel.contentView)))
        discardCanvas.selectTool(.shape)
        discardCanvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: discardCanvas, imagePoint: CGPoint(x: 20, y: 20)), panel: discardPanel))
        discardCanvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: discardCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: discardPanel))
        discardCanvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: discardCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: discardPanel))

        let replacedScreenshotBeforeDiscard = replacedScreenshot
        let newPreviewScreenshotBeforeDiscard = newPreviewScreenshot

        discardPanel.close()

        XCTAssertFalse(discardPanel.isVisible)
        XCTAssertEqual(replacedScreenshot?.id, replacedScreenshotBeforeDiscard?.id)
        XCTAssertEqual(newPreviewScreenshot?.id, newPreviewScreenshotBeforeDiscard?.id)

        let cancelPanel = try showWorkspace(
            copy: { _ in true },
            save: { _ in true },
            replaceCurrent: { screenshot in
                replacedScreenshot = screenshot
            },
            saveAsNew: { screenshot in
                newPreviewScreenshot = screenshot
                return true
            },
            closeSaveChoice: { .cancel }
        )
        defer {
            closePanel(cancelPanel)
        }
        let cancelCanvas = try XCTUnwrap(findAnnotationCanvas(in: try XCTUnwrap(cancelPanel.contentView)))
        cancelCanvas.selectTool(.shape)
        cancelCanvas.mouseDown(with: try makeMouseButtonEvent(type: .leftMouseDown, point: imageWindowPoint(in: cancelCanvas, imagePoint: CGPoint(x: 20, y: 20)), panel: cancelPanel))
        cancelCanvas.mouseDragged(with: try makeMouseButtonEvent(type: .leftMouseDragged, point: imageWindowPoint(in: cancelCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: cancelPanel))
        cancelCanvas.mouseUp(with: try makeMouseButtonEvent(type: .leftMouseUp, point: imageWindowPoint(in: cancelCanvas, imagePoint: CGPoint(x: 120, y: 90)), panel: cancelPanel))

        let replacedScreenshotBeforeCancel = replacedScreenshot
        let newPreviewScreenshotBeforeCancel = newPreviewScreenshot

        cancelPanel.close()

        XCTAssertTrue(cancelPanel.isVisible)
        XCTAssertEqual(replacedScreenshot?.id, replacedScreenshotBeforeCancel?.id)
        XCTAssertEqual(newPreviewScreenshot?.id, newPreviewScreenshotBeforeCancel?.id)
        XCTAssertTrue(cancelCanvas.documentForTesting.hasUncommittedEdits)
    }

    func testTemporaryWorkspaceReusesExistingWindowForSameScreenshot() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let firstPanel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(firstPanel)
        }

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let openedPanels = workspacePanels(excluding: windowsBeforeShow)
        XCTAssertEqual(openedPanels.count, 1)
        XCTAssertTrue(openedPanels.first === firstPanel)
        XCTAssertTrue(firstPanel.isVisible)
    }

    func testWorkspaceOutputButtonsCloseWindowAfterSuccess() throws {
        let copyPanel = try showWorkspace(copy: { true }, save: { false })
        defer {
            closePanel(copyPanel)
        }
        let copyButton = try XCTUnwrap(findButton(in: try XCTUnwrap(copyPanel.contentView), accessibilityLabel: "Copy"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertFalse(copyPanel.isVisible)

        let downloadPanel = try showWorkspace(copy: { false }, save: { true })
        defer {
            closePanel(downloadPanel)
        }
        let downloadButton = try XCTUnwrap(findButton(in: try XCTUnwrap(downloadPanel.contentView), accessibilityLabel: "Download"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(downloadButton.action), to: downloadButton.target, from: downloadButton))
        XCTAssertFalse(downloadPanel.isVisible)
    }

    func testPinnedWorkspaceIsImageOnlyWithoutToolbar() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertNil(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        XCTAssertNil(findView(in: contentView, accessibilityLabel: "Image Workspace Header Style Control"))
        for label in ["Mosaic", "Shape Box", "Brush", "Text", "Arrow", "Highlight", "Save", "Copy", "Download"] {
            XCTAssertNil(findButton(in: contentView, accessibilityLabel: label))
        }

        let imageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Pinned Image Container"))
        XCTAssertNil(findTextSelectionOverlay(in: contentView))
        let closeFrame = try XCTUnwrap(panel.standardWindowButton(.closeButton))
            .convert(try XCTUnwrap(panel.standardWindowButton(.closeButton)).bounds, to: contentView)
        XCTAssertEqual(imageContainer.frame.minX, contentView.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minY, contentView.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.maxX, contentView.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.maxY, contentView.bounds.maxY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(closeFrame.minX, imageContainer.frame.minX)
        XCTAssertLessThanOrEqual(closeFrame.maxY, imageContainer.frame.maxY)
        XCTAssertLessThan(closeFrame.midX, imageContainer.frame.minX + 80)
        XCTAssertGreaterThan(closeFrame.midY, imageContainer.frame.maxY - 40)
    }

    func testImageWorkspaceCanvasBackdropIsFullyOpaque() throws {
        let panel = try showWorkspace(copy: { _ in true }, save: { _ in true })
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        let imageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Preview Container"))
        let backgroundColor = try XCTUnwrap(imageContainer.layer?.backgroundColor)

        XCTAssertEqual(backgroundColor.alpha, 1, accuracy: 0.001)
    }

    func testTemporaryWorkspaceOpensSmallImageAtOriginalDisplaySize() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeSolidScreenshot(color: .systemBlue, size: CGSize(width: 120, height: 80))

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))

        XCTAssertGreaterThan(canvas.bounds.width, screenshot.image.size.width)
        XCTAssertGreaterThan(canvas.bounds.height, screenshot.image.size.height)
        XCTAssertEqual(canvas.lastDrawRectForTesting.width, screenshot.image.size.width, accuracy: 0.5)
        XCTAssertEqual(canvas.lastDrawRectForTesting.height, screenshot.image.size.height, accuracy: 0.5)
    }

    func testPinnedWorkspaceOpensSmallImageAtOriginalDisplaySize() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeSolidScreenshot(color: .systemBlue, size: CGSize(width: 120, height: 80))

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(findZoomableImageSurface(in: contentView))

        XCTAssertGreaterThan(imageView.bounds.width, screenshot.image.size.width)
        XCTAssertGreaterThan(imageView.bounds.height, screenshot.image.size.height)
        XCTAssertEqual(imageView.lastDrawRectForTesting.width, screenshot.image.size.width, accuracy: 0.5)
        XCTAssertEqual(imageView.lastDrawRectForTesting.height, screenshot.image.size.height, accuracy: 0.5)
    }

    func testTemporaryWorkspaceOpensFittingImageAtOriginalWindowSize() throws {
        _ = NSApplication.shared
        let sourceSize = CGSize(width: 1040, height: 650)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        try XCTSkipIf(
            visibleFrame.width < sourceSize.width + 80 || visibleFrame.height < sourceSize.height + 120,
            "Screen is too small to verify original-size initial workspace window."
        )

        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeSolidScreenshot(color: .systemBlue, size: sourceSize)

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))

        XCTAssertEqual(canvas.bounds.width, sourceSize.width, accuracy: 1.5)
        XCTAssertEqual(canvas.bounds.height, sourceSize.height, accuracy: 1.5)
        XCTAssertEqual(canvas.lastDrawRectForTesting.width, sourceSize.width, accuracy: 0.5)
        XCTAssertEqual(canvas.lastDrawRectForTesting.height, sourceSize.height, accuracy: 0.5)
    }

    func testPinnedWorkspaceOpensFittingImageAtOriginalWindowSize() throws {
        _ = NSApplication.shared
        let sourceSize = CGSize(width: 1040, height: 650)
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        try XCTSkipIf(
            visibleFrame.width < sourceSize.width + 80 || visibleFrame.height < sourceSize.height + 80,
            "Screen is too small to verify original-size initial pinned window."
        )

        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeSolidScreenshot(color: .systemBlue, size: sourceSize)

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(findZoomableImageSurface(in: contentView))

        XCTAssertEqual(imageView.bounds.width, sourceSize.width, accuracy: 1.5)
        XCTAssertEqual(imageView.bounds.height, sourceSize.height, accuracy: 1.5)
        XCTAssertEqual(imageView.lastDrawRectForTesting.width, sourceSize.width, accuracy: 0.5)
        XCTAssertEqual(imageView.lastDrawRectForTesting.height, sourceSize.height, accuracy: 0.5)
    }

    func testTemporaryWorkspaceTrackpadMagnificationZoomsImageWithoutResizingWindow() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let textSelectionOverlay = try XCTUnwrap(findTextSelectionOverlay(in: contentView))
        let initialPanelFrame = panel.frame
        let initialDrawRect = canvas.lastDrawRectForTesting

        canvas.magnify(with: FakeMagnifyEvent(magnification: 0.35, locationInWindow: canvas.convert(canvas.bounds.center, to: nil)))
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertGreaterThan(canvas.lastDrawRectForTesting.width, initialDrawRect.width)
        XCTAssertGreaterThan(canvas.lastDrawRectForTesting.height, initialDrawRect.height)

        let zoomedDrawRect = canvas.lastDrawRectForTesting
        canvas.magnify(with: FakeMagnifyEvent(magnification: -0.40, locationInWindow: canvas.convert(canvas.bounds.center, to: nil)))
        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertLessThan(canvas.lastDrawRectForTesting.width, zoomedDrawRect.width)
        XCTAssertGreaterThanOrEqual(canvas.lastDrawRectForTesting.width, initialDrawRect.width)

        let drawRectBeforeOverlayMagnification = canvas.lastDrawRectForTesting
        textSelectionOverlay.magnify(with: FakeMagnifyEvent(
            magnification: 0.25,
            locationInWindow: textSelectionOverlay.convert(textSelectionOverlay.bounds.center, to: nil)
        ))

        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertGreaterThan(canvas.lastDrawRectForTesting.width, drawRectBeforeOverlayMagnification.width)
    }

    func testTemporaryWorkspaceScrollWheelPansZoomedImageWithoutResizingWindow() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let textSelectionOverlay = try XCTUnwrap(findTextSelectionOverlay(in: contentView))
        let initialPanelFrame = panel.frame

        canvas.magnify(with: FakeMagnifyEvent(magnification: 5, locationInWindow: canvas.convert(canvas.bounds.center, to: nil)))
        let centeredZoomedDrawRect = canvas.lastDrawRectForTesting

        canvas.scrollWheel(with: FakeScrollWheelEvent(deltaX: 32, deltaY: -24))
        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertNotEqual(canvas.lastDrawRectForTesting.origin, centeredZoomedDrawRect.origin)
        XCTAssertGreaterThan(canvas.lastDrawRectForTesting.minX, centeredZoomedDrawRect.minX)
        XCTAssertGreaterThan(canvas.lastDrawRectForTesting.minY, centeredZoomedDrawRect.minY)

        let drawRectBeforeOverlayScroll = canvas.lastDrawRectForTesting
        textSelectionOverlay.scrollWheel(with: FakeScrollWheelEvent(deltaX: -18, deltaY: 12))
        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertNotEqual(canvas.lastDrawRectForTesting.origin, drawRectBeforeOverlayScroll.origin)
        XCTAssertLessThan(canvas.lastDrawRectForTesting.minX, drawRectBeforeOverlayScroll.minX)
        XCTAssertLessThan(canvas.lastDrawRectForTesting.minY, drawRectBeforeOverlayScroll.minY)
    }

    func testPinnedWorkspaceTrackpadMagnificationZoomsImageWithoutResizingWindow() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(findZoomableImageSurface(in: contentView))
        let initialPanelFrame = panel.frame
        let initialDrawRect = imageView.lastDrawRectForTesting

        imageView.magnify(with: FakeMagnifyEvent(magnification: 0.35, locationInWindow: imageView.convert(imageView.bounds.center, to: nil)))
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertGreaterThan(imageView.lastDrawRectForTesting.width, initialDrawRect.width)
        XCTAssertGreaterThan(imageView.lastDrawRectForTesting.height, initialDrawRect.height)

        let zoomedDrawRect = imageView.lastDrawRectForTesting
        imageView.magnify(with: FakeMagnifyEvent(magnification: -0.40, locationInWindow: imageView.convert(imageView.bounds.center, to: nil)))

        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertLessThan(imageView.lastDrawRectForTesting.width, zoomedDrawRect.width)
        XCTAssertGreaterThanOrEqual(imageView.lastDrawRectForTesting.width, initialDrawRect.width)
    }

    func testPinnedWorkspaceScrollWheelPansZoomedImageWithoutResizingWindow() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let imageView = try XCTUnwrap(findZoomableImageSurface(in: contentView))
        let initialPanelFrame = panel.frame

        imageView.magnify(with: FakeMagnifyEvent(magnification: 1.5, locationInWindow: imageView.convert(imageView.bounds.center, to: nil)))
        let centeredZoomedDrawRect = imageView.lastDrawRectForTesting

        imageView.scrollWheel(with: FakeScrollWheelEvent(deltaX: 32, deltaY: -24))

        XCTAssertEqual(panel.frame, initialPanelFrame)
        XCTAssertNotEqual(imageView.lastDrawRectForTesting.origin, centeredZoomedDrawRect.origin)
        XCTAssertGreaterThan(imageView.lastDrawRectForTesting.minX, centeredZoomedDrawRect.minX)
        XCTAssertGreaterThan(imageView.lastDrawRectForTesting.minY, centeredZoomedDrawRect.minY)
    }

    func testPinnedWorkspaceContextMenuOutputsAndEditsWithoutClosingPin() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        var copyCount = 0
        var saveCount = 0

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: {
                copyCount += 1
                return true
            },
            save: {
                saveCount += 1
                return true
            }
        ))

        let pinPanel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            for panel in workspacePanels(excluding: windowsBeforeShow) {
                closePanel(panel)
            }
        }

        let contentView = try XCTUnwrap(pinPanel.contentView)
        let menu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: pinPanel.windowNumber)))
        let copyMenuItem = try XCTUnwrap(menu.item(withTitle: "Copy"))
        let downloadMenuItem = try XCTUnwrap(menu.item(withTitle: "Download"))
        let editMenuItem = try XCTUnwrap(menu.item(withTitle: "Edit"))

        XCTAssertNil(menu.item(withTitle: "Save"))
        XCTAssertNil(menu.item(withTitle: "Mosaic"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyMenuItem.action), to: copyMenuItem.target, from: copyMenuItem))
        XCTAssertEqual(copyCount, 1)
        XCTAssertTrue(pinPanel.isVisible)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(downloadMenuItem.action), to: downloadMenuItem.target, from: downloadMenuItem))
        XCTAssertEqual(saveCount, 1)
        XCTAssertTrue(pinPanel.isVisible)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(editMenuItem.action), to: editMenuItem.target, from: editMenuItem))
        XCTAssertTrue(pinPanel.isVisible)
        XCTAssertEqual(workspacePanels(excluding: windowsBeforeShow).filter(\.isVisible).count, 2)

        let editPanel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first {
            $0 !== pinPanel && $0.isVisible
        })
        let editContentView = try XCTUnwrap(editPanel.contentView)
        XCTAssertNotNil(findView(in: editContentView, accessibilityLabel: "Image Workspace Toolbar"))
    }

    func testTemporaryWorkspaceStaysOpenOnFocusLossAndClosesOnEscape() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            closePanel(panel)
        }

        panel.resignKey()
        XCTAssertTrue(panel.isVisible)

        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
    }

    func testWorkspaceUsesNativeCloseAndTopToolbarOutsideImage() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        var copyCount = 0
        var saveCount = 0

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: {
                copyCount += 1
                return true
            },
            save: {
                saveCount += 1
                return true
            }
        ))

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            closePanel(panel)
        }

        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.closable))
        XCTAssertTrue(panel.styleMask.contains(.miniaturizable))
        XCTAssertTrue(panel.hasShadow)
        let closeButton = try XCTUnwrap(panel.standardWindowButton(.closeButton))
        let miniaturizeButton = try XCTUnwrap(panel.standardWindowButton(.miniaturizeButton))
        let zoomButton = try XCTUnwrap(panel.standardWindowButton(.zoomButton))
        XCTAssertTrue(closeButton.isEnabled)
        XCTAssertTrue(miniaturizeButton.isEnabled)
        XCTAssertTrue(zoomButton.isEnabled)

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Close"))

        let toolbar = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        let imageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Preview Container"))
        let selectButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select"))
        let mosaicButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic"))
        let mosaicOptionsButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic Options"))
        let mosaicSplitControl = try XCTUnwrap(findView(in: contentView, identifier: "ImageWorkspaceToolbarMosaicSplitControl"))
        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy"))
        let saveButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save Current"))
        let downloadButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Download"))
        let historyToolsDivider = try XCTUnwrap(findView(in: contentView, identifier: "ImageWorkspaceToolbarHistoryToolsDivider"))
        let styleDivider = try XCTUnwrap(findView(in: contentView, identifier: "ImageWorkspaceToolbarStyleDivider"))
        let outputDivider = try XCTUnwrap(findView(in: contentView, identifier: "ImageWorkspaceToolbarOutputDivider"))
        let menu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))
        let copyMenuItem = try XCTUnwrap(menu.item(withTitle: "Copy"))
        let saveMenuItem = try XCTUnwrap(menu.item(withTitle: "Save Current"))
        let downloadMenuItem = try XCTUnwrap(menu.item(withTitle: "Download"))
        let mosaicMenuItem = try XCTUnwrap(menu.item(withTitle: "Mosaic"))

        let mosaicFrame = mosaicButton.convert(mosaicButton.bounds, to: contentView)
        let mosaicOptionsFrame = mosaicOptionsButton.convert(mosaicOptionsButton.bounds, to: contentView)
        let mosaicSplitFrame = mosaicSplitControl.convert(mosaicSplitControl.bounds, to: contentView)
        let copyFrame = copyButton.convert(copyButton.bounds, to: contentView)
        let saveFrame = saveButton.convert(saveButton.bounds, to: contentView)
        let downloadFrame = downloadButton.convert(downloadButton.bounds, to: contentView)
        let closeFrame = closeButton.convert(closeButton.bounds, to: contentView)
        let miniaturizeFrame = miniaturizeButton.convert(miniaturizeButton.bounds, to: contentView)
        let zoomFrame = zoomButton.convert(zoomButton.bounds, to: contentView)

        XCTAssertEqual(toolbar.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(toolbar.frame.height, 36, accuracy: 0.5)
        XCTAssertEqual(toolbar.appearance?.name, .vibrantDark)
        XCTAssertGreaterThanOrEqual(toolbar.layer?.backgroundColor?.alpha ?? 0, 0.5)
        XCTAssertEqual(mosaicFrame.width, 28, accuracy: 0.5)
        XCTAssertEqual(mosaicOptionsFrame.width, 20, accuracy: 0.5)
        XCTAssertEqual(mosaicSplitFrame.width, mosaicFrame.width + mosaicOptionsFrame.width, accuracy: 0.5)
        XCTAssertEqual(mosaicSplitFrame.minX, mosaicFrame.minX, accuracy: 0.5)
        XCTAssertEqual(mosaicSplitFrame.maxX, mosaicOptionsFrame.maxX, accuracy: 0.5)
        XCTAssertEqual(mosaicOptionsFrame.minX, mosaicFrame.maxX, accuracy: 0.5)
        XCTAssertEqual(saveFrame.width, 28, accuracy: 0.5)
        XCTAssertEqual(copyFrame.width, 28, accuracy: 0.5)
        XCTAssertEqual(downloadFrame.width, 28, accuracy: 0.5)
        XCTAssertEqual(copyFrame.minX - saveFrame.maxX, 2, accuracy: 0.5)
        XCTAssertEqual(downloadFrame.minX - copyFrame.maxX, 2, accuracy: 0.5)
        XCTAssertEqual(toolbar.layer?.cornerRadius ?? 0, toolbar.frame.height / 2, accuracy: 0.5)
        XCTAssertEqual(toolbar.layer?.borderWidth ?? 0, 0.5, accuracy: 0.01)
        XCTAssertLessThanOrEqual(toolbar.frame.minX, closeFrame.minX - 2)
        XCTAssertEqual(toolbar.frame.maxX, imageContainer.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(toolbar.frame.minX, imageContainer.frame.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(mosaicFrame.minX, zoomFrame.maxX + 8)
        XCTAssertEqual(toolbar.frame.midY, closeFrame.midY, accuracy: 1.5)
        XCTAssertEqual(toolbar.frame.midY, miniaturizeFrame.midY, accuracy: 1.5)
        XCTAssertEqual(toolbar.frame.midY, zoomFrame.midY, accuracy: 1.5)
        XCTAssertFalse(historyToolsDivider.isHidden)
        XCTAssertTrue(styleDivider.isHidden)
        XCTAssertFalse(outputDivider.isHidden)
        XCTAssertEqual(historyToolsDivider.frame.width, 1, accuracy: 0.5)
        XCTAssertEqual(outputDivider.frame.width, 1, accuracy: 0.5)
        assertCircularHoverLayer(in: mosaicButton)
        for button in [selectButton, mosaicButton, saveButton, copyButton, downloadButton] {
            try assertToolbarIconViewCentered(in: button)
        }
        XCTAssertTrue(mosaicButton.isEnabled)
        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(downloadButton.isEnabled)
        let selectIcon = try XCTUnwrap(selectButton.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertEqual(selectIcon.contentTintColor, NSColor.white)
        XCTAssertEqual(copyButton.toolTip, "Save and Copy")
        XCTAssertEqual(downloadButton.toolTip, "Save and Download")

        XCTAssertTrue(mosaicMenuItem.isEnabled)
        XCTAssertFalse(saveMenuItem.isEnabled)
        XCTAssertTrue(copyMenuItem.isEnabled)
        XCTAssertTrue(downloadMenuItem.isEnabled)
        XCTAssertEqual(toolbar.frame.minY - imageContainer.frame.maxY, 6, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minX, toolbar.frame.minX, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minY, contentView.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(
            imageContainer.frame.width / imageContainer.frame.height,
            320.0 / 240.0,
            accuracy: 0.01
        )
        XCTAssertGreaterThan(saveFrame.minX, mosaicFrame.maxX)
        XCTAssertGreaterThan(copyFrame.minX, saveFrame.maxX)
        XCTAssertGreaterThan(downloadFrame.minX, copyFrame.maxX)

        let mosaicSplitBackground = try XCTUnwrap(mosaicSplitControl.layer?.sublayers?.first)
        XCTAssertEqual(mosaicSplitBackground.opacity, 0, accuracy: 0.01)
        let hoverEvent = try makeMouseMoveEvent(point: mosaicSplitControl.convert(mosaicSplitControl.bounds.center, to: nil), panel: panel)
        mosaicSplitControl.mouseEntered(with: hoverEvent)
        XCTAssertEqual(mosaicSplitBackground.opacity, 1, accuracy: 0.01)
        mosaicSplitControl.mouseExited(with: hoverEvent)
        XCTAssertEqual(mosaicSplitBackground.opacity, 0, accuracy: 0.01)

        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(mosaicButton.action), to: mosaicButton.target, from: mosaicButton))
        contentView.layoutSubtreeIfNeeded()
        XCTAssertEqual(mosaicSplitBackground.opacity, 1, accuracy: 0.01)

        canvas.selectTool(.shape)
        contentView.layoutSubtreeIfNeeded()
        XCTAssertFalse(styleDivider.isHidden)

        panel.setFrame(NSRect(origin: panel.frame.origin, size: panel.minSize), display: false)
        contentView.layoutSubtreeIfNeeded()

        let minimumToolbar = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        let minimumImageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Preview Container"))
        let minimumDownloadButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Download"))
        let minimumDownloadFrame = minimumDownloadButton.convert(minimumDownloadButton.bounds, to: contentView)
        let minimumVerticalChromeHeight = minimumToolbar.frame.height + minimumToolbar.frame.minY - minimumImageContainer.frame.maxY
        XCTAssertLessThanOrEqual(minimumDownloadFrame.maxX, minimumToolbar.frame.maxX - 5)
        XCTAssertEqual(
            minimumImageContainer.frame.width / minimumImageContainer.frame.height,
            320.0 / 240.0,
            accuracy: 0.01
        )

        let proposedFrameSize = NSSize(width: panel.frame.width + 200, height: panel.frame.height)
        let constrainedFrameSize = try XCTUnwrap(panel.delegate?.windowWillResize?(panel, to: proposedFrameSize))
        let constrainedContentSize = panel.contentRect(forFrameRect: NSRect(origin: .zero, size: constrainedFrameSize)).size
        XCTAssertGreaterThan(constrainedFrameSize.height, proposedFrameSize.height)
        XCTAssertEqual(
            constrainedContentSize.width / (constrainedContentSize.height - minimumVerticalChromeHeight),
            320.0 / 240.0,
            accuracy: 0.01
        )

        XCTAssertEqual(copyCount, 0)
        XCTAssertEqual(saveCount, 0)
    }

    func testTemporaryWorkspaceAutomaticallyLoadsOCRTextOverlay() async throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var recognizeCount = 0
        var copiedText: String?

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true },
            recognizeText: { _ in
                recognizeCount += 1
                return RecognizedTextLayout(lines: [
                    RecognizedTextLine(
                        text: "Frame",
                        bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                        confidence: 0.9,
                        tokens: [
                            RecognizedTextToken(
                                text: "Frame",
                                bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                                needsLeadingSpace: false
                            ),
                        ]
                    ),
                ])
            },
            copyRecognizedText: { text in
                copiedText = text
                return true
            }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let overlay = try XCTUnwrap(findTextSelectionOverlay(in: contentView))

        for _ in 0..<10 where !overlay.hasRecognizedText {
            await Task.yield()
        }
        XCTAssertTrue(overlay.hasRecognizedText)
        XCTAssertEqual(recognizeCount, 1)

        let selectionPoint = overlay.convert(
            canvas.convert(imageViewPoint(in: canvas, imagePoint: CGPoint(x: 64, y: 60)), to: nil),
            from: nil
        )
        overlay.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: overlay.convert(selectionPoint, to: nil),
            panel: panel
        ))
        overlay.mouseUp(with: try makeMouseButtonEvent(
            type: .leftMouseUp,
            point: overlay.convert(selectionPoint, to: nil),
            panel: panel
        ))
        overlay.keyDown(with: try makeKeyEvent("c", modifiers: .command, panel: panel))

        XCTAssertEqual(copiedText, "Frame")
    }

    func testOCRTextSelectionOverlayOnlyHitsTextWhenPointerToolIsActive() async throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true },
            recognizeText: { _ in
                RecognizedTextLayout(lines: [
                    RecognizedTextLine(
                        text: "Frame",
                        bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                        confidence: 0.9,
                        tokens: [
                            RecognizedTextToken(
                                text: "Frame",
                                bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                                needsLeadingSpace: false
                            ),
                        ]
                    ),
                ])
            },
            copyRecognizedText: { _ in true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }
        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()
        let canvas = try XCTUnwrap(findAnnotationCanvas(in: contentView))
        let overlay = try XCTUnwrap(findTextSelectionOverlay(in: contentView))
        let selectButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select"))
        let shapeButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Rectangle"))

        for _ in 0..<10 where !overlay.hasRecognizedText {
            await Task.yield()
        }
        XCTAssertTrue(overlay.hasRecognizedText)

        let selectionPoint = overlay.convert(
            canvas.convert(imageViewPoint(in: canvas, imagePoint: CGPoint(x: 64, y: 60)), to: nil),
            from: nil
        )
        XCTAssertTrue(overlay.hitTest(selectionPoint) === overlay)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(shapeButton.action), to: shapeButton.target, from: shapeButton))
        XCTAssertNil(overlay.hitTest(selectionPoint))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(selectButton.action), to: selectButton.target, from: selectButton))
        XCTAssertTrue(overlay.hitTest(selectionPoint) === overlay)
    }

    func testLiveCornerResizeKeepsInitialResizeAxisStableForPreviewAndPin() throws {
        try assertLiveCornerResizeKeepsInitialResizeAxisStable(kind: .temporaryPreview)
        try assertLiveCornerResizeKeepsInitialResizeAxisStable(kind: .pinned)
    }

    func testImageTextSelectionOverlayCopiesDraggedSelection() throws {
        _ = NSApplication.shared
        var copiedText: String?
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let overlay = ImageWorkspaceTextSelectionOverlayView(
            imageSize: CGSize(width: 320, height: 240),
            copyText: { text in
                copiedText = text
                return true
            }
        )
        overlay.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = overlay
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }
        XCTAssertFalse(overlay.mouseDownCanMoveWindow)

        overlay.setRecognizedTextLayout(RecognizedTextLayout(lines: [
            RecognizedTextLine(
                text: "你好啊",
                bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                confidence: 0.9,
                tokens: [
                    RecognizedTextToken(
                        text: "你",
                        bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.08, height: 0.1),
                        needsLeadingSpace: false
                    ),
                    RecognizedTextToken(
                        text: "好",
                        bounds: NormalizedImageRect(x: 0.2, y: 0.2, width: 0.08, height: 0.1),
                        needsLeadingSpace: false
                    ),
                    RecognizedTextToken(
                        text: "啊",
                        bounds: NormalizedImageRect(x: 0.3, y: 0.2, width: 0.08, height: 0.1),
                        needsLeadingSpace: false
                    ),
                ]
            ),
        ]))
        overlay.resetCursorRects()
        XCTAssertTrue(overlay.hitTest(NSPoint(x: 45, y: 60)) === overlay)
        XCTAssertNil(overlay.hitTest(NSPoint(x: 280, y: 220)))

        overlay.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: overlay.convert(NSPoint(x: 45, y: 60), to: nil),
            panel: panel
        ))
        overlay.mouseDragged(with: try makeMouseButtonEvent(
            type: .leftMouseDragged,
            point: overlay.convert(NSPoint(x: 73, y: 60), to: nil),
            panel: panel
        ))
        overlay.mouseDragged(with: try makeMouseButtonEvent(
            type: .leftMouseDragged,
            point: overlay.convert(NSPoint(x: 105, y: 60), to: nil),
            panel: panel
        ))
        overlay.mouseUp(with: try makeMouseButtonEvent(
            type: .leftMouseUp,
            point: overlay.convert(NSPoint(x: 105, y: 60), to: nil),
            panel: panel
        ))

        XCTAssertEqual(overlay.selectedTextForTesting, "你好啊")
        overlay.keyDown(with: try makeKeyEvent("c", modifiers: .command, panel: panel))
        XCTAssertEqual(copiedText, "你好啊")

        copiedText = nil
        let menu = try XCTUnwrap(overlay.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))
        let copyMenuItem = try XCTUnwrap(menu.item(withTitle: "Copy"))
        let copyTarget = try XCTUnwrap(copyMenuItem.target as? NSObject)
        let copyAction = try XCTUnwrap(copyMenuItem.action)
        XCTAssertTrue(copyTarget.responds(to: copyAction))
        copyTarget.perform(copyAction, with: copyMenuItem)
        XCTAssertEqual(copiedText, "你好啊")
    }

    func testImageTextSelectionOverlayClearsSelectionWhenClickingBlankArea() throws {
        _ = NSApplication.shared
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let overlay = ImageWorkspaceTextSelectionOverlayView(
            imageSize: CGSize(width: 320, height: 240),
            copyText: { _ in true }
        )
        overlay.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
        panel.contentView = overlay
        panel.orderFrontRegardless()
        defer {
            closePanel(panel)
        }

        overlay.setRecognizedTextLayout(RecognizedTextLayout(lines: [
            RecognizedTextLine(
                text: "Frame",
                bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                confidence: 0.9,
                tokens: [
                    RecognizedTextToken(
                        text: "Frame",
                        bounds: NormalizedImageRect(x: 0.1, y: 0.2, width: 0.2, height: 0.1),
                        needsLeadingSpace: false
                    ),
                ]
            ),
        ]))

        let textPoint = NSPoint(x: 45, y: 60)
        let blankPoint = NSPoint(x: 280, y: 220)
        XCTAssertTrue(overlay.hitTest(textPoint) === overlay)
        XCTAssertNil(overlay.hitTest(blankPoint))

        overlay.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: overlay.convert(textPoint, to: nil),
            panel: panel
        ))
        overlay.mouseUp(with: try makeMouseButtonEvent(
            type: .leftMouseUp,
            point: overlay.convert(textPoint, to: nil),
            panel: panel
        ))

        XCTAssertEqual(overlay.selectedTextForTesting, "Frame")
        XCTAssertTrue(overlay.hitTest(blankPoint) === overlay)

        overlay.mouseDown(with: try makeMouseButtonEvent(
            type: .leftMouseDown,
            point: overlay.convert(blankPoint, to: nil),
            panel: panel
        ))
        overlay.mouseUp(with: try makeMouseButtonEvent(
            type: .leftMouseUp,
            point: overlay.convert(blankPoint, to: nil),
            panel: panel
        ))

        XCTAssertEqual(overlay.selectedTextForTesting, "")
        XCTAssertNil(overlay.hitTest(blankPoint))
    }

    private func assertLiveCornerResizeKeepsInitialResizeAxisStable(kind: ImageWorkspaceKind) throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: kind,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            closePanel(panel)
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        panel.delegate?.windowWillStartLiveResize?(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))

        let initialContentSize = contentView.bounds.size
        let firstProposedContentSize = NSSize(
            width: initialContentSize.width + 12,
            height: initialContentSize.height + 80
        )
        let firstFrameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: firstProposedContentSize)).size
        let firstConstrainedFrameSize = try XCTUnwrap(panel.delegate?.windowWillResize?(panel, to: firstFrameSize))
        panel.setFrame(NSRect(origin: panel.frame.origin, size: firstConstrainedFrameSize), display: false)
        contentView.layoutSubtreeIfNeeded()

        let liveContentSize = contentView.bounds.size
        let secondProposedContentSize = NSSize(
            width: liveContentSize.width + 120,
            height: liveContentSize.height + 24
        )
        let secondFrameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: secondProposedContentSize)).size
        let secondConstrainedFrameSize = try XCTUnwrap(panel.delegate?.windowWillResize?(panel, to: secondFrameSize))
        let secondConstrainedContentSize = panel.contentRect(
            forFrameRect: NSRect(origin: .zero, size: secondConstrainedFrameSize)
        ).size

        XCTAssertEqual(secondConstrainedContentSize.height, secondProposedContentSize.height, accuracy: 0.5)
        panel.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
    }

    private func makeScreenshot() throws -> CapturedScreenshot {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 6,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return CapturedScreenshot(
            pngData: pngData,
            image: NSImage(size: NSSize(width: 320, height: 240)),
            rect: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
    }

    private func makeSolidScreenshot(id: UUID = UUID(), color: NSColor, size: CGSize = CGSize(width: 64, height: 48)) throws -> CapturedScreenshot {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        let pngData = try XCTUnwrap(image.pngDataForTesting())
        return CapturedScreenshot(
            id: id,
            pngData: pngData,
            image: image,
            rect: CGRect(origin: .zero, size: size)
        )
    }

    private func makeGradientScreenshot(size: CGSize = CGSize(width: 64, height: 48)) throws -> CapturedScreenshot {
        let image = NSImage(size: size)
        image.lockFocus()
        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                NSColor(
                    calibratedRed: CGFloat(x) / size.width,
                    green: CGFloat(y) / size.height,
                    blue: 0.3,
                    alpha: 1
                ).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        let pngData = try XCTUnwrap(image.pngDataForTesting())
        return CapturedScreenshot(
            pngData: pngData,
            image: image,
            rect: CGRect(origin: .zero, size: size)
        )
    }

    private func makeCheckerboardScreenshot(size: CGSize) throws -> CapturedScreenshot {
        let image = NSImage(size: size)
        image.lockFocus()
        for x in 0..<Int(size.width) {
            for y in 0..<Int(size.height) {
                ((x + y).isMultiple(of: 2) ? NSColor.white : NSColor.black).setFill()
                NSRect(x: x, y: y, width: 1, height: 1).fill()
            }
        }
        image.unlockFocus()
        let pngData = try XCTUnwrap(image.pngDataForTesting())
        return CapturedScreenshot(
            pngData: pngData,
            image: image,
            rect: CGRect(origin: .zero, size: size)
        )
    }

    private func showWorkspace(
        strings: AppStrings = AppStrings(language: .en),
        editingOptionsDefaults: UserDefaults? = nil,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool
    ) throws -> NSPanel {
        try showWorkspace(
            strings: strings,
            editingOptionsDefaults: editingOptionsDefaults,
            copy: { _ in copy() },
            save: { _ in save() }
        )
    }

    private func showWorkspace(
        strings: AppStrings = AppStrings(language: .en),
        editingOptionsDefaults: UserDefaults? = nil,
        saveCurrentBehavior: ImageWorkspaceSaveCurrentBehavior = .replaceCurrent,
        presentSaveCurrentMenu: @escaping (NSMenu, NSButton) -> Void = { _, _ in },
        copy: @escaping (CapturedScreenshot) -> Bool,
        save: @escaping (CapturedScreenshot) -> Bool,
        replaceCurrent: ((CapturedScreenshot) -> Void)? = nil,
        saveAsNew: ((CapturedScreenshot) -> Bool)? = nil,
        closeSaveChoice: (() -> ImageWorkspaceCloseSaveChoice)? = nil
    ) throws -> NSPanel {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controllerDefaults: UserDefaults
        if let editingOptionsDefaults {
            controllerDefaults = editingOptionsDefaults
        } else {
            let suiteName = "FrameTests.ImageWorkspaceOptions.\(UUID().uuidString)"
            temporaryDefaultsSuiteNames.append(suiteName)
            controllerDefaults = UserDefaults(suiteName: suiteName)!
        }
        let controller = ImageWorkspacePanelController(
            editingOptionsProvider: {
                SettingsStore.imageAnnotationEditingOptions(defaults: controllerDefaults)
            },
            persistEditingOptions: { options in
                SettingsStore.setImageAnnotationEditingOptions(options, defaults: controllerDefaults)
            },
            saveCurrentBehaviorProvider: {
                saveCurrentBehavior
            },
            presentSaveCurrentMenu: { menu, sender in
                presentSaveCurrentMenu(menu, sender)
            }
        )
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            strings: strings,
            copy: copy,
            save: save,
            replaceCurrent: replaceCurrent,
            saveAsNew: saveAsNew,
            closeSaveChoice: closeSaveChoice
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        panel.contentView?.layoutSubtreeIfNeeded()
        return panel
    }

    private func findButton(in view: NSView, accessibilityLabel: String) -> NSButton? {
        guard !view.isHidden else {
            return nil
        }

        if let button = view as? NSButton,
           button.accessibilityLabel() == accessibilityLabel {
            return button
        }

        for subview in view.subviews {
            if let button = findButton(in: subview, accessibilityLabel: accessibilityLabel) {
                return button
            }
        }

        return nil
    }

    private func orderedButtonTitles(in view: NSView) -> [String] {
        view.subviews.flatMap { subview -> [String] in
            if let button = subview as? NSButton {
                return [button.title]
            }

            return orderedButtonTitles(in: subview)
        }
    }

    private func orderedButtonAccessibilityLabels(in view: NSView) -> [String] {
        view.subviews.flatMap { subview -> [String] in
            if let button = subview as? NSButton {
                return [button.accessibilityLabel() ?? ""]
            }

            return orderedButtonAccessibilityLabels(in: subview)
        }
    }

    private func findSlider(in view: NSView, accessibilityLabel: String) -> NSSlider? {
        guard !view.isHidden else {
            return nil
        }

        if let slider = view as? NSSlider,
           slider.accessibilityLabel() == accessibilityLabel {
            return slider
        }

        for subview in view.subviews {
            if let slider = findSlider(in: subview, accessibilityLabel: accessibilityLabel) {
                return slider
            }
        }

        return nil
    }

    private func findAnnotationCanvas(in view: NSView) -> ImageAnnotationCanvasView? {
        if let canvas = view as? ImageAnnotationCanvasView {
            return canvas
        }

        for subview in view.subviews {
            if let canvas = findAnnotationCanvas(in: subview) {
                return canvas
            }
        }

        return nil
    }

    private func findZoomableImageSurface(in view: NSView) -> (NSView & ImageWorkspaceZoomableImageSurfaceForTesting)? {
        if let imageSurface = view as? (NSView & ImageWorkspaceZoomableImageSurfaceForTesting) {
            return imageSurface
        }

        for subview in view.subviews {
            if let imageSurface = findZoomableImageSurface(in: subview) {
                return imageSurface
            }
        }

        return nil
    }

    private func imageViewPoint(
        in imageSurface: NSView & ImageWorkspaceZoomableImageSurfaceForTesting,
        imagePoint: CGPoint,
        imageSize: CGSize = CGSize(width: 320, height: 240)
    ) -> NSPoint {
        let drawRect = imageSurface.lastDrawRectForTesting
        return NSPoint(
            x: drawRect.minX + imagePoint.x / imageSize.width * drawRect.width,
            y: drawRect.minY + imagePoint.y / imageSize.height * drawRect.height
        )
    }

    private func imageWindowPoint(
        in imageSurface: NSView & ImageWorkspaceZoomableImageSurfaceForTesting,
        imagePoint: CGPoint,
        imageSize: CGSize = CGSize(width: 320, height: 240)
    ) -> NSPoint {
        imageSurface.convert(imageViewPoint(in: imageSurface, imagePoint: imagePoint, imageSize: imageSize), to: nil)
    }

    private func findView(in view: NSView, accessibilityLabel: String) -> NSView? {
        if view.accessibilityLabel() == accessibilityLabel {
            return view
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, accessibilityLabel: accessibilityLabel) {
                return matchingView
            }
        }

        return nil
    }

    private func findView(in view: NSView, identifier: String) -> NSView? {
        if view.identifier?.rawValue == identifier {
            return view
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, identifier: identifier) {
                return matchingView
            }
        }

        return nil
    }

    private func findTextSelectionOverlay(in view: NSView) -> ImageWorkspaceTextSelectionOverlayView? {
        if let overlay = view as? ImageWorkspaceTextSelectionOverlayView {
            return overlay
        }

        for subview in view.subviews {
            if let overlay = findTextSelectionOverlay(in: subview) {
                return overlay
            }
        }

        return nil
    }

    private func workspacePanels(excluding windowIDs: Set<ObjectIdentifier>) -> [NSPanel] {
        NSApp.windows.compactMap { window in
            guard !windowIDs.contains(ObjectIdentifier(window)) else {
                return nil
            }

            return window as? NSPanel
        }
    }

    private func closePanel(_ panel: NSPanel) {
        panel.makeFirstResponder(nil)
        panel.contentView = nil
        panel.orderOut(nil)
        panel.close()
    }

    private func assertCircularHoverLayer(in button: NSButton) {
        button.layoutSubtreeIfNeeded()
        let hoverLayer = button.layer?.sublayers?.first
        XCTAssertNotNil(hoverLayer)
        XCTAssertEqual(hoverLayer?.bounds.width ?? 0, hoverLayer?.bounds.height ?? 1, accuracy: 0.5)
        XCTAssertEqual(hoverLayer?.cornerRadius ?? 0, (hoverLayer?.bounds.height ?? 0) / 2, accuracy: 0.5)
        XCTAssertEqual(hoverLayer?.opacity ?? 1, 0, accuracy: 0.01)
    }

    private func assertToolbarIconViewCentered(in button: NSButton) throws {
        button.layoutSubtreeIfNeeded()
        let iconView = try XCTUnwrap(button.subviews.compactMap { $0 as? NSImageView }.first)
        XCTAssertEqual(iconView.imageScaling, .scaleProportionallyDown)
        XCTAssertEqual(iconView.frame.width, 14, accuracy: 0.5)
        XCTAssertEqual(iconView.frame.height, 14, accuracy: 0.5)
        XCTAssertEqual(iconView.frame.midX, button.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(iconView.frame.midY, button.bounds.midY, accuracy: 0.5)

        let hoverLayer = try XCTUnwrap(button.layer?.sublayers?.first)
        XCTAssertEqual(iconView.frame.midX, hoverLayer.position.x, accuracy: 0.5)
        XCTAssertEqual(iconView.frame.midY, hoverLayer.position.y, accuracy: 0.5)
    }

    private func makeRightClickEvent(windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }

    private func makeMouseButtonEvent(
        type: NSEvent.EventType,
        point: NSPoint,
        panel: NSPanel,
        clickCount: Int = 1,
        modifiers: NSEvent.ModifierFlags = []
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: type == .leftMouseUp ? 0 : 1
        ))
    }

    private func makeMouseMoveEvent(
        point: NSPoint,
        panel: NSPanel
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
    }

    private func makeKeyEvent(
        _ character: String,
        modifiers: NSEvent.ModifierFlags,
        panel: NSPanel,
        keyCode: UInt16 = 0
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: keyCode
        ))
    }

    private func pixelColor(in pngData: Data, x: Int, y: Int) throws -> [UInt8] {
        let image = try XCTUnwrap(NSImage(data: pngData))
        let tiffData = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: tiffData))
        let imageRow = max(0, min(bitmap.pixelsHigh - 1, y))
        let xScale = CGFloat(bitmap.pixelsWide) / max(1, image.size.width)
        let yScale = CGFloat(bitmap.pixelsHigh) / max(1, image.size.height)
        let row = bitmap.pixelsHigh - 1 - max(0, min(bitmap.pixelsHigh - 1, Int((CGFloat(imageRow) * yScale).rounded())))
        let column = max(0, min(bitmap.pixelsWide - 1, Int((CGFloat(x) * xScale).rounded())))
        let color = try XCTUnwrap(bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB))
        return [
            UInt8((color.redComponent * 255).rounded()),
            UInt8((color.greenComponent * 255).rounded()),
            UInt8((color.blueComponent * 255).rounded()),
            UInt8((color.alphaComponent * 255).rounded()),
        ]
    }

    private func pixelColor(in view: NSView, x: Int, y: Int) throws -> [UInt8] {
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let row = max(0, min(bitmap.pixelsHigh - 1, y))
        let column = max(0, min(bitmap.pixelsWide - 1, x))
        let color = try XCTUnwrap(bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB))
        return [
            UInt8((color.redComponent * 255).rounded()),
            UInt8((color.greenComponent * 255).rounded()),
            UInt8((color.blueComponent * 255).rounded()),
            UInt8((color.alphaComponent * 255).rounded()),
        ]
    }

    private func isRedAnnotationPixel(_ color: [UInt8]) -> Bool {
        Int(color[0]) > 140
            && Int(color[0]) > Int(color[1]) + 20
            && Int(color[0]) > Int(color[2]) + 20
    }

    private func redPixelCount(in pngData: Data, x: Int, yRange: ClosedRange<Int>) throws -> Int {
        try yRange.filter { y in
            try isRedAnnotationPixel(pixelColor(in: pngData, x: x, y: y))
        }.count
    }
}

private extension NSImage {
    func pngDataForTesting() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

private final class FakeMagnifyEvent: NSEvent {
    private let fakeMagnification: CGFloat
    private let fakeLocationInWindow: NSPoint

    init(magnification: CGFloat, locationInWindow: NSPoint) {
        fakeMagnification = magnification
        fakeLocationInWindow = locationInWindow
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var magnification: CGFloat {
        fakeMagnification
    }

    override var locationInWindow: NSPoint {
        fakeLocationInWindow
    }
}

private final class FakeScrollWheelEvent: NSEvent {
    private let fakeDeltaX: CGFloat
    private let fakeDeltaY: CGFloat

    init(deltaX: CGFloat, deltaY: CGFloat) {
        fakeDeltaX = deltaX
        fakeDeltaY = deltaY
        super.init()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var scrollingDeltaX: CGFloat {
        fakeDeltaX
    }

    override var scrollingDeltaY: CGFloat {
        fakeDeltaY
    }
}

private final class TIFFAccessCountingImage: NSImage {
    private let counter = TIFFAccessCounter()

    var tiffAccessCount: Int {
        get {
            counter.count
        }
        set {
            counter.count = newValue
        }
    }

    override var tiffRepresentation: Data? {
        counter.count += 1
        return super.tiffRepresentation
    }

    override func draw(
        in dstRect: NSRect,
        from srcRect: NSRect,
        operation op: NSCompositingOperation,
        fraction delta: CGFloat
    ) {
        NSColor.white.setFill()
        dstRect.fill()
    }

    override func draw(
        in dstRect: NSRect,
        from srcRect: NSRect,
        operation op: NSCompositingOperation,
        fraction requestedAlpha: CGFloat,
        respectFlipped respectContextIsFlipped: Bool,
        hints: [NSImageRep.HintKey: Any]?
    ) {
        NSColor.white.setFill()
        dstRect.fill()
    }
}

private final class TIFFAccessCounter: @unchecked Sendable {
    var count = 0
}
