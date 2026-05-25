import AppKit
import Testing
@testable import FrameApp

@MainActor
@Suite("HUD size control")
struct HUDSizeControlTests {
    @Test("width field allows normal editing before commit")
    func widthFieldAllowsNormalEditingBeforeCommit() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "5")
        #expect(editor.string == "5")

        editor.replaceCharacters(in: NSRange(location: 0, length: 1), with: "")
        #expect(editor.string == "")
    }

    @Test("width field appends consecutive digits without reselecting")
    func widthFieldAppendsConsecutiveDigitsWithoutReselecting() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "1")
        editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
        editor.replaceCharacters(in: editor.selectedRange, with: "1")

        #expect(editor.string == "11")
        #expect(editor.selectedRange == NSRange(location: 2, length: 0))
    }

    @Test("command select all replaces the full value")
    func commandSelectAllReplacesFullValue() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        #expect(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.selectAll(_:))
        ))
        editor.replaceCharacters(in: editor.selectedRange, with: "9")

        #expect(editor.string == "9")
    }

    @Test("command A key equivalent selects all text")
    func commandAKeyEquivalentSelectsAllText() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        let event = try #require(NSEvent.keyEvent(
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

        #expect(widthField.performKeyEquivalent(with: event))
        #expect(editor.selectedRange == NSRange(location: 0, length: 4))
    }

    @Test("width field commits editor text")
    func widthFieldCommitsEditorText() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "640")
        committedWidth = nil
        #expect(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        #expect(committedWidth == 640)
    }

    @Test("height field commits editor text")
    func heightFieldCommitsEditorText() throws {
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

        let heightField = try #require(harness.heightField)
        #expect(harness.window.makeFirstResponder(heightField))
        heightField.selectText(nil)

        let editor = try #require(heightField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "480")
        #expect(harness.control.control(
            heightField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        #expect(committedHeight == 480)
    }

    @Test("width field allows values above screen maximum to be clamped by overlay")
    func widthFieldAllowsValuesAboveScreenMaximumToBeClampedByOverlay() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "999")
        #expect(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        #expect(committedWidth == 999)
    }

    @Test("empty width edit restores without commit")
    func emptyWidthEditRestoresWithoutCommit() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.setSelectedRange(NSRange(location: 0, length: editor.string.count))
        editor.replaceCharacters(in: editor.selectedRange, with: "")
        #expect(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        #expect(committedWidth == nil)
        #expect(widthField.stringValue == "1280")
    }

    @Test("metrics refresh does not overwrite active editor text")
    func metricsRefreshDoesNotOverwriteActiveEditorText() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "1")

        harness.control.update(
            width: 0,
            height: 0,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        #expect(editor.string == "1")
    }

    @Test("metrics refresh updates inactive dimension while preserving active editor")
    func metricsRefreshUpdatesInactiveDimensionWhilePreservingActiveEditor() throws {
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

        let widthField = try #require(harness.widthField)
        let heightField = try #require(harness.heightField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "1")

        harness.control.update(
            width: 0,
            height: 600,
            maximumWidth: 4096,
            maximumHeight: 2304,
            isLocked: false,
            foregroundColor: .labelColor
        )

        #expect(editor.string == "1")
        #expect(heightField.stringValue == "600")
    }

    @Test("lock button commits active edit before toggling")
    func lockButtonCommitsActiveEditBeforeToggling() throws {
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

        let widthField = try #require(harness.widthField)
        #expect(harness.window.makeFirstResponder(widthField))
        widthField.selectText(nil)

        let editor = try #require(widthField.currentEditor() as? NSTextView)
        editor.replaceCharacters(in: editor.selectedRange, with: "640")
        harness.linkButton?.performClick(nil)

        #expect(committedWidth == 640)
        #expect(toggled)
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
            .first { $0.toolTip == "锁定比例" }
    }

    func close() {
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
