import AppKit
import FrameCore

@MainActor
final class ImageWorkspacePanelController: NSObject {
    private var workspaceItems: [ImageWorkspaceItem] = []

    func show(
        screenshot: CapturedScreenshot,
        kind: ImageWorkspaceKind,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)? = nil,
        copyRecognizedText: ((String) -> Bool)? = nil
    ) -> Bool {
        if kind == .temporaryPreview,
           let existingItem = workspaceItem(for: screenshot, kind: kind) {
            activateWorkspace(existingItem)
            return true
        }

        let panel = makePanel(for: screenshot, kind: kind)
        let item = ImageWorkspaceItem(
            state: ImageWorkspaceState(kind: kind),
            panel: panel,
            screenshot: screenshot,
            copy: copy,
            save: save,
            recognizeText: recognizeText,
            copyRecognizedText: copyRecognizedText
        )

        panel.contentView = makeContentView(for: item)
        workspaceItems.append(item)
        installLifecycleCallbacks(for: item)
        startAutomaticOCRIfNeeded(for: item)

        activateWorkspace(item)
        return true
    }

    private func activateWorkspace(_ item: ImageWorkspaceItem) {
        NSApp.activate(ignoringOtherApps: true)
        item.panel.makeKeyAndOrderFront(nil)
        item.panel.orderFrontRegardless()
    }

    private func makePanel(for screenshot: CapturedScreenshot, kind: ImageWorkspaceKind) -> ImageWorkspacePanel {
        let targetScreen = NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let contentSize = initialContentSize(for: screenshot.image, in: visibleFrame, kind: kind)
        let imageAspectRatio = ImageWorkspaceLayout.imageAspectRatio(for: screenshot.image)
        let contentRect = NSRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )

        // Use an activating panel so preview workspaces can become key for Escape handling.
        let panel = ImageWorkspacePanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.configureAspectLockedResize(
            imageAspectRatio: imageAspectRatio,
            metrics: ImageWorkspaceLayout.resizeMetrics(for: kind)
        )
        panel.onEscape = { [weak self, weak panel] in
            guard let panel,
                  let item = self?.workspaceItem(for: panel),
                  item.state.closePolicy == .escapeOrExplicitClose else {
                return
            }

            self?.closeWorkspace(item)
        }

        return panel
    }

    private func initialContentSize(
        for image: NSImage,
        in visibleFrame: NSRect,
        kind: ImageWorkspaceKind
    ) -> CGSize {
        let aspectRatio = ImageWorkspaceLayout.imageAspectRatio(for: image)
        let resizeMetrics = ImageWorkspaceLayout.resizeMetrics(for: kind)
        let maximumContentSize = CGSize(
            width: max(440, min(980, visibleFrame.width * 0.72)),
            height: max(260, min(640, visibleFrame.height * 0.68))
        )
        let maximumImageSize = CGSize(
            width: maximumContentSize.width - resizeMetrics.horizontalChromeWidth,
            height: maximumContentSize.height - resizeMetrics.fixedVerticalChromeHeight
        )
        let sourceWidth = max(ImageWorkspaceLayout.fallbackImageSize.width, image.size.width)
        let fittedImageWidth = min(maximumImageSize.width, maximumImageSize.height * aspectRatio, sourceWidth)
        let minimumImageWidth = max(1, resizeMetrics.minimumContentWidth - resizeMetrics.horizontalChromeWidth)
        let imageWidth = max(minimumImageWidth, fittedImageWidth)
        let fittedImageSize = CGSize(width: imageWidth, height: imageWidth / aspectRatio)

        return CGSize(
            width: fittedImageSize.width + resizeMetrics.horizontalChromeWidth,
            height: fittedImageSize.height + resizeMetrics.fixedVerticalChromeHeight
        )
    }

    private func makeContentView(for item: ImageWorkspaceItem) -> NSView {
        switch item.state.kind {
        case .temporaryPreview:
            makePreviewContentView(for: item)
        case .pinned:
            makePinnedContentView(for: item)
        }
    }

    private func makePreviewContentView(for item: ImageWorkspaceItem) -> NSView {
        let contextMenuProvider: () -> NSMenu = { [weak self, weak item] in
            guard let self,
                  let item else {
                return NSMenu()
            }

            return self.makeContextMenu(for: item)
        }

        let contentView = ImageWorkspaceContextMenuView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.menuProvider = contextMenuProvider

        let imageContainer = ImageWorkspaceContextMenuView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 10
        imageContainer.layer?.cornerCurve = .continuous
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        imageContainer.menuProvider = contextMenuProvider
        imageContainer.setAccessibilityLabel("Image Preview Container")

        let imageView = ImageWorkspaceImageView(image: item.screenshot.image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.menuProvider = contextMenuProvider

        let textSelectionOverlay = ImageWorkspaceTextSelectionOverlayView(
            imageSize: item.screenshot.image.size,
            copyText: item.copyRecognizedText ?? { _ in false }
        )
        textSelectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        textSelectionOverlay.isHidden = true
        textSelectionOverlay.menuProvider = contextMenuProvider
        item.textSelectionOverlay = textSelectionOverlay

        let toolbar = ImageWorkspaceToolbarView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.setAccessibilityLabel("Image Workspace Toolbar")

        let toolbarStack = NSStackView()
        toolbarStack.orientation = .horizontal
        toolbarStack.alignment = .centerY
        toolbarStack.distribution = .fill
        toolbarStack.spacing = ImageWorkspaceLayout.toolbarStackSpacing
        toolbarStack.translatesAutoresizingMaskIntoConstraints = false

        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.alignment = .centerY
        toolStack.distribution = .fillEqually
        toolStack.spacing = ImageWorkspaceLayout.editingToolSpacing
        toolStack.translatesAutoresizingMaskIntoConstraints = false

        for tool in ImageEditingTool.allCases {
            let button = makeIconButton(
                title: title(for: tool),
                symbolName: symbolName(for: tool),
                action: #selector(toolButtonClicked),
                buttonType: .toggle
            )
            button.tag = tag(for: tool)
            button.isEnabled = false
            button.contentTintColor = .disabledControlTextColor
            button.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
            toolStack.addArrangedSubview(button)
            item.toolButtons.append((tool: tool, button: button))
        }

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let saveEditedButton = makeIconButton(
            title: "Save",
            symbolName: "checkmark.circle",
            action: #selector(saveEditedButtonClicked),
            buttonType: .momentaryPushIn
        )
        let copyButton = makeIconButton(
            title: "Copy",
            symbolName: "doc.on.doc",
            action: #selector(copyButtonClicked),
            buttonType: .momentaryPushIn
        )
        let downloadButton = makeIconButton(
            title: "Download",
            symbolName: "square.and.arrow.down",
            action: #selector(downloadButtonClicked),
            buttonType: .momentaryPushIn
        )
        saveEditedButton.isEnabled = false
        saveEditedButton.contentTintColor = .disabledControlTextColor
        saveEditedButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.outputButtonWidth).isActive = true
        saveEditedButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
        copyButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.outputButtonWidth).isActive = true
        copyButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
        downloadButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.outputButtonWidth).isActive = true
        downloadButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true

        contentView.addSubview(imageContainer)
        contentView.addSubview(toolbar)
        imageContainer.addSubview(imageView)
        imageContainer.addSubview(textSelectionOverlay)
        toolbar.addSubview(toolbarStack)
        toolbarStack.addArrangedSubview(toolStack)
        toolbarStack.addArrangedSubview(spacer)
        toolbarStack.addArrangedSubview(saveEditedButton)
        toolbarStack.addArrangedSubview(copyButton)
        toolbarStack.addArrangedSubview(downloadButton)

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ImageWorkspaceLayout.toolbarLeading),
            imageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ImageWorkspaceLayout.toolbarTrailing),
            imageContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: ImageWorkspaceLayout.imageTopSpacing),
            imageContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -ImageWorkspaceLayout.imageBottomInset),

            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            textSelectionOverlay.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            textSelectionOverlay.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            textSelectionOverlay.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            textSelectionOverlay.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ImageWorkspaceLayout.toolbarLeading),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ImageWorkspaceLayout.toolbarTrailing),
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: ImageWorkspaceLayout.toolbarTopInset),
            toolbar.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.toolbarHeight),

            toolbarStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: ImageWorkspaceLayout.toolbarStackLeadingInset),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -ImageWorkspaceLayout.toolbarStackTrailingInset),
            toolbarStack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 2),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -2),

            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: ImageWorkspaceLayout.minimumSpacerWidth),
        ])

        return contentView
    }

    private func makePinnedContentView(for item: ImageWorkspaceItem) -> NSView {
        let contextMenuProvider: () -> NSMenu = { [weak self, weak item] in
            guard let self,
                  let item else {
                return NSMenu()
            }

            return self.makePinnedContextMenu(for: item)
        }

        let contentView = ImageWorkspaceContextMenuView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        contentView.menuProvider = contextMenuProvider

        let imageContainer = ImageWorkspaceContextMenuView()
        imageContainer.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.wantsLayer = true
        imageContainer.layer?.cornerRadius = 10
        imageContainer.layer?.cornerCurve = .continuous
        imageContainer.layer?.masksToBounds = true
        imageContainer.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
        imageContainer.menuProvider = contextMenuProvider
        imageContainer.setAccessibilityLabel("Pinned Image Container")

        let imageView = ImageWorkspaceImageView(image: item.screenshot.image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.menuProvider = contextMenuProvider

        contentView.addSubview(imageContainer)
        imageContainer.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),
        ])

        return contentView
    }

    private func makeIconButton(
        title: String,
        symbolName: String,
        action: Selector,
        buttonType: NSButton.ButtonType
    ) -> NSButton {
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: title)
            ?? NSImage()
        let button = ImageWorkspaceToolbarButton(image: image, target: self, action: action)
        button.toolTip = title
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.contentTintColor = .labelColor
        button.setButtonType(buttonType)
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        return button
    }

    private func installLifecycleCallbacks(for item: ImageWorkspaceItem) {
        item.panel.onClose = { [weak self, weak item] in
            guard let item else {
                return
            }

            self?.removeWorkspace(item)
        }
    }

    private func startAutomaticOCRIfNeeded(for item: ImageWorkspaceItem) {
        guard item.state.kind == .temporaryPreview,
              let recognizeText = item.recognizeText,
              let textSelectionOverlay = item.textSelectionOverlay else {
            return
        }

        item.ocrTask = Task { @MainActor [weak self, weak item, weak textSelectionOverlay] in
            guard let self,
                  let item,
                  let textSelectionOverlay else {
                return
            }

            do {
                let layout = try await recognizeText(item.screenshot)
                guard self.workspaceItems.contains(where: { $0 === item }) else {
                    return
                }

                textSelectionOverlay.setRecognizedTextLayout(layout)
            } catch {
                guard self.workspaceItems.contains(where: { $0 === item }) else {
                    return
                }

                textSelectionOverlay.isHidden = true
                NSLog("Frame 预览编辑自动 OCR 失败: \(error.localizedDescription)")
            }
        }
    }

    private func makeContextMenu(for item: ImageWorkspaceItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Copy", action: #selector(copyMenuItemClicked), representedObject: item))
        menu.addItem(makeMenuItem(title: "Download", action: #selector(downloadMenuItemClicked), representedObject: item))
        let saveEditedMenuItem = makeMenuItem(
            title: "Save",
            action: #selector(saveEditedMenuItemClicked),
            representedObject: item
        )
        saveEditedMenuItem.isEnabled = false
        menu.addItem(saveEditedMenuItem)
        menu.addItem(.separator())

        for tool in ImageEditingTool.allCases {
            let selection = ImageWorkspaceToolMenuSelection(item: item, tool: tool)
            let menuItem = makeMenuItem(
                title: title(for: tool),
                action: #selector(toolMenuItemClicked),
                representedObject: selection
            )
            menuItem.state = item.state.selectedTool == tool ? .on : .off
            menuItem.isEnabled = false
            menu.addItem(menuItem)
        }

        return menu
    }

    private func makePinnedContextMenu(for item: ImageWorkspaceItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: "Copy", action: #selector(copyMenuItemClicked), representedObject: item))
        menu.addItem(makeMenuItem(title: "Download", action: #selector(downloadMenuItemClicked), representedObject: item))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: "Edit", action: #selector(editMenuItemClicked), representedObject: item))
        return menu
    }

    private func makeMenuItem(title: String, action: Selector, representedObject: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    @objc private func copyButtonClicked(_ sender: NSButton) {
        guard let item = workspaceItem(for: sender.window) else {
            return
        }

        copyOutput(for: item)
    }

    @objc private func downloadButtonClicked(_ sender: NSButton) {
        guard let item = workspaceItem(for: sender.window) else {
            return
        }

        downloadOutput(for: item)
    }

    @objc private func saveEditedButtonClicked(_ sender: NSButton) {
        guard sender.isEnabled else {
            return
        }
    }

    @objc private func toolButtonClicked(_ sender: NSButton) {
        guard sender.isEnabled else {
            return
        }

        guard let item = workspaceItem(for: sender.window),
              let tool = tool(for: sender.tag) else {
            return
        }

        select(tool, in: item)
    }

    @objc private func copyMenuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ImageWorkspaceItem else {
            return
        }

        copyOutput(for: item)
    }

    @objc private func downloadMenuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ImageWorkspaceItem else {
            return
        }

        downloadOutput(for: item)
    }

    @objc private func editMenuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ImageWorkspaceItem,
              item.state.kind == .pinned else {
            return
        }

        _ = show(
            screenshot: item.screenshot,
            kind: .temporaryPreview,
            copy: item.copy,
            save: item.save
        )
    }

    @objc private func saveEditedMenuItemClicked(_ sender: NSMenuItem) {
        guard sender.isEnabled else {
            return
        }
    }

    @objc private func toolMenuItemClicked(_ sender: NSMenuItem) {
        guard sender.isEnabled else {
            return
        }

        guard let selection = sender.representedObject as? ImageWorkspaceToolMenuSelection else {
            return
        }

        select(selection.tool, in: selection.item)
    }

    private func select(_ tool: ImageEditingTool, in item: ImageWorkspaceItem) {
        item.state.select(tool)
        for toolButton in item.toolButtons {
            let isSelected = toolButton.tool == tool
            toolButton.button.state = isSelected ? .on : .off
            toolButton.button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
            if let toolbarButton = toolButton.button as? ImageWorkspaceToolbarButton {
                toolbarButton.isWorkspaceSelected = isSelected
            }
        }
    }

    private func copyOutput(for item: ImageWorkspaceItem) {
        guard item.copy() else {
            return
        }

        if item.state.kind == .temporaryPreview {
            closeWorkspace(item)
        }
    }

    private func downloadOutput(for item: ImageWorkspaceItem) {
        guard item.save() else {
            return
        }

        if item.state.kind == .temporaryPreview {
            closeWorkspace(item)
        }
    }

    private func closeWorkspace(_ item: ImageWorkspaceItem) {
        item.panel.close()
    }

    private func removeWorkspace(_ item: ImageWorkspaceItem) {
        item.ocrTask?.cancel()
        for observer in item.notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        item.notificationObservers.removeAll()
        item.panel.onClose = nil
        item.panel.onEscape = nil
        workspaceItems.removeAll { $0 === item }
    }

    private func workspaceItem(for window: NSWindow?) -> ImageWorkspaceItem? {
        guard let window else {
            return nil
        }

        return workspaceItems.first { $0.panel === window }
    }

    private func workspaceItem(for screenshot: CapturedScreenshot, kind: ImageWorkspaceKind) -> ImageWorkspaceItem? {
        workspaceItems.first {
            $0.state.kind == kind
                && $0.screenshot.id == screenshot.id
                && $0.panel.isVisible
        }
    }

    private func title(for tool: ImageEditingTool) -> String {
        switch tool {
        case .mosaic:
            "Mosaic"
        case .shapeBox:
            "Shape Box"
        case .brush:
            "Brush"
        case .text:
            "Text"
        case .arrow:
            "Arrow"
        case .highlight:
            "Highlight"
        }
    }

    private func symbolName(for tool: ImageEditingTool) -> String {
        switch tool {
        case .mosaic:
            "square.grid.3x3.fill"
        case .shapeBox:
            "rectangle"
        case .brush:
            "paintbrush"
        case .text:
            "textformat"
        case .arrow:
            "arrow.up.right"
        case .highlight:
            "highlighter"
        }
    }

    private func tag(for tool: ImageEditingTool) -> Int {
        switch tool {
        case .mosaic:
            1
        case .shapeBox:
            2
        case .brush:
            3
        case .text:
            4
        case .arrow:
            5
        case .highlight:
            6
        }
    }

    private func tool(for tag: Int) -> ImageEditingTool? {
        switch tag {
        case 1:
            .mosaic
        case 2:
            .shapeBox
        case 3:
            .brush
        case 4:
            .text
        case 5:
            .arrow
        case 6:
            .highlight
        default:
            nil
        }
    }
}

private final class ImageWorkspaceItem {
    var state: ImageWorkspaceState
    let panel: ImageWorkspacePanel
    let screenshot: CapturedScreenshot
    let copy: () -> Bool
    let save: () -> Bool
    let recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)?
    let copyRecognizedText: ((String) -> Bool)?
    var notificationObservers: [NSObjectProtocol] = []
    var toolButtons: [(tool: ImageEditingTool, button: NSButton)] = []
    weak var textSelectionOverlay: ImageWorkspaceTextSelectionOverlayView?
    var ocrTask: Task<Void, Never>?

    init(
        state: ImageWorkspaceState,
        panel: ImageWorkspacePanel,
        screenshot: CapturedScreenshot,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)?,
        copyRecognizedText: ((String) -> Bool)?
    ) {
        self.state = state
        self.panel = panel
        self.screenshot = screenshot
        self.copy = copy
        self.save = save
        self.recognizeText = recognizeText
        self.copyRecognizedText = copyRecognizedText
    }
}

