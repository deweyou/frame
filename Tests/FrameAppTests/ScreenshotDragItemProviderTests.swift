import AppKit
import XCTest
@testable import FrameApp

@MainActor
final class ScreenshotDragItemProviderTests: XCTestCase {
    private var retainedPreviewControllers: [QuickAccessPanelController] = []

    func testDraggingItemProvidesPNGDataAndTemporaryFileURL() throws {
        let pngData = try makePNGData()
        let screenshot = CapturedScreenshot(
            pngData: pngData,
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        let draggingItem = ScreenshotDragItemProvider().draggingItem(
            for: screenshot,
            sourceBounds: NSRect(x: 0, y: 0, width: 2, height: 2)
        )

        let pasteboardItem = try XCTUnwrap(draggingItem.item as? NSPasteboardItem)
        XCTAssertEqual(pasteboardItem.data(forType: .png), pngData)

        let fileURLString = try XCTUnwrap(pasteboardItem.string(forType: .fileURL))
        let fileURL = try XCTUnwrap(URL(string: fileURLString))
        defer {
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
        }

        XCTAssertEqual(fileURL.lastPathComponent, "Frame Screenshot.png")
        XCTAssertEqual(try Data(contentsOf: fileURL), pngData)
    }

    func testPreviewHitTestingRoutesImageBodyToPreviewAndVisibleControlsToButtons() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)

