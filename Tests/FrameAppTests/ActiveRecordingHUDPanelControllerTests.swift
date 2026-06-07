import XCTest
@testable import FrameApp

@MainActor
final class ActiveRecordingHUDPanelControllerTests: XCTestCase {
    func testActiveRecordingHUDShowsCompactControlsAndElapsedTime() {
        let controller = ActiveRecordingHUDPanelController()
        defer {
            controller.close()
        }

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            stop: {},
            restart: {},
            delete: {}
        )

        XCTAssertEqual(controller.buttonLabelsForTesting(), ["停止录制", "重新开始", "删除录制"])
        XCTAssertEqual(controller.elapsedTextForTesting(), "00:24")
        XCTAssertEqual(controller.panelSizeForTesting(), CGSize(width: 172, height: 42))
        XCTAssertEqual(controller.rootViewFrameForTesting(), CGRect(origin: .zero, size: CGSize(width: 172, height: 42)))
        XCTAssertEqual(controller.chromeViewFrameForTesting(), CGRect(origin: .zero, size: CGSize(width: 172, height: 42)))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().minSize, CGSize(width: 172, height: 42))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().maxSize, CGSize(width: 172, height: 42))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().contentMinSize, CGSize(width: 172, height: 42))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().contentMaxSize, CGSize(width: 172, height: 42))
        XCTAssertFalse(controller.panelHasSystemShadowForTesting())
        XCTAssertEqual(controller.elapsedTextColorForTesting(), ActiveRecordingHUDPanelController.recordingAccentColor)
        XCTAssertEqual(
            controller.buttonTintColorForTesting(accessibilityLabel: "停止录制"),
            ActiveRecordingHUDPanelController.recordingAccentColor
        )
    }

    func testPausedRecordingHUDKeepsRecoveryActions() {
        let controller = ActiveRecordingHUDPanelController()
        defer {
            controller.close()
        }

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: true,
            stop: {},
            restart: {},
            delete: {}
        )

        XCTAssertEqual(controller.buttonLabelsForTesting(), ["停止录制", "重新开始", "删除录制"])
    }

    func testShowReclaimsStaleOversizedPanelFrame() {
        let controller = ActiveRecordingHUDPanelController()
        defer {
            controller.close()
        }

        controller.setPanelFrameForTesting(CGRect(x: 20, y: 20, width: 200, height: 132))
        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            stop: {},
            restart: {},
            delete: {}
        )

        XCTAssertEqual(controller.panelSizeForTesting(), CGSize(width: 172, height: 42))
    }

    func testElapsedUpdatesDoNotRecreateButtons() {
        let controller = ActiveRecordingHUDPanelController()
        defer {
            controller.close()
        }

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            stop: {},
            restart: {},
            delete: {}
        )
        let initialButtonIDs = controller.buttonObjectIDsForTesting()

        controller.update(elapsed: 25, isPaused: false)
        controller.update(elapsed: 26, isPaused: false)

        XCTAssertEqual(controller.elapsedTextForTesting(), "00:26")
        XCTAssertEqual(controller.buttonObjectIDsForTesting(), initialButtonIDs)
    }

    func testActiveRecordingHUDInvokesRecoveryActions() {
        let controller = ActiveRecordingHUDPanelController()
        defer {
            controller.close()
        }
        var didStop = false
        var didRestart = false
        var didDelete = false

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            stop: { didStop = true },
            restart: { didRestart = true },
            delete: { didDelete = true }
        )

        XCTAssertTrue(controller.performButtonActionForTesting(accessibilityLabel: "停止录制"))
        XCTAssertTrue(controller.performButtonActionForTesting(accessibilityLabel: "重新开始"))
        XCTAssertTrue(controller.performButtonActionForTesting(accessibilityLabel: "删除录制"))
        XCTAssertTrue(controller.performButtonActionForTesting(accessibilityLabel: "确认删除"))
        XCTAssertTrue(didStop)
        XCTAssertTrue(didRestart)
        XCTAssertTrue(didDelete)
    }

    func testDeleteRequiresSecondConfirmationClick() {
        let controller = ActiveRecordingHUDPanelController()
        defer {
            controller.close()
        }
        var didDelete = false

        controller.show(
            near: CGRect(x: 20, y: 20, width: 320, height: 200),
            elapsed: 24,
            isPaused: false,
            stop: {},
            restart: {},
            delete: { didDelete = true }
        )

        XCTAssertTrue(controller.performButtonActionForTesting(accessibilityLabel: "删除录制"))
        XCTAssertFalse(didDelete)
        XCTAssertEqual(controller.buttonLabelsForTesting(), ["停止录制", "重新开始", "确认删除"])
        XCTAssertEqual(
            controller.buttonTintColorForTesting(accessibilityLabel: "确认删除"),
            ActiveRecordingHUDPanelController.recordingAccentColor
        )

        XCTAssertTrue(controller.performButtonActionForTesting(accessibilityLabel: "确认删除"))
        XCTAssertTrue(didDelete)
    }
}