private final class ImageWorkspaceToolMenuSelection: NSObject {
    let item: ImageWorkspaceItem
    let tool: ImageEditingTool

    init(item: ImageWorkspaceItem, tool: ImageEditingTool) {
        self.item = item
        self.tool = tool
    }
}

private enum ImageWorkspaceLayout {
    static let fallbackImageSize = CGSize(width: 640, height: 420)
    static let toolbarLeading: CGFloat = 0
    static let toolbarTrailing: CGFloat = 0
    static let toolbarTopInset: CGFloat = 0
    static let toolbarStackLeadingInset: CGFloat = 88
    static let toolbarStackTrailingInset: CGFloat = 6
    static let toolbarStackSpacing: CGFloat = 8
    static let toolbarHeight: CGFloat = 32
    static let imageTopSpacing: CGFloat = 6
    static let imageBottomInset: CGFloat = 0
    static let editingToolSize: CGFloat = 24
    static let editingToolSpacing: CGFloat = 4
    static let outputButtonWidth: CGFloat = 26
    static let minimumSpacerWidth: CGFloat = 12
    static let baseMinimumContentWidth: CGFloat = 440
    static let pinnedMinimumContentWidth: CGFloat = 320

    static var minimumContentWidth: CGFloat {
        max(baseMinimumContentWidth, toolbarLeading + minimumToolbarWidth + toolbarTrailing)
    }

