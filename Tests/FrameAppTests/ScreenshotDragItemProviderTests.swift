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
            image: NSImage(size: NSSize(width: 1600, height: 900)),
            rect: CGRect(x: 0, y: 0, width: 1600, height: 900)
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
        let expectedPreviewSize = CapturePreviewMetrics.quickAccessCardSize
        XCTAssertEqual(imageView.frame.width, expectedPreviewSize.width, accuracy: 0.5)
        XCTAssertEqual(imageView.frame.height, expectedPreviewSize.height, accuracy: 0.5)
        XCTAssertEqual(
            imageView.frame.height / imageView.frame.width,
            expectedPreviewSize.height / expectedPreviewSize.width,
            accuracy: 0.01
        )
        XCTAssertNotEqual(imageView.layer?.backgroundColor, NSColor.clear.cgColor)

        XCTAssertEqual(closeButton.frame.width, 20, accuracy: 0.5)
        XCTAssertEqual(closeButton.frame.maxX, imageView.frame.maxX - 6, accuracy: 0.5)
        XCTAssertEqual(closeButton.frame.maxY, imageView.frame.maxY - 6, accuracy: 0.5)
        XCTAssertGreaterThan(closeButton.frame.minX, imageView.frame.minX)
        XCTAssertLessThan(closeButton.frame.maxY, previewView.bounds.maxY)
        XCTAssertEqual(closeButton.layer?.cornerRadius ?? 0, closeButton.frame.width / 2, accuracy: 0.5)
        XCTAssertEqual(closeButton.layer?.borderWidth ?? 0, 0.5, accuracy: 0.1)
        XCTAssertGreaterThan(closeButton.layer?.shadowOpacity ?? 0, 0)
        let closeBackground = try XCTUnwrap(closeButton.layer?.backgroundColor)
        let closeBackgroundAlpha = try XCTUnwrap(NSColor(cgColor: closeBackground)?.alphaComponent)
        XCTAssertGreaterThan(closeBackgroundAlpha, 0.2)
        XCTAssertLessThan(closeBackgroundAlpha, 0.7)
        let closeButtonBackground = closeButton.layer?.backgroundColor
        let iconLayer = try XCTUnwrap(closeButton.layer?.sublayers?.first)
        XCTAssertEqual(iconLayer.position.x, closeButton.bounds.midX, accuracy: 0.5)
        XCTAssertEqual(iconLayer.position.y, closeButton.bounds.midY, accuracy: 0.5)
        XCTAssertEqual(iconLayer.bounds.width, iconLayer.bounds.height, accuracy: 0.5)
        let iconStrokeColor = try XCTUnwrap((iconLayer as? CAShapeLayer)?.strokeColor)
        let iconStrokeAlpha = try XCTUnwrap(NSColor(cgColor: iconStrokeColor)?.alphaComponent)
        XCTAssertLessThan(iconStrokeAlpha, 0.75)
        let closeButtonCell = try XCTUnwrap(closeButton.cell as? NSButtonCell)
        XCTAssertTrue(closeButtonCell.highlightsBy.isEmpty)
        XCTAssertTrue(closeButtonCell.showsStateBy.isEmpty)
        XCTAssertNil(closeButtonCell.image)
        XCTAssertNotNil(closeButton.image)
        closeButton.highlight(true)
        XCTAssertFalse(closeButton.cell?.isHighlighted == true)
        XCTAssertEqual(closeButton.state, .off)
        XCTAssertEqual(closeButton.layer?.backgroundColor, closeButtonBackground)
        closeButton.highlight(false)
        closeButton.state = .on
        XCTAssertEqual(closeButton.state, .off)
        closeButton.cell?.isHighlighted = true
        closeButton.needsDisplay = true
        closeButton.displayIfNeeded()
        XCTAssertFalse(closeButton.cell?.isHighlighted == true)

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

    func testQuickAccessToolbarUsesReadableSymbolsWithConsistentScaling() throws {
        _ = NSApplication.shared
        let panel = try showPreview(
            screenshot: CapturedScreenshot(
                pngData: try makePNGData(),
                image: NSImage(size: NSSize(width: 1600, height: 900)),
                rect: CGRect(x: 0, y: 0, width: 1600, height: 900)
            ),
            copy: { true },
            save: { true }
        )
        defer {
            panel.close()
        }

        let previewView = try XCTUnwrap(panel.contentView)
        let expectedSymbolsByLabel = [
            "保存": "square.and.arrow.down",
            "复制": "doc.on.doc",
            "识别文字": "character.textbox",
            "固定到预览窗口": "pin",
            "打开预览": "arrow.up.left.and.arrow.down.right"
        ]
        let expectedConfigurationsByLabel = [
            "保存": NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold),
            "复制": NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold),
            "识别文字": NSImage.SymbolConfiguration(pointSize: 12.5, weight: .semibold),
            "固定到预览窗口": NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold),
            "打开预览": NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        ]

        for (label, symbolName) in expectedSymbolsByLabel {
            let button = try XCTUnwrap(findButton(in: previewView, accessibilityLabel: label))

            XCTAssertEqual(button.identifier?.rawValue, symbolName)
            XCTAssertEqual(button.imageScaling, .scaleNone)
            XCTAssertEqual(button.symbolConfiguration, expectedConfigurationsByLabel[label])
        }
    }

    func testQuickAccessPreviewUsesSharedCardSize() throws {
        _ = NSApplication.shared
        let panel = try showPreview(
            screenshot: CapturedScreenshot(
                pngData: try makePNGData(),
                image: NSImage(size: NSSize(width: 1600, height: 900)),
                rect: CGRect(x: 0, y: 0, width: 1600, height: 900)
            ),
            copy: { true },
            save: { true }
        )
        defer {
            panel.close()
        }

        let previewView = try XCTUnwrap(panel.contentView)
        previewView.layoutSubtreeIfNeeded()

        let imageView = try XCTUnwrap(findPreviewImageView(in: previewView))
        let expectedPreviewSize = CapturePreviewMetrics.quickAccessCardSize
        XCTAssertEqual(imageView.frame.width, expectedPreviewSize.width, accuracy: 0.5)
        XCTAssertEqual(imageView.frame.height, expectedPreviewSize.height, accuracy: 0.5)
        XCTAssertEqual(
            imageView.frame.height / imageView.frame.width,
            expectedPreviewSize.height / expectedPreviewSize.width,
            accuracy: 0.01
        )
    }

    func testCapturePreviewMetricsUsesDesktopAspectRatioForFixedSize() {
        XCTAssertEqual(
            CapturePreviewMetrics.previewSize(forDesktopSize: CGSize(width: 1600, height: 900)),
            CGSize(width: 200, height: 112)
        )
    }

    func testCapturePreviewMetricsAspectFillDrawRectCoversPreviewBounds() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 112)
        let drawRect = CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: CGSize(width: 200, height: 400),
            in: bounds
        )

        XCTAssertGreaterThanOrEqual(drawRect.width, bounds.width)
        XCTAssertGreaterThanOrEqual(drawRect.height, bounds.height)
        XCTAssertEqual(drawRect.midX, bounds.midX, accuracy: 0.5)
        XCTAssertEqual(drawRect.midY, bounds.midY, accuracy: 0.5)
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
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
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
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(saveButton.action), to: saveButton.target, from: saveButton))
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
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(ocrButton.action), to: ocrButton.target, from: ocrButton))

        XCTAssertTrue(didRecognizeText)
        XCTAssertTrue(panel.isVisible)
    }

    func testQuickAccessOCRStatusDisablesButtonAndShowsMessage() throws {
        _ = NSApplication.shared
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))

        controller.show(
            for: screenshot,
            preferredAnchor: nil,
            strings: AppStrings(language: .en),
            copy: { false },
            save: { false },
            recognizeText: { true },
            openWorkspace: { false },
            pin: { false },
            close: {}
        )

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }
        let contentView = try XCTUnwrap(panel.contentView)
        let ocrButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Recognize Text"))
        let statusLabel = try XCTUnwrap(findTextField(in: contentView, accessibilityLabel: "OCR Status"))
        let progressIndicator = try XCTUnwrap(findProgressIndicator(in: contentView, accessibilityLabel: "Recognizing..."))

        controller.setOCRStatus(.recognizing("Recognizing..."), for: screenshot)

        XCTAssertFalse(ocrButton.isEnabled)
        XCTAssertFalse(progressIndicator.isHidden)
        XCTAssertEqual(statusLabel.stringValue, "")
        XCTAssertEqual(statusLabel.alphaValue, 0, accuracy: 0.01)

        controller.setOCRStatus(.message("No text found", resetAfter: nil), for: screenshot)

        XCTAssertTrue(ocrButton.isEnabled)
        XCTAssertTrue(progressIndicator.isHidden)
        XCTAssertEqual(statusLabel.stringValue, "No text found")
        XCTAssertEqual(statusLabel.alphaValue, 1, accuracy: 0.01)
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
        XCTAssertTrue(previewPanels.allSatisfy { $0.alphaValue == 0 })
        XCTAssertTrue(previewPanels.allSatisfy(\.ignoresMouseEvents))
        XCTAssertEqual(closeCount, 0)

        controller.restoreTemporarilyHiddenPreviews()

        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 2)
        XCTAssertTrue(previewPanels.allSatisfy { $0.alphaValue == 1 })
        XCTAssertTrue(previewPanels.allSatisfy { !$0.ignoresMouseEvents })
        XCTAssertTrue(controller.closePreview(for: firstScreenshot, notify: false))
        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 1)
    }

    func testQuickAccessRestoreCanBeSuppressedDuringRecording() throws {
        _ = NSApplication.shared
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))

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

        let previewPanels = NSApp.windows.filter { !windowsBeforeShow.contains(ObjectIdentifier($0)) }
        XCTAssertEqual(previewPanels.count, 1)

        controller.setPreviewRestorationSuppressed(true)
        controller.restoreTemporarilyHiddenPreviews()

        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 0)
        XCTAssertTrue(previewPanels.allSatisfy { $0.alphaValue == 0 })
        XCTAssertTrue(previewPanels.allSatisfy(\.ignoresMouseEvents))

        controller.setPreviewRestorationSuppressed(false)
        controller.restoreTemporarilyHiddenPreviews()

        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 1)
        XCTAssertTrue(previewPanels.allSatisfy { $0.alphaValue == 1 })
        XCTAssertTrue(previewPanels.allSatisfy { !$0.ignoresMouseEvents })
    }

    func testQuickAccessTemporarilyHidesExistingPreviewsWhenRecordingStarts() throws {
        _ = NSApplication.shared
        let screenshot = CapturedScreenshot(
            pngData: try makePNGData(),
            image: NSImage(size: NSSize(width: 2, height: 2)),
            rect: CGRect(x: 0, y: 0, width: 2, height: 2)
        )
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        var closeCount = 0

        controller.show(
            for: screenshot,
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
        XCTAssertEqual(previewPanels.count, 1)

        controller.closePreviewsForRecordingStart()
        controller.restoreTemporarilyHiddenPreviews()

        XCTAssertEqual(previewPanels.filter(\.isVisible).count, 1)
        XCTAssertTrue(previewPanels.allSatisfy { $0.alphaValue == 1 })
        XCTAssertTrue(previewPanels.allSatisfy { !$0.ignoresMouseEvents })
        XCTAssertEqual(closeCount, 0)
    }

    func testQuickAccessClosesOrphanPreviewPanelsWhenRecordingStarts() {
        _ = NSApplication.shared
        let controller = QuickAccessPanelController()
        retainedPreviewControllers.append(controller)
        let orphanPanel = NSPanel(
            contentRect: CGRect(x: 40, y: 40, width: 200, height: 132),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        orphanPanel.title = QuickAccessPanelController.previewWindowTitle
        orphanPanel.isReleasedWhenClosed = false
        orphanPanel.orderFrontRegardless()
        defer {
            orphanPanel.close()
        }

        controller.closePreviewsForRecordingStart()

        XCTAssertFalse(orphanPanel.isVisible)
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

    private func findTextField(in view: NSView, accessibilityLabel: String) -> NSTextField? {
        if let textField = view as? NSTextField,
           textField.accessibilityLabel() == accessibilityLabel {
            return textField
        }

        for subview in view.subviews {
            if let textField = findTextField(in: subview, accessibilityLabel: accessibilityLabel) {
                return textField
            }
        }

        return nil
    }

    private func findProgressIndicator(in view: NSView, accessibilityLabel: String) -> NSProgressIndicator? {
        if let progressIndicator = view as? NSProgressIndicator,
           progressIndicator.accessibilityLabel() == accessibilityLabel {
            return progressIndicator
        }

        for subview in view.subviews {
            if let progressIndicator = findProgressIndicator(in: subview, accessibilityLabel: accessibilityLabel) {
                return progressIndicator
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
