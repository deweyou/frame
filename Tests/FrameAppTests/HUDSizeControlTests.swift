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
