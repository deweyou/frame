import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsWindowLayoutSizesLeaveRoomForSettingsRows() {
        XCTAssertEqual(SettingsWindowLayout.defaultSize.width, 900, accuracy: 0.5)
        XCTAssertEqual(SettingsWindowLayout.defaultSize.height, 540, accuracy: 0.5)
        XCTAssertEqual(SettingsWindowLayout.minimumSize.width, 780, accuracy: 0.5)
        XCTAssertEqual(SettingsWindowLayout.minimumSize.height, 480, accuracy: 0.5)
    }

    func testSettingsWindowUsesConfiguredMinimumSize() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = SettingsWindowController()

        controller.show(
            strings: AppStrings(language: .en),
            onShortcutChange: { _ in true },
            onCheckPermission: {},
            onLanguageChange: { _ in },
            onChooseScreenshotDirectory: { nil },
            onResetScreenshotDirectory: {},
            onClearCaptureHistory: {}
        )

        let window = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) })
        defer {
            window.close()
        }

        XCTAssertEqual(window.minSize.width, 780, accuracy: 0.5)
        XCTAssertEqual(window.minSize.height, 480, accuracy: 0.5)
    }

    func testOCRLanguageSettingsExposeDefaultOptions() {
        XCTAssertEqual(OCRLanguageOption.allCases.map(\.rawValue).count, 25)
        XCTAssertEqual(OCRLanguageOption.defaultIdentifiers.count, 5)
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("zh-Hans"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("zh-Hant"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("en-US"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("ja-JP"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("ko-KR"))
    }

    func testRecordingMouseHintColorPresetsExposeDefaultAndCustomChoices() {
        XCTAssertEqual(RecordingMouseHintColorPreset.defaultPreset, .red)
        XCTAssertEqual(RecordingMouseHintColorPreset.standardPresets.map(\.id), [
            "red",
            "yellow",
            "blue",
            "green",
            "white",
            "black",
        ])
    }

    func testSettingsWindowPlacementCentersInsideActiveVisibleFrame() {
        let visibleFrame = CGRect(x: 1440, y: 80, width: 1200, height: 800)
        let frame = SettingsWindowLayout.centeredFrame(
            windowSize: CGSize(width: 900, height: 540),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.5)
        XCTAssertEqual(frame.width, 900, accuracy: 0.5)
        XCTAssertEqual(frame.height, 540, accuracy: 0.5)
    }
}