    static func imageAspectRatio(for image: NSImage) -> CGFloat {
        let imageSize = image.size.width > 0 && image.size.height > 0 ? image.size : fallbackImageSize
        return max(0.05, imageSize.width / imageSize.height)
    }

    static func resizeMetrics(for kind: ImageWorkspaceKind) -> ImageWorkspaceResizeMetrics {
        switch kind {
        case .temporaryPreview:
            ImageWorkspaceResizeMetrics(
                fixedVerticalChromeHeight: toolbarTopInset + toolbarHeight + imageTopSpacing + imageBottomInset,
                horizontalChromeWidth: toolbarLeading + toolbarTrailing,
                minimumContentWidth: minimumContentWidth
            )
        case .pinned:
            ImageWorkspaceResizeMetrics(
                fixedVerticalChromeHeight: 0,
                horizontalChromeWidth: 0,
                minimumContentWidth: pinnedMinimumContentWidth
            )
        }
    }

    private static var minimumToolbarWidth: CGFloat {
        let toolCount = CGFloat(ImageEditingTool.allCases.count)
        let editingToolsWidth = editingToolSize * toolCount + editingToolSpacing * max(0, toolCount - 1)
        let arrangedSubviewSpacing = toolbarStackSpacing * 3
        return toolbarStackLeadingInset
            + toolbarStackTrailingInset
            + editingToolsWidth
            + arrangedSubviewSpacing
            + minimumSpacerWidth
            + outputButtonWidth * 3
    }
}

