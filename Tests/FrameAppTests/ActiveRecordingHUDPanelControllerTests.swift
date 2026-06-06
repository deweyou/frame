import XCTest
@testable import FrameApp

@MainActor
final class ActiveRecordingHUDPanelControllerTests: XCTestCase {
    func testActiveRecordingHUDShowsCompactControlsAndElapsedTime() {
        let controller = ActiveRecordingHUDPanelController()

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            pause: {},
            resume: {},
            stop: {}
        )

        XCTAssertEqual(controller.buttonLabelsForTesting(), ["暂停", "停止录制"])
        XCTAssertEqual(controller.elapsedTextForTesting(), "00:24")
        XCTAssertEqual(controller.panelSizeForTesting(), CGSize(width: 178, height: 42))
    }

    func testPausedRecordingHUDShowsResume() {
        let controller = ActiveRecordingHUDPanelController()

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: true,
            pause: {},
            resume: {},
            stop: {}
        )

        XCTAssertEqual(controller.buttonLabelsForTesting(), ["继续", "停止录制"])
    }

    func testStoppingRecordingHUDShowsImmediateFeedback() {
        let controller = ActiveRecordingHUDPanelController()

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            pause: {},
            resume: {},
            stop: {}
        )
        controller.setStopping(true)

        XCTAssertEqual(controller.buttonLabelsForTesting(), ["暂停", "正在停止"])
    }
}