        controller.show(
            for: screenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .zhHans),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }
        XCTAssertFalse(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.isMovable)
        XCTAssertFalse(panel.isMovableByWindowBackground)

        let previewView = try XCTUnwrap(panel.contentView)
        previewView.layoutSubtreeIfNeeded()

        XCTAssertIdentical(previewView.hitTest(NSPoint(x: 90, y: 60)), previewView)
        XCTAssertFalse(previewView is NSDraggingSource)
        XCTAssertTrue(previewView.acceptsFirstMouse(for: nil))

        let closeButton = try XCTUnwrap(findButton(in: previewView, accessibilityLabel: "关闭"))
        XCTAssertFalse(closeButton.frame.isEmpty)
        XCTAssertTrue(closeButton.acceptsFirstMouse(for: nil))
        let closePoint = NSPoint(x: closeButton.frame.midX, y: closeButton.frame.midY)

        XCTAssertIdentical(previewView.hitTest(closePoint), closeButton)

        let imageView = try XCTUnwrap(findPreviewImageView(in: previewView))
        XCTAssertEqual(imageView.frame.width, 200, accuracy: 0.5)
        XCTAssertEqual(imageView.frame.height, 132, accuracy: 0.5)

        XCTAssertEqual(closeButton.frame.width, 20, accuracy: 0.5)
        XCTAssertEqual(closeButton.frame.maxX, imageView.frame.maxX - 6, accuracy: 0.5)
        XCTAssertEqual(closeButton.frame.maxY, imageView.frame.maxY - 6, accuracy: 0.5)
        XCTAssertGreaterThan(closeButton.frame.minX, imageView.frame.minX)
        XCTAssertLessThan(closeButton.frame.maxY, previewView.bounds.maxY)
        XCTAssertEqual(closeButton.layer?.cornerRadius ?? 0, closeButton.frame.width / 2, accuracy: 0.5)
        XCTAssertEqual(closeButton.layer?.borderWidth ?? 0, 0.5, accuracy: 0.1)
        XCTAssertGreaterThan(closeButton.layer?.shadowOpacity ?? 0, 0)
        XCTAssertNotNil(closeButton.layer?.backgroundColor)

        let overlayView = try XCTUnwrap(findVisualEffectView(in: previewView))
        XCTAssertEqual(overlayView.frame.width, 154, accuracy: 0.5)
        XCTAssertEqual(overlayView.frame.height, 28, accuracy: 0.5)
        XCTAssertEqual(overlayView.frame.midX, imageView.frame.midX, accuracy: 0.5)
        XCTAssertLessThan(overlayView.frame.width, imageView.frame.width * 0.8)

        for label in ["保存", "复制", "识别文字", "固定到预览窗口", "打开预览"] {
            let button = try XCTUnwrap(findButton(in: previewView, accessibilityLabel: label))
            let buttonPoint = NSPoint(x: button.bounds.midX, y: button.bounds.midY)
            let previewPoint = previewView.convert(buttonPoint, from: button)

            XCTAssertIdentical(previewView.hitTest(previewPoint), button)
        }
    }

    func testQuickAccessActionButtonsUseSenderWindow() throws {
        _ = NSApplication.shared
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        var didCopy = false
        let copyPanel = try showPreview(
            screenshot: screenshot,
            copy: {
                didCopy = true
                return false
            },
            save: { false }
        )
        defer {
            copyPanel.close()
        }

        let copyButton = try XCTUnwrap(findButton(in: try XCTUnwrap(copyPanel.contentView), accessibilityLabel: "复制"))
        copyButton.performClick(nil)
        XCTAssertTrue(didCopy)

        var didSave = false
        let savePanel = try showPreview(
            screenshot: screenshot,
            copy: { false },
            save: {
                didSave = true
                return false
            }
        )
        defer {
            savePanel.close()
        }

        let saveButton = try XCTUnwrap(findButton(in: try XCTUnwrap(savePanel.contentView), accessibilityLabel: "保存"))
        saveButton.performClick(nil)
        XCTAssertTrue(didSave)
    }

    func testQuickAccessOCRButtonRoutesActionWithoutClosingPreview() throws {
        _ = NSApplication.shared
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        var didRecognizeText = false

        let panel = try showPreview(
            screenshot: screenshot,
            copy: { false },
            save: { false },
            recognizeText: {
                didRecognizeText = true
                return true
            }
        )
        defer {
            panel.close()
        }

        let ocrButton = try XCTUnwrap(findButton(in: try XCTUnwrap(panel.contentView), accessibilityLabel: "识别文字"))
        ocrButton.performClick(nil)

        XCTAssertTrue(didRecognizeText)
        XCTAssertTrue(panel.isVisible)
    }

    func testQuickAccessCanClosePreviewForMatchingScreenshotOnly() throws {
        _ = NSApplication.shared
        let firstScreenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let secondScreenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))

        controller.show(
            for: firstScreenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .zhHans),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {}
        )
        controller.show(
            for: secondScreenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .zhHans),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {}
        )

        let previewPanels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) }
        XCTAssertEqual(previewPanels.count, 2)

        XCTAssertTrue(controller.closePreview(for: firstScreenshot, notify: false))
        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 1)

        for panel in previewPanels where panel.isVisible {
            panel.close()
        }
    }

    func testQuickAccessCanTemporarilyHideAndRestoreAllPreviews() throws {
        _ = NSApplication.shared
        let firstScreenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let secondScreenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        var closeCount = 0

        controller.show(
            for: firstScreenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .zhHans),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {
                closeCount += 1
            }
        )
        controller.show(
            for: secondScreenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .zhHans),
            copy: { true },
            save: { true },
            recognizeText: { true },
            openWorkspace: { true },
            pin: { true },
            close: {
                closeCount += 1
            }
        )

        let previewPanels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) }
        XCTAssertEqual(previewPanels.count, 2)

        controller.temporarilyHidePreviews()

        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 0)
        XCTAssertEqual(closeCount, 0)

        controller.restoreTemporarilyHiddenPreviews()

        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 2)
        XCTAssertTrue(controller.closePreview(for: firstScreenshot, notify: false))
        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 1)
    }

    func testQuickAccessActionButtonsReceivePanelMouseClicks() throws {
        _ = NSApplication.shared
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )

        var didCopy = false
        let copyPanel = try showPreview(
            screenshot: screenshot,
            copy: {
                didCopy = true
                return false
            },
            save: { false }
        )
        defer {
            copyPanel.close()
        }
        try clickButton(accessibilityLabel: "复制", in: copyPanel)
        XCTAssertTrue(didCopy)

        var didSave = false
        let savePanel = try showPreview(
            screenshot: screenshot,
            copy: { false },
            save: {
                didSave = true
                return false
            }
        )
        defer {
            savePanel.close()
        }
        try clickButton(accessibilityLabel: "保存", in: savePanel)
        XCTAssertTrue(didSave)
    }

    private func makePNGData() throws -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 2,
            pixelsHigh: 2,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )

        return try XCTUnwrap(bitmap?.representation(using: .png, properties: [:]))
    }

    private func showPreview(
        screenshot: CapturedScreenshot,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        recognizeText: @escaping () -> Bool = { false }
    ) throws -> NSPanel {
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        controller.show(
            for: screenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .zhHans),
            copy: copy,
            save: save,
            recognizeText: recognizeText,
            openWorkspace: { true },
            pin: { true },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        panel.contentView?.layoutSubtreeIfNeeded()
        return panel
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

    private func findVisualEffectView(in view: NSView) -> NSVisualEffectView? {
        if let visualEffectView = view as? NSVisualEffectView {
            return visualEffectView
        }

        for subview in view.subviews {
            if let visualEffectView = findVisualEffectView(in: subview) {
                return visualEffectView
            }
        }

        return nil
    }

    private func findPreviewImageView(in view: NSView) -> NSView? {
        view.subviews.first { subview in
            !(subview is NSButton) && !(subview is NSVisualEffectView)
        }
    }

    private func clickButton(accessibilityLabel: String, in panel: NSPanel) throws {
        let contentView = try XCTUnwrap(panel.contentView)
        let button = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: accessibilityLabel))
        let windowPoint = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)

        let mouseDown = try makeMouseButtonEvent(type: .leftMouseDown, point: windowPoint, panel: panel)
        let mouseUp = try makeMouseButtonEvent(type: .leftMouseUp, point: windowPoint, panel: panel)

        panel.sendEvent(mouseDown)
        panel.sendEvent(mouseUp)
    }

    private func makeMouseButtonEvent(type: NSEvent.EventType, point: NSPoint, panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ))
    }

    private func makeMouseEvent(for panel: NSPanel) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .mouseMoved,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0
        ))
    }
}
