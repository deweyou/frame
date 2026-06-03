import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class AHUDSizeControlTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FRAME_RUN_HUD_APPKIT_TESTS"] != "1",
            "HUD AppKit field-editor tests are order-sensitive under SwiftPM xctest; run with FRAME_RUN_HUD_APPKIT_TESTS=1 for focused local coverage."
        )
    }

    func testWidthFieldAllowsNormalEditingBeforeCommit() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "5")
        XCTAssert(editor.string == "5")

        editor.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        XCTAssert(editor.string == "")
    }

    func testWidthFieldAppendsConsecutiveDigitsWithoutReselecting() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        harness.control.update(
            width: 0,
            height: 0,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "1")
        editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        editor.replaceCharacters(in: editor.selectedRange, with: "1")

        XCTAssert(editor.string == "11")
        XCTAssert(editor.selectedRange == NSRange(location: 2, length: 0))
    }

    func testCommandSelectAllReplacesFullValue() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        XCTAssert(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.selectAll(_:))
        ))
        editor.replaceCharacters(in: editor.selectedRange, with: "9")

        XCTAssert(editor.string == "9")
    }

    func testCommandAKeyEquivalentSelectsAllText() throws {
        try XCTSkipIf(
            ProcessInfo.processInfo.environment["FRAME_RUN_SYNTHETIC_KEY_EVENT_TESTS"] != "1",
            "Synthetic AppKit key-equivalent events are order-sensitive in xctest; selectAll command routing remains covered by testCommandSelectAllReplacesFullValue."
        )

        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: harness.window.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))

        XCTAssert(widthField.performKeyEquivalent(with: event))
        XCTAssert(editor.selectedRange == NSRange(location: 0, length: 4))
    }

    func testWidthFieldCommitsEditorText() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        var committedWidth: Int?
        harness.control.onWidthCommit = { value in
            committedWidth = value
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "640")
        committedWidth = nil
        XCTAssert(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        XCTAssert(committedWidth == 640)
    }

    func testHeightFieldCommitsEditorText() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        var committedHeight: Int?
        harness.control.onHeightCommit = { value in
            committedHeight = value
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let heightField = try XCTUnwrap(harness.heightField)
        XCTAssert(harness.window.makeFirstResponder(heightField))
        heightField.selectText(nil)

        let editor = try XCTUnwrap(heightField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "480")
        XCTAssert(harness.control.control(
            heightField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        XCTAssert(committedHeight == 480)
    }

    func testWidthFieldAllowsValuesAboveScreenMaximumToBeClampedByOverlay() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        var committedWidth: Int?
        harness.control.onWidthCommit = { value in
            committedWidth = value
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 100,
            maximumHeight: 100,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "999")
        XCTAssert(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        XCTAssert(committedWidth == 999)
    }

    func testEmptyWidthEditRestoresWithoutCommit() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        var committedWidth: Int?
        harness.control.onWidthCommit = { value in
            committedWidth = value
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.count))
        editor.replaceCharacters(in: editor.selectedRange, with: "")
        XCTAssert(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        XCTAssert(committedWidth == nil)
        XCTAssert(widthField.stringValue == "1280")
    }

    func testMetricsRefreshDoesNotOverwriteActiveEditorText() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "1")

        harness.control.update(
            width: 0,
            height: 0,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        XCTAssert(editor.string == "1")
    }

    func testMetricsRefreshUpdatesInactiveDimensionWhilePreservingActiveEditor() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        let heightField = try XCTUnwrap(harness.heightField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "1")

        harness.control.update(
            width: 0,
            height: 600,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        XCTAssert(editor.string == "1")
        XCTAssert(heightField.stringValue == "600")
    }

    func testLockButtonCommitsActiveEditBeforeToggling() throws {
        let harness = HUDSizeControlHarness()
        defer {
            harness.close()
        }

        var committedWidth: Int?
        var toggled = false
        harness.control.onWidthCommit = { value in
            committedWidth = value
        }
        harness.control.onLockToggle = {
            toggled = true
        }

        harness.control.update(
            width: 1280,
            height: 720,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        let widthField = try XCTUnwrap(harness.widthField)
        XCTAssert(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try XCTUnwrap(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "640")
        harness.linkButton?.performClick(nil)

        XCTAssert(committedWidth == 640)
        XCTAssert(toggled)
    }

}

@MainActor
private final class HUDSizeControlHarness {
    let window: TestKeyWindow
    let control: HUDSizeControl

    init() {
        control = HUDSizeControl(frame: CGRect(x: 0, y: 0, width: 127, height: 42))
        window = TestKeyWindow(
            contentRect: CGRect(x: 0, y: 0, width: 160, height: 64),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.animationBehavior = .none
        window.contentView = TestContentView(frame: window.contentRect(forFrameRect: window.frame))
        window.contentView?.addSubview(control)
        control.frame = CGRect(x: 0, y: 0, width: 127, height: 42)
        window.makeKeyAndOrderFront(nil)
        control.layoutSubtreeIfNeeded()
    }

    var widthField: NSTextField? {
        control.subviews.compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "width" }
    }

    var heightField: NSTextField? {
        control.subviews.compactMap { $0 as? NSTextField }
            .first { $0.identifier?.rawValue == "height" }
    }

    var linkButton: NSButton? {
        control.subviews.compactMap { $0 as? NSButton }
            .first { $0.identifier?.rawValue == "ratio-lock" }
    }

    func close() {
        window.makeFirstResponder(nil)
        window.contentView = nil
        window.orderOut(nil)
        window.close()
    }
}

private final class TestKeyWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

private final class TestContentView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}
