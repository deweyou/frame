import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class ScrollingScreenshotPreviewPanelControllerTests: XCTestCase {
    func testLayoutPrefersRightSideAndUsesFixedSize() throws {
        let screenFrame = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let selectionRect = CGRect(x: 100, y: 160, width: 400, height: 400)

        let layout = try XCTUnwrap(
            ScrollingScreenshotPreviewPanelController.previewLayout(
                selectionRect: selectionRect,
                screenFrame: screenFrame
            )
        )

        XCTAssertEqual(layout.size, CGSize(width: 220, height: 320))
        XCTAssertEqual(layout.frame.minX, selectionRect.maxX + 12)
        XCTAssertFalse(layout.frame.intersects(selectionRect))
    }

    func testLayoutUsesCompactBoxOnSideWithLimitedSpace() throws {
        let screenFrame = CGRect(x: 0, y: 0, width: 600, height: 700)
        let selectionRect = CGRect(x: 190, y: 150, width: 250, height: 350)

        let layout = try XCTUnwrap(
            ScrollingScreenshotPreviewPanelController.previewLayout(
                selectionRect: selectionRect,
                screenFrame: screenFrame
            )
        )

        XCTAssertEqual(layout.size, CGSize(width: 160, height: 240))
        XCTAssertEqual(layout.frame.maxX, selectionRect.minX - 12)
        XCTAssertFalse(layout.frame.intersects(selectionRect))
    }

    func testLayoutReturnsNilWhenNoFixedBoxFitsOutsideSelection() {
        let layout = ScrollingScreenshotPreviewPanelController.previewLayout(
            selectionRect: CGRect(x: 10, y: 10, width: 580, height: 680),
            screenFrame: CGRect(x: 0, y: 0, width: 600, height: 700)
        )

        XCTAssertNil(layout)
    }

    func testPreviewImageDestinationUsesFixedHeightAndCentersHorizontally() {
        let destination = ScrollingScreenshotPreviewImageView.destinationRect(
            imageSize: CGSize(width: 100, height: 300),
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )

        XCTAssertEqual(destination.height, 200, accuracy: 0.001)
        XCTAssertEqual(destination.width, 200 / 3, accuracy: 0.001)
        XCTAssertEqual(destination.midX, 100, accuracy: 0.001)
        XCTAssertEqual(destination.minY, 0, accuracy: 0.001)
    }

    func testPanelIsFixedNonInteractiveAndUsesFullBoxForImagePreview() throws {
        let controller = ScrollingScreenshotPreviewPanelController(
            screenFrameProvider: { CGRect(x: 0, y: 0, width: 1_200, height: 800) }
        )
        controller.show(selectionRect: CGRect(x: 100, y: 160, width: 400, height: 400))
        let image = NSImage(size: CGSize(width: 100, height: 300))
        controller.update(image: image, status: .capturing)
        controller.update(image: nil, status: .unreliableOverlap)

        XCTAssertEqual(controller.panelSizeForTesting(), CGSize(width: 220, height: 320))
        XCTAssertTrue(controller.panelIgnoresMouseEventsForTesting())
        XCTAssertIdentical(controller.previewImageForTesting(), image)
        XCTAssertEqual(controller.statusForTesting(), .unreliableOverlap)
        let visibleFrames = try XCTUnwrap(controller.visibleFramesForTesting())
        XCTAssertTrue(visibleFrames.panel.contains(visibleFrames.status))
        XCTAssertTrue(visibleFrames.panel.contains(visibleFrames.preview))
        XCTAssertEqual(visibleFrames.preview, visibleFrames.panel.insetBy(dx: 8, dy: 8))

        controller.close()
    }
}
