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
        controller.show(rect: rect, countdownText: "5")

        XCTAssertEqual(controller.frameForTesting(), screenFrame.integral)
        XCTAssertEqual(
            controller.selectionRectForTesting(),
            rect.integral.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
        )
        XCTAssertEqual(controller.countdownTextForTesting(), "5")
        controller.updateCountdown("4")
        XCTAssertEqual(controller.countdownTextForTesting(), "4")
        XCTAssertEqual(controller.ignoresMouseEventsForTesting(), true)
        XCTAssertEqual(controller.sharingTypeForTesting(), NSWindow.SharingType.none)
    }
}
