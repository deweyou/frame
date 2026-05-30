import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class ImageWorkspacePanelControllerTests: XCTestCase {
    private var retainedControllers: [ImageWorkspacePanelController] = []

    func testTemporaryWorkspaceReusesExistingWindowForSameScreenshot() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        let screenshot = try makeScreenshot()

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let firstPanel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            firstPanel.close()
        }

        XCTAssertTrue(controller.show(
            screenshot: screenshot,
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let openedPanels = workspacePanels(excluding: windowsBeforeShow)
        XCTAssertEqual(openedPanels.count, 1)
        XCTAssertTrue(openedPanels.first === firstPanel)
        XCTAssertTrue(firstPanel.isVisible)
    }

    func testWorkspaceOutputButtonsCloseWindowAfterSuccess() throws {
        let copyPanel = try showWorkspace(copy: { true }, save: { false })
        let copyButton = try XCTUnwrap(findButton(in: try XCTUnwrap(copyPanel.contentView), accessibilityLabel: "Copy"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
        XCTAssertFalse(copyPanel.isVisible)

        let downloadPanel = try showWorkspace(copy: { false }, save: { true })
        let downloadButton = try XCTUnwrap(findButton(in: try XCTUnwrap(downloadPanel.contentView), accessibilityLabel: "Download"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(downloadButton.action), to: downloadButton.target, from: downloadButton))
        XCTAssertFalse(downloadPanel.isVisible)
    }

    func testPinnedWorkspaceIsImageOnlyWithoutToolbar() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            panel.close()
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertNil(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        for label in ["Mosaic", "Shape Box", "Brush", "Text", "Arrow", "Highlight", "Save", "Copy", "Download"] {
            XCTAssertNil(findButton(in: contentView, accessibilityLabel: label))
        }

        let imageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Pinned Image Container"))
        let closeFrame = try XCTUnwrap(panel.standardWindowButton(.closeButton))
            .convert(try XCTUnwrap(panel.standardWindowButton(.closeButton)).bounds, to: contentView)
        XCTAssertEqual(imageContainer.frame.minX, contentView.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minY, contentView.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.maxX, contentView.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.maxY, contentView.bounds.maxY, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(closeFrame.minX, imageContainer.frame.minX)
        XCTAssertLessThanOrEqual(closeFrame.maxY, imageContainer.frame.maxY)
        XCTAssertLessThan(closeFrame.midX, imageContainer.frame.minX + 80)
        XCTAssertGreaterThan(closeFrame.midY, imageContainer.frame.maxY - 40)
    }

    func testPinnedWorkspaceContextMenuOutputsAndEditsWithoutClosingPin() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        var copyCount = 0
        var saveCount = 0

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .pinned,
            copy: {
                copyCount += 1
                return true
            },
            save: {
                saveCount += 1
                return true
            }
        ))

        let pinPanel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            for panel in workspacePanels(excluding: windowsBeforeShow) {
                panel.close()
            }
        }

        let contentView = try XCTUnwrap(pinPanel.contentView)
        let menu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: pinPanel.windowNumber)))
        let copyMenuItem = try XCTUnwrap(menu.item(withTitle: "Copy"))
        let downloadMenuItem = try XCTUnwrap(menu.item(withTitle: "Download"))
        let editMenuItem = try XCTUnwrap(menu.item(withTitle: "Edit"))

        XCTAssertNil(menu.item(withTitle: "Save"))
        XCTAssertNil(menu.item(withTitle: "Mosaic"))

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyMenuItem.action), to: copyMenuItem.target, from: copyMenuItem))
        XCTAssertEqual(copyCount, 1)
        XCTAssertTrue(pinPanel.isVisible)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(downloadMenuItem.action), to: downloadMenuItem.target, from: downloadMenuItem))
        XCTAssertEqual(saveCount, 1)
        XCTAssertTrue(pinPanel.isVisible)

        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(editMenuItem.action), to: editMenuItem.target, from: editMenuItem))
        XCTAssertTrue(pinPanel.isVisible)
        XCTAssertEqual(workspacePanels(excluding: windowsBeforeShow).filter(\.isVisible).count, 2)

        let editPanel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first {
            $0 !== pinPanel && $0.isVisible
        })
        let editContentView = try XCTUnwrap(editPanel.contentView)
        XCTAssertNotNil(findView(in: editContentView, accessibilityLabel: "Image Workspace Toolbar"))
    }

    func testTemporaryWorkspaceStaysOpenOnFocusLossAndClosesOnEscape() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }

        panel.resignKey()
        XCTAssertTrue(panel.isVisible)

        panel.cancelOperation(nil)
        XCTAssertFalse(panel.isVisible)
    }

    func testWorkspaceUsesNativeCloseAndTopToolbarOutsideImage() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)
        var copyCount = 0
        var saveCount = 0

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: {
                copyCount += 1
                return true
            },
            save: {
                saveCount += 1
                return true
            }
        ))

        let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
        defer {
            panel.close()
        }

        XCTAssertTrue(panel.styleMask.contains(.titled))
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.styleMask.contains(.closable))
        XCTAssertTrue(panel.styleMask.contains(.miniaturizable))
        XCTAssertTrue(panel.hasShadow)
        let closeButton = try XCTUnwrap(panel.standardWindowButton(.closeButton))
        let miniaturizeButton = try XCTUnwrap(panel.standardWindowButton(.miniaturizeButton))
        let zoomButton = try XCTUnwrap(panel.standardWindowButton(.zoomButton))
        XCTAssertTrue(closeButton.isEnabled)
        XCTAssertTrue(miniaturizeButton.isEnabled)
        XCTAssertTrue(zoomButton.isEnabled)

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        XCTAssertNil(findButton(in: contentView, accessibilityLabel: "Close"))

        let toolbar = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        let imageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Preview Container"))
        let mosaicButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Mosaic"))
        let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy"))
        let saveButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Save"))
        let downloadButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Download"))
        let menu = try XCTUnwrap(contentView.menu(for: try makeRightClickEvent(windowNumber: panel.windowNumber)))
        let copyMenuItem = try XCTUnwrap(menu.item(withTitle: "Copy"))
        let saveMenuItem = try XCTUnwrap(menu.item(withTitle: "Save"))
        let downloadMenuItem = try XCTUnwrap(menu.item(withTitle: "Download"))
        let mosaicMenuItem = try XCTUnwrap(menu.item(withTitle: "Mosaic"))

        let mosaicFrame = mosaicButton.convert(mosaicButton.bounds, to: contentView)
        let copyFrame = copyButton.convert(copyButton.bounds, to: contentView)
        let saveFrame = saveButton.convert(saveButton.bounds, to: contentView)
        let downloadFrame = downloadButton.convert(downloadButton.bounds, to: contentView)
        let closeFrame = closeButton.convert(closeButton.bounds, to: contentView)
        let miniaturizeFrame = miniaturizeButton.convert(miniaturizeButton.bounds, to: contentView)
        let zoomFrame = zoomButton.convert(zoomButton.bounds, to: contentView)

        XCTAssertEqual(toolbar.alphaValue, 1, accuracy: 0.01)
        XCTAssertEqual(toolbar.layer?.cornerRadius ?? 0, toolbar.frame.height / 2, accuracy: 0.5)
        XCTAssertEqual(toolbar.layer?.borderWidth ?? 0, 0.5, accuracy: 0.01)
        XCTAssertLessThanOrEqual(toolbar.frame.minX, closeFrame.minX - 2)
        XCTAssertEqual(toolbar.frame.maxX, imageContainer.frame.maxX, accuracy: 0.5)
        XCTAssertEqual(toolbar.frame.minX, imageContainer.frame.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(mosaicFrame.minX, zoomFrame.maxX + 8)
        XCTAssertEqual(toolbar.frame.midY, closeFrame.midY, accuracy: 1.5)
        XCTAssertEqual(toolbar.frame.midY, miniaturizeFrame.midY, accuracy: 1.5)
        XCTAssertEqual(toolbar.frame.midY, zoomFrame.midY, accuracy: 1.5)
        assertCircularHoverLayer(in: mosaicButton)
        XCTAssertFalse(mosaicButton.isEnabled)
        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertTrue(copyButton.isEnabled)
        XCTAssertTrue(downloadButton.isEnabled)
        XCTAssertFalse(mosaicMenuItem.isEnabled)
        XCTAssertFalse(saveMenuItem.isEnabled)
        XCTAssertTrue(copyMenuItem.isEnabled)
        XCTAssertTrue(downloadMenuItem.isEnabled)
        XCTAssertEqual(toolbar.frame.minY - imageContainer.frame.maxY, 6, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minX, toolbar.frame.minX, accuracy: 0.5)
        XCTAssertEqual(imageContainer.frame.minY, contentView.bounds.minY, accuracy: 0.5)
        XCTAssertEqual(
            imageContainer.frame.width / imageContainer.frame.height,
            320.0 / 240.0,
            accuracy: 0.01
        )
        XCTAssertGreaterThan(saveFrame.minX, mosaicFrame.maxX)
        XCTAssertGreaterThan(copyFrame.minX, saveFrame.maxX)
        XCTAssertGreaterThan(downloadFrame.minX, copyFrame.maxX)

        panel.setFrame(NSRect(origin: panel.frame.origin, size: panel.minSize), display: false)
        contentView.layoutSubtreeIfNeeded()

        let minimumToolbar = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Workspace Toolbar"))
        let minimumImageContainer = try XCTUnwrap(findView(in: contentView, accessibilityLabel: "Image Preview Container"))
        let minimumDownloadButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Download"))
        let minimumDownloadFrame = minimumDownloadButton.convert(minimumDownloadButton.bounds, to: contentView)
        let minimumVerticalChromeHeight = minimumToolbar.frame.height + minimumToolbar.frame.minY - minimumImageContainer.frame.maxY
        XCTAssertLessThanOrEqual(minimumDownloadFrame.maxX, minimumToolbar.frame.maxX - 5)
        XCTAssertEqual(
            minimumImageContainer.frame.width / minimumImageContainer.frame.height,
            320.0 / 240.0,
            accuracy: 0.01
        )

        let proposedFrameSize = NSSize(width: panel.frame.width + 200, height: panel.frame.height)
        let constrainedFrameSize = try XCTUnwrap(panel.delegate?.windowWillResize?(panel, to: proposedFrameSize))
        let constrainedContentSize = panel.contentRect(forFrameRect: NSRect(origin: .zero, size: constrainedFrameSize)).size
        XCTAssertGreaterThan(constrainedFrameSize.height, proposedFrameSize.height)
        XCTAssertEqual(
            constrainedContentSize.width / (constrainedContentSize.height - minimumVerticalChromeHeight),
            320.0 / 240.0,
            accuracy: 0.01
        )

        XCTAssertEqual(copyCount, 0)
        XCTAssertEqual(saveCount, 0)
    }

    func testLiveCornerResizeKeepsInitialResizeAxisStableForPreviewAndPin() throws {
        try assertLiveCornerResizeKeepsInitialResizeAxisStable(kind: .temporaryPreview)
        try assertLiveCornerResizeKeepsInitialResizeAxisStable(kind: .pinned)
    }

    private func assertLiveCornerResizeKeepsInitialResizeAxisStable(kind: ImageWorkspaceKind) throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: kind,
            copy: { true },
            save: { true }
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
        defer {
            panel.close()
        }

        let contentView = try XCTUnwrap(panel.contentView)
        contentView.layoutSubtreeIfNeeded()

        panel.delegate?.windowWillStartLiveResize?(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))

        let initialContentSize = contentView.bounds.size
        let firstProposedContentSize = NSSize(
            width: initialContentSize.width + 12,
            height: initialContentSize.height + 80
        )
        let firstFrameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: firstProposedContentSize)).size
        let firstConstrainedFrameSize = try XCTUnwrap(panel.delegate?.windowWillResize?(panel, to: firstFrameSize))
        panel.setFrame(NSRect(origin: panel.frame.origin, size: firstConstrainedFrameSize), display: false)
        contentView.layoutSubtreeIfNeeded()

        let liveContentSize = contentView.bounds.size
        let secondProposedContentSize = NSSize(
            width: liveContentSize.width + 120,
            height: liveContentSize.height + 24
        )
        let secondFrameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: secondProposedContentSize)).size
        let secondConstrainedFrameSize = try XCTUnwrap(panel.delegate?.windowWillResize?(panel, to: secondFrameSize))
        let secondConstrainedContentSize = panel.contentRect(
            forFrameRect: NSRect(origin: .zero, size: secondConstrainedFrameSize)
        ).size

        XCTAssertEqual(secondConstrainedContentSize.height, secondProposedContentSize.height, accuracy: 0.5)
        panel.delegate?.windowDidEndLiveResize?(Notification(name: NSWindow.didEndLiveResizeNotification, object: panel))
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

    private func showWorkspace(copy: @escaping () -> Bool, save: @escaping () -> Bool) throws -> NSPanel {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = ImageWorkspacePanelController()
        retainedControllers.append(controller)

        XCTAssertTrue(controller.show(
            screenshot: try makeScreenshot(),
            kind: .temporaryPreview,
            copy: copy,
            save: save
        ))

        let panel = try XCTUnwrap(workspacePanels(excluding: windowsBeforeShow).first)
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

    private func findView(in view: NSView, accessibilityLabel: String) -> NSView? {
        if view.accessibilityLabel() == accessibilityLabel {
            return view
        }

        for subview in view.subviews {
            if let matchingView = findView(in: subview, accessibilityLabel: accessibilityLabel) {
                return matchingView
            }
        }

        return nil
    }

    private func workspacePanels(excluding windowIDs: Set<ObjectIdentifier>) -> [NSPanel] {
        NSApp.windows.compactMap { window in
            guard !windowIDs.contains(ObjectIdentifier(window)) else {
                return nil
            }

            return window as? NSPanel
        }
    }

    private func assertCircularHoverLayer(in button: NSButton) {
        button.layoutSubtreeIfNeeded()
        let hoverLayer = button.layer?.sublayers?.first
        XCTAssertNotNil(hoverLayer)
        XCTAssertEqual(hoverLayer?.bounds.width ?? 0, hoverLayer?.bounds.height ?? 1, accuracy: 0.5)
        XCTAssertEqual(hoverLayer?.cornerRadius ?? 0, (hoverLayer?.bounds.height ?? 0) / 2, accuracy: 0.5)
        XCTAssertEqual(hoverLayer?.opacity ?? 1, 0, accuracy: 0.01)
    }

    private func makeRightClickEvent(windowNumber: Int) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
