import Carbon
import XCTest
import FrameCore
@testable import FrameApp

@MainActor
final class HotKeyControllerTests: XCTestCase {
    func testRegistrationParametersMapCustomShortcutToCarbonValues() {
        let shortcut = ScreenshotShortcut(key: .letter("Z"), modifiers: [.command, .option, .shift])

        let parameters = HotKeyController.registrationParameters(for: shortcut)

        XCTAssertEqual(parameters.keyCode, kVK_ANSI_Z)
        XCTAssertEqual(parameters.modifierFlags, UInt32(cmdKey | optionKey | shiftKey))
    }

    func testRegistrationParametersMapNumberShortcutToCarbonValues() {
        let shortcut = ScreenshotShortcut(key: .number("7"), modifiers: [.control, .shift])

        let parameters = HotKeyController.registrationParameters(for: shortcut)

        XCTAssertEqual(parameters.keyCode, kVK_ANSI_7)
        XCTAssertEqual(parameters.modifierFlags, UInt32(controlKey | shiftKey))
    }
}
