import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class OCRTextPanelControllerTests: XCTestCase {
    private var retainedControllers: [OCRTextPanelController] = []

    func testOCRPanelShowsClearCutsWithoutScreenshotPreviewAndDisabledCopyButton() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        panel.contentView?.layoutSubtreeIfNeeded()

        XCTAssertNil(findImageView(in: contentView))
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
        XCTAssertEqual(cutButtons.map(\.title), ["为", "什", "么", "hello"])
        for button in cutButtons {
            XCTAssertEqual(button.layer?.borderWidth, 1)
            XCTAssertGreaterThanOrEqual(button.intrinsicContentSize.height, 24)
            XCTAssertLessThan(button.intrinsicContentSize.height, 28)
            XCTAssertGreaterThan(button.intrinsicContentSize.width, button.attributedTitle.size().width)
            XCTAssertEqual(button.layer?.borderColor, NSColor.separatorColor.withAlphaComponent(0.35).cgColor)
        }

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertFalse(copyButton.isEnabled)
        let copyAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy All"))
        XCTAssertTrue(copyAllButton.isEnabled)
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

        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyText: { _ in true })
        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyText: { _ in true })

        let panels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) && $0.isVisible }
        defer { panels.forEach { $0.close() } }
        XCTAssertEqual(panels.count, 1)
    }

    func testOCRPanelReuseUpdatesCutsAndClearsSelection() throws {
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
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        var contentView = try XCTUnwrap(panel.contentView)
        let selectAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select All"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(selectAllButton.action), to: selectAllButton.target, from: selectAllButton))
        XCTAssertTrue(try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected")).isEnabled)
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Clear"))

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "world", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { _ in true }
        )

        contentView = try XCTUnwrap(panel.contentView)
        XCTAssertEqual(findButtons(in: contentView, accessibilityPrefix: "OCR Cut").map(\.title), ["world"])
        XCTAssertFalse(try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected")).isEnabled)
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Select All"))
    }

    func testOCRPanelCutDocumentExpandsBeyondViewportForManyRows() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        let lines = (0..<32).map { index in
            RecognizedTextLine(text: "row\(index)", bounds: .zero, confidence: 0.9)
        }

        controller.show(
            layout: RecognizedTextLayout(lines: lines),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        panel.contentView?.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findScrollView(in: contentView))
        let documentView = try XCTUnwrap(scrollView.documentView)
        XCTAssertEqual(findButtons(in: contentView, accessibilityPrefix: "OCR Cut").count, lines.count)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertGreaterThan(documentView.frame.height, scrollView.contentView.bounds.height)
        XCTAssertGreaterThan(documentView.frame.height, 500)
    }

    func testOCRPanelWrapsCutsInsteadOfScrollingHorizontally() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "一二三四五六七八九十十一十二十三十四十五十六", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        panel.contentView?.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(findScrollView(in: contentView))
        let documentView = try XCTUnwrap(scrollView.documentView)
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
        XCTAssertGreaterThan(cutButtons.count, 12)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertEqual(documentView.frame.width, scrollView.contentView.bounds.width, accuracy: 1)
        XCTAssertGreaterThan(Set(cutButtons.map { round($0.frame.minY) }).count, 1)
    }

    func testOCRPanelFooterButtonsUseOrderedStackLayout() throws {
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
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        panel.contentView?.layoutSubtreeIfNeeded()

        let selectAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select All"))
        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        let footerStack = try XCTUnwrap(selectAllButton.superview as? NSStackView)
        XCTAssertTrue(copyButton.superview === footerStack)
        let copyAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy All"))
        XCTAssertTrue(copyAllButton.superview === footerStack)
        XCTAssertLessThan(
            footerStack.arrangedSubviews.firstIndex(of: selectAllButton) ?? .max,
            footerStack.arrangedSubviews.firstIndex(of: copyButton) ?? .min
        )
        XCTAssertLessThan(
            footerStack.arrangedSubviews.firstIndex(of: copyButton) ?? .max,
            footerStack.arrangedSubviews.firstIndex(of: copyAllButton) ?? .min
        )
        XCTAssertGreaterThanOrEqual(copyButton.frame.minX, selectAllButton.frame.maxX + footerStack.spacing)
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

        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyText: { _ in true })
        let firstPanel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        firstPanel.orderOut(nil)
        XCTAssertFalse(firstPanel.isVisible)

        controller.show(layout: layout, for: screenshot, strings: AppStrings(language: .en), copyText: { _ in true })

        let visiblePanels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) && $0.isVisible }
        XCTAssertEqual(visiblePanels.count, 1)
        XCTAssertTrue(visiblePanels.first === firstPanel)
        XCTAssertTrue(controller.closePanel(for: screenshot))
    }

    func testSelectAllThenCopySelectedInvokesClosureWithSelectedText() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)

        let selectAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select All"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(selectAllButton.action), to: selectAllButton.target, from: selectAllButton))

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertEqual(copiedText, "为什么 hello")
    }

    func testSelectAllButtonTogglesToDeselectAll() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)

        let selectAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select All"))
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(selectAllButton.action), to: selectAllButton.target, from: selectAllButton))
        let deselectAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Clear"))
        XCTAssertTrue(try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected")).isEnabled)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(deselectAllButton.action), to: deselectAllButton.target, from: deselectAllButton))
        XCTAssertFalse(try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected")).isEnabled)
        XCTAssertNotNil(findButton(in: contentView, accessibilityLabel: "Select All"))
    }

    func testCopyAllIsAvailableWithoutSelection() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)

        XCTAssertFalse(try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected")).isEnabled)
        let copyAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy All"))
        XCTAssertTrue(copyAllButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyAllButton.action), to: copyAllButton.target, from: copyAllButton))
        XCTAssertEqual(copiedText, "为什么 hello")
    }

    func testCommandASelectsAllCuts() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertEqual(copiedText, "为什么 hello")
    }

    func testSelectingCutsByIDsEnablesCopySelected() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { _ in true }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")

        controller.selectCutButtonsForTesting(Array(cutButtons.prefix(2)), in: panel)

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
    }

    func testShiftSelectingCutSelectsRangeFromPreviousSelection() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
        XCTAssertGreaterThanOrEqual(cutButtons.count, 4)

        controller.selectCutButtonsForTesting([cutButtons[0]], in: panel)
        controller.shiftSelectCutButtonForTesting(cutButtons[2], in: panel)

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertEqual(copiedText, "为什么")
    }

    func testShiftSelectingWithoutAnchorSelectsClickedCut() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
        XCTAssertGreaterThanOrEqual(cutButtons.count, 4)

        controller.shiftSelectCutButtonForTesting(cutButtons[3], in: panel)

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertEqual(copiedText, "hello")
    }

    func testScrubSelectionOnlyContinuesDuringActiveSession() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
        XCTAssertGreaterThanOrEqual(cutButtons.count, 3)

        controller.beginScrubSelectionForTesting(from: cutButtons[0], in: panel)
        controller.continueScrubSelectionForTesting(through: cutButtons[1], in: panel)
        controller.endScrubSelectionForTesting()
        controller.continueScrubSelectionForTesting(through: cutButtons[2], in: panel)

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertEqual(copiedText, "为什")
    }

    func testScrubSelectionFollowsDraggedWindowPointAcrossCuts() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = OCRTextPanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()
        var copiedText: String?

        controller.show(
            layout: RecognizedTextLayout(lines: [
                RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
            ]),
            for: screenshot,
            strings: AppStrings(language: .en),
            copyText: { text in
                copiedText = text
                return true
            }
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer { panel.close() }
        let contentView = try XCTUnwrap(panel.contentView)
        panel.contentView?.layoutSubtreeIfNeeded()
        let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
        XCTAssertGreaterThanOrEqual(cutButtons.count, 3)

        controller.beginScrubSelectionForTesting(from: cutButtons[0], in: panel)
        for button in cutButtons[1...2] {
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
            controller.continueScrubSelectionForTesting(atWindowPoint: point, in: panel)
        }
        controller.endScrubSelectionForTesting()

        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertEqual(copiedText, "为什么")
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

        controller.show(layout: layout, for: first, strings: AppStrings(language: .en), copyText: { _ in true })
        controller.show(layout: layout, for: second, strings: AppStrings(language: .en), copyText: { _ in true })

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

    private func findImageView(in view: NSView) -> NSImageView? {
        if let imageView = view as? NSImageView {
            return imageView
        }

        for subview in view.subviews {
            if let imageView = findImageView(in: subview) {
                return imageView
            }
        }

        return nil
    }

    private func findScrollView(in view: NSView) -> NSScrollView? {
        if let scrollView = view as? NSScrollView {
            return scrollView
        }

        for subview in view.subviews {
            if let scrollView = findScrollView(in: subview) {
                return scrollView
            }
        }

        return nil
    }

    private func findButtons(in view: NSView, accessibilityPrefix: String) -> [NSButton] {
        var buttons: [NSButton] = []
        if let button = view as? NSButton,
           button.accessibilityLabel()?.hasPrefix(accessibilityPrefix) == true {
            buttons.append(button)
        }

        for subview in view.subviews {
            buttons.append(contentsOf: findButtons(in: subview, accessibilityPrefix: accessibilityPrefix))
        }

        return buttons
    }
}