private struct ImageWorkspaceResizeMetrics {
    let fixedVerticalChromeHeight: CGFloat
    let horizontalChromeWidth: CGFloat
    let minimumContentWidth: CGFloat

    func minimumContentSize(for imageAspectRatio: CGFloat) -> NSSize {
        NSSize(
            width: minimumContentWidth,
            height: fixedVerticalChromeHeight + minimumContentWidth / imageAspectRatio
        )
    }
}

private enum ImageWorkspaceResizeAxis {
    case width
    case height
}

@MainActor
private final class ImageWorkspacePanel: NSPanel, NSWindowDelegate {
    var onEscape: (() -> Void)?
    var onClose: (() -> Void)?
    private var imageAspectRatio: CGFloat?
    private var isLiveAspectResize = false
    private var liveResizeAxis: ImageWorkspaceResizeAxis?
    private var resizeMetrics = ImageWorkspaceResizeMetrics(
        fixedVerticalChromeHeight: 0,
        horizontalChromeWidth: 0,
        minimumContentWidth: ImageWorkspaceLayout.pinnedMinimumContentWidth
    )

    func configureAspectLockedResize(
        imageAspectRatio: CGFloat,
        metrics: ImageWorkspaceResizeMetrics
    ) {
        self.imageAspectRatio = imageAspectRatio
        resizeMetrics = metrics
        minSize = frameSize(forContentSize: metrics.minimumContentSize(for: imageAspectRatio))
        delegate = self
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func close() {
        let closeHandler = onClose
        onClose = nil
        closeHandler?()
        super.close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        constrainedFrameSize(for: frameSize)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === self else {
            return
        }

        isLiveAspectResize = true
        liveResizeAxis = nil
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard notification.object as? NSWindow === self else {
            return
        }

        isLiveAspectResize = false
        liveResizeAxis = nil
    }

    private func constrainedFrameSize(for proposedFrameSize: NSSize) -> NSSize {
        guard let imageAspectRatio else {
            return proposedFrameSize
        }

        let proposedContentSize = contentSize(forFrameSize: proposedFrameSize)
        let currentContentSize = contentView?.bounds.size ?? proposedContentSize
        let proposedImageWidth = max(1, proposedContentSize.width - resizeMetrics.horizontalChromeWidth)
        let proposedImageHeight = max(1, proposedContentSize.height - resizeMetrics.fixedVerticalChromeHeight)
        let widthDelta = abs(proposedContentSize.width - currentContentSize.width)
        let heightDelta = abs(proposedContentSize.height - currentContentSize.height)
        let minimumContentSize = resizeMetrics.minimumContentSize(for: imageAspectRatio)
        let resizeAxis = resizeAxis(widthDelta: widthDelta, heightDelta: heightDelta)
        let contentSize: NSSize

        switch resizeAxis {
        case .width:
            let imageWidth = max(
                minimumContentSize.width - resizeMetrics.horizontalChromeWidth,
                proposedImageWidth
            )
            contentSize = NSSize(
                width: imageWidth + resizeMetrics.horizontalChromeWidth,
                height: imageWidth / imageAspectRatio + resizeMetrics.fixedVerticalChromeHeight
            )
        case .height:
            var imageHeight = max(
                minimumContentSize.height - resizeMetrics.fixedVerticalChromeHeight,
                proposedImageHeight
            )
            var imageWidth = imageHeight * imageAspectRatio
            if imageWidth + resizeMetrics.horizontalChromeWidth < minimumContentSize.width {
                imageWidth = minimumContentSize.width - resizeMetrics.horizontalChromeWidth
                imageHeight = imageWidth / imageAspectRatio
            }
            contentSize = NSSize(
                width: imageWidth + resizeMetrics.horizontalChromeWidth,
                height: imageHeight + resizeMetrics.fixedVerticalChromeHeight
            )
        }

        return frameSize(forContentSize: contentSize)
    }

    private func resizeAxis(widthDelta: CGFloat, heightDelta: CGFloat) -> ImageWorkspaceResizeAxis {
        if isLiveAspectResize, let liveResizeAxis {
            return liveResizeAxis
        }

        let resizeAxis: ImageWorkspaceResizeAxis = widthDelta >= heightDelta ? .width : .height
        if isLiveAspectResize {
            liveResizeAxis = resizeAxis
        }

        return resizeAxis
    }

    private func contentSize(forFrameSize frameSize: NSSize) -> NSSize {
        contentRect(forFrameRect: NSRect(origin: .zero, size: frameSize)).size
    }

    private func frameSize(forContentSize contentSize: NSSize) -> NSSize {
        frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
    }
}

private class ImageWorkspaceContextMenuView: NSView {
    var menuProvider: (() -> NSMenu)?

