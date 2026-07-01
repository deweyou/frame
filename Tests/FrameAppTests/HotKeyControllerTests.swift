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

    func testRegistrationParametersMapDefaultRecordingShortcutToCarbonValues() {
        let parameters = HotKeyController.registrationParameters(for: .defaultRecording)

        XCTAssertEqual(parameters.keyCode, kVK_ANSI_R)
        XCTAssertEqual(parameters.modifierFlags, UInt32(cmdKey | shiftKey))
    }

    func testControllerDefaultsRecordingShortcutToEmpty() {
        let controller = HotKeyController()

        XCTAssertNil(controller.recordingShortcut)
    }

    func testRegisteredHotKeyIDsSkipEmptyRecordingShortcut() throws {
        let controller = HotKeyController(recordingShortcut: nil)

        try controller.registerHotKeysForTesting()

        XCTAssertEqual(controller.registeredHotKeyIDsForTesting(), [1])
    }

    func testRegisteredHotKeyIDsIncludeConfiguredRecordingShortcut() throws {
        let controller = HotKeyController(recordingShortcut: .defaultRecording)

        try controller.registerHotKeysForTesting()

        XCTAssertEqual(controller.registeredHotKeyIDsForTesting(), [1, 2])
    }

    func testHotKeyKindRoutesDistinctScreenshotAndRecordingIDs() {
        XCTAssertEqual(
            HotKeyController.hotKeyKindForTesting(signature: HotKeyController.hotKeySignatureForTesting, id: 1),
            .screenshot
        )
        XCTAssertEqual(
            HotKeyController.hotKeyKindForTesting(signature: HotKeyController.hotKeySignatureForTesting, id: 2),
            .recording
        )
    }
}
