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
        XCTAssertEqual(controller.panelSizeForTesting(), CGSize(width: 175, height: 42))
        XCTAssertEqual(controller.rootViewFrameForTesting(), CGRect(origin: .zero, size: CGSize(width: 175, height: 42)))
        XCTAssertEqual(controller.chromeViewFrameForTesting(), CGRect(origin: .zero, size: CGSize(width: 175, height: 42)))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().minSize, CGSize(width: 175, height: 42))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().maxSize, CGSize(width: 175, height: 42))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().contentMinSize, CGSize(width: 175, height: 42))
        XCTAssertEqual(controller.panelSizeLimitsForTesting().contentMaxSize, CGSize(width: 175, height: 42))
        XCTAssertEqual(controller.horizontalPaddingForTesting(), 3)
        XCTAssertFalse(controller.panelHasSystemShadowForTesting())
        XCTAssertEqual(controller.elapsedTextColorForTesting(), ActiveRecordingHUDPanelController.recordingAccentColor)
        XCTAssertLessThan(controller.chromeColorsForTesting().background.relativeLuminanceForTesting, 0.08)
        XCTAssertGreaterThanOrEqual(controller.chromeColorsForTesting().background.relativeAlphaForTesting, 0.88)
        XCTAssertGreaterThan(controller.chromeColorsForTesting().border.relativeLuminanceForTesting, 0.8)
        XCTAssertGreaterThanOrEqual(controller.chromeColorsForTesting().border.relativeAlphaForTesting, 0.28)
        XCTAssertEqual(
            controller.buttonTintColorForTesting(accessibilityLabel: "停止录制"),
            ActiveRecordingHUDPanelController.recordingAccentColor
        )
        XCTAssertGreaterThan(
            controller.buttonTintColorForTesting(accessibilityLabel: "重新开始")?.relativeLuminanceForTesting ?? 0,
            0.8
        )
        XCTAssertGreaterThan(
            controller.buttonTintColorForTesting(accessibilityLabel: "删除录制")?.relativeLuminanceForTesting ?? 0,
            0.8
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

        XCTAssertEqual(controller.panelSizeForTesting(), CGSize(width: 175, height: 42))
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
        XCTAssertTrue(didStop)
        XCTAssertTrue(didRestart)
        XCTAssertTrue(didDelete)
    }

    func testDeleteInvokesImmediately() {
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
        XCTAssertTrue(didDelete)
        XCTAssertEqual(controller.buttonLabelsForTesting(), ["停止录制", "重新开始", "删除录制"])
    }
}

private extension NSColor {
    var relativeLuminanceForTesting: CGFloat {
        let color = usingColorSpace(.deviceRGB) ?? self
        return 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
    }

    var relativeAlphaForTesting: CGFloat {
        (usingColorSpace(.deviceRGB) ?? self).alphaComponent
    }
}
