import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class OCRTextPanelControllerTests: XCTestCase {
    private var retainedControllers: [OCRTextPanelController] = []

    func testOCRPanelShowsSelectableRecognizedTextAndCopyAllButton() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyAll: { true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }

        let textView = try XCTUnwrap(findTextView(in: try XCTUnwrap(panel.contentView)))
        XCTAssertEqual(textView.string, "hello")
        XCTAssertTrue(textView.isSelectable)
        XCTAssertFalse(textView.isEditable)
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(textView.frame.width, 0)
        XCTAssertGreaterThan(textView.frame.height, textView.font?.pointSize ?? 0)

        let button = try XCTUnwrap(findButton(in: try XCTUnwrap(panel.contentView), accessibilityLabel: "Copy All"))
        XCTAssertTrue(button.isEnabled)
    }

    func testOCRPanelReusesExistingWindowForSameScreenshot() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        let layout = RecognizedTextLayout(lines: [
            RecognizedTextLine(text: "hello", bounds: .zero, confidence: 0.9),
        ])

        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyAll: { true })
        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyAll: { true })

        let panels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) && $0.isVisible }
        defer { panels.forEach { $0.close() } }
        XCTAssertEqual(panels.count, 1)
    }

    func testOCRPanelReusesOrderedOutWindowForSameScreenshot() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        let layout = RecognizedTextLayout(lines: [
            RecognizedTextLine(text: "hello", bounds: .zero, confidence: 0.9),
        ])

        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyAll: { true })
        let firstPanel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        firstPanel.orderOut(nil)
        XCTAssertFalse(firstPanel.isVisible)

        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyAll: { true })

        let visiblePanels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) && $0.isVisible }
        XCTAssertEqual(visiblePanels.count, 1)
        XCTAssertTrue(visiblePanels.first === firstPanel)
        XCTAssertTrue(controller.closePanel(for: screenshot))
    }

    func testCopyAllButtonInvokesClosureUsingSenderWindow() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var didCopyAll = false

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyAll: {
                didCopyAll = true
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }

        let button = try XCTUnwrap(findButton(in: try XCTUnwrap(panel.contentView), accessibilityLabel: "Copy All"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(button.action), to: button.target, from: button))
        XCTAssertTrue(didCopyAll)
    }

    func testClosePanelForScreenshotClosesMatchingPanelOnly() throws {
        _ = NSApplication.shared
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let first = try makeScreenshot()
        let second = try makeScreenshot()
        let layout = RecognizedTextLayout(lines: [
            RecognizedTextLine(text: "hello", bounds: .zero, confidence: 0.9),
        ])

        controller.show(layout: layout, for: first, strings: AppStrings(language: .en), copyAll: { true })
        controller.show(layout: layout, for: second, strings: AppStrings(language: .en), copyAll: { true })

        XCTAssertTrue(controller.closePanel(for: first))
        XCTAssertFalse(controller.closePanel(for: first))
        XCTAssertTrue(controller.closePanel(for: second))
    }

    private func makeScreenshot() throws -> CapturedScreenshot {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 8,
            pixelsHigh: 6,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let pngData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return CapturedScreenshot(
            pngData: pngData,
            image: NSImage(size: NSSize(width: 320, height: 240)),
            rect: CGRect(x: 0, y: 0, width: 320, height: 240)
        )
    }

    private func findButton(in view: NSView, accessibilityLabel: String) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == accessibilityLabel {
            return button
        }

        for subview in view.subviews {
            if let button = findButton(in: subview, accessibilityLabel: accessibilityLabel) {
                return button
            }
        }

        return nil
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        if let scrollView = view as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }

        return nil
    }
}
