import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class RecordingBoundaryOverlayControllerTests: XCTestCase {
    func testRecordingBoundaryShowsPassiveScreenOverlayAndIsExcludedFromCapture() throws {
        let controller = RecordingBoundaryOverlayController()
        defer {
            controller.close()
        }

        let screenFrame = try XCTUnwrap(NSScreen.main?.frame)
        let rect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 60,
            width: 320,
            height: 180
        )
        controller.show(rect: rect, preparationState: .loading)

        XCTAssertEqual(controller.frameForTesting(), screenFrame.integral)
        XCTAssertEqual(
            controller.selectionRectForTesting(),
            rect.integral.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        )
        XCTAssertEqual(controller.preparationStateForTesting(), .loading)
        XCTAssertLessThanOrEqual(try XCTUnwrap(controller.preparationIndicatorFrameForTesting()).width, 32)
        XCTAssertLessThanOrEqual(try XCTUnwrap(controller.preparationIndicatorFrameForTesting()).height, 32)
        controller.updatePreparationState(nil)
        XCTAssertNil(controller.preparationStateForTesting())
        XCTAssertEqual(controller.ignoresMouseEventsForTesting(), true)
        XCTAssertEqual(controller.sharingTypeForTesting(), NSWindow.SharingType.none)
    }

    func testShowingSameRecordingBoundaryUpdatesExistingPanelInPlace() throws {
        let controller = RecordingBoundaryOverlayController()
        defer {
            controller.close()
        }

        let screenFrame = try XCTUnwrap(NSScreen.main?.frame)
        let rect = CGRect(
            x: screenFrame.minX + 40,
            y: screenFrame.minY + 60,
            width: 320,
            height: 180
        )

        controller.show(rect: rect, preparationState: .loading)
        let firstPanelID = try XCTUnwrap(controller.panelIdentifierForTesting())

        controller.show(rect: rect, preparationState: nil)

        XCTAssertEqual(controller.panelIdentifierForTesting(), firstPanelID)
        XCTAssertNil(controller.preparationStateForTesting())
    }
}
