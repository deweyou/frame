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
            onResetScreenshotDirectory: {}
        )

        let window = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) })
        defer {
            window.close()
        }

        XCTAssertEqual(window.minSize.width, 780, accuracy: 0.5)
        XCTAssertEqual(window.minSize.height, 480, accuracy: 0.5)
    }

    func testSettingsWindowShowsOCRLanguageControls() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = SettingsWindowController()

        controller.show(
            strings: AppStrings(language: .en),
            onShortcutChange: { _ in true },
            onCheckPermission: {},
            onLanguageChange: { _ in },
            onChooseScreenshotDirectory: { nil },
            onResetScreenshotDirectory: {}
        )

        let window = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) })
        defer {
            window.close()
        }

        let contentView = try XCTUnwrap(window.contentViewController?.view)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        let ocrLanguageButtons = checkboxButtons(in: contentView)

        XCTAssertEqual(ocrLanguageButtons.count, OCRLanguageOption.allCases.count)
        XCTAssertEqual(
            ocrLanguageButtons.filter { $0.state == .on }.count,
            OCRLanguageOption.defaultIdentifiers.count
        )
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

    private func checkboxButtons(in view: NSView) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton,
           String(describing: type(of: button)).contains("FocusRingNSButton") {
            buttons.append(button)
        }

        for subview in view.subviews {
            buttons.append(contentsOf: checkboxButtons(in: subview))
        }

        return buttons
    }
}