    override var mouseDownCanMoveWindow: Bool {
        true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}

private final class ImageWorkspaceToolbarView: NSVisualEffectView {
    private let toolbarHeight = ImageWorkspaceLayout.toolbarHeight

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        alphaValue = 1
        wantsLayer = true
        layer?.cornerRadius = toolbarHeight / 2
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class ImageWorkspaceToolbarButton: NSButton {
    private let hoverLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            updateHoverAppearance()
        }
    }
    var isWorkspaceSelected = false {
        didSet {
            updateHoverAppearance()
        }
    }
    override var isEnabled: Bool {
        didSet {
            if !isEnabled {
                isHovering = false
            }
            updateHoverAppearance()
            window?.invalidateCursorRects(for: self)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    init(image: NSImage, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.image = image
        self.target = target
        self.action = action
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()

        let hoverDiameter = min(bounds.width, bounds.height, 22)
        hoverLayer.cornerRadius = hoverDiameter / 2
        hoverLayer.bounds = CGRect(x: 0, y: 0, width: hoverDiameter, height: hoverDiameter)
        hoverLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isEnabled {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        guard isEnabled else {
            super.mouseEntered(with: event)
            return
        }

        NSCursor.pointingHand.set()
        isHovering = true
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        guard isEnabled else {
            super.mouseMoved(with: event)
            return
        }

        NSCursor.pointingHand.set()
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        super.mouseExited(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return
        }

        animateHoverLayer(opacity: 0.18)
        super.mouseDown(with: event)
        updateHoverAppearance()
    }

    private func configure() {
        title = ""
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        hoverLayer.opacity = 0
        hoverLayer.backgroundColor = NSColor.labelColor.withAlphaComponent(0.10).cgColor
        layer?.insertSublayer(hoverLayer, at: 0)
    }

    private func updateHoverAppearance() {
        guard isEnabled else {
            animateHoverLayer(opacity: 0)
            return
        }

        hoverLayer.backgroundColor = hoverBackgroundColor.cgColor
        animateHoverLayer(opacity: isHovering || isWorkspaceSelected ? 1 : 0)
    }

    private var hoverBackgroundColor: NSColor {
        if isWorkspaceSelected {
            return NSColor.controlAccentColor.withAlphaComponent(0.18)
        }

        return NSColor.labelColor.withAlphaComponent(0.10)
    }

    private func animateHoverLayer(opacity: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = hoverLayer.presentation()?.opacity ?? hoverLayer.opacity
        animation.toValue = opacity
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        hoverLayer.opacity = opacity
        hoverLayer.add(animation, forKey: "opacity")
    }
}

private final class ImageWorkspaceImageView: ImageWorkspaceContextMenuView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = CGRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}
