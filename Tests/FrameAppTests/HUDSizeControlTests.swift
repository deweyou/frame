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
        #expect(harness.control.control(
            widthField,
            textView: editor,
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))

        #expect(committedWidth == 640)
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
