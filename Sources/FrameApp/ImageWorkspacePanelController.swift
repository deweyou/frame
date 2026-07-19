import AppKit
import FrameCore

@MainActor
final class ImageWorkspacePanelController: NSObject {
    private var workspaceItems: [ImageWorkspaceItem] = []
    private let editingOptionsProvider: () -> ImageAnnotationEditingOptions
    private let persistEditingOptions: (ImageAnnotationEditingOptions) -> Void
    private let saveCurrentBehaviorProvider: () -> ImageWorkspaceSaveCurrentBehavior
    private let presentSaveCurrentMenu: (NSMenu, NSButton) -> Void

    init(
        editingOptionsProvider: @escaping () -> ImageAnnotationEditingOptions = {
            SettingsStore.imageAnnotationEditingOptions()
        },
        persistEditingOptions: @escaping (ImageAnnotationEditingOptions) -> Void = {
            SettingsStore.setImageAnnotationEditingOptions($0)
        },
        saveCurrentBehaviorProvider: @escaping () -> ImageWorkspaceSaveCurrentBehavior = {
            SettingsStore.imageWorkspaceSaveCurrentBehavior()
        },
        presentSaveCurrentMenu: @escaping (NSMenu, NSButton) -> Void = { menu, sender in
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4),
                in: sender
            )
        }
    ) {
        self.editingOptionsProvider = editingOptionsProvider
        self.persistEditingOptions = persistEditingOptions
        self.saveCurrentBehaviorProvider = saveCurrentBehaviorProvider
        self.presentSaveCurrentMenu = presentSaveCurrentMenu
        super.init()
    }

    func show(
        screenshot: CapturedScreenshot,
        kind: ImageWorkspaceKind,
        strings: AppStrings = AppStrings(language: .en),
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)? = nil,
        copyRecognizedText: ((String) -> Bool)? = nil,
        replaceCurrent: ((CapturedScreenshot) -> Void)? = nil,
        saveAsNew: ((CapturedScreenshot) -> Bool)? = nil,
        closeSaveChoice: (() -> ImageWorkspaceCloseSaveChoice)? = nil
    ) -> Bool {
        show(
            screenshot: screenshot,
            kind: kind,
            strings: strings,
            copy: { _ in copy() },
            save: { _ in save() },
            recognizeText: recognizeText,
            copyRecognizedText: copyRecognizedText,
            replaceCurrent: replaceCurrent,
            saveAsNew: saveAsNew,
            closeSaveChoice: closeSaveChoice
        )
    }

    func show(
        screenshot: CapturedScreenshot,
        kind: ImageWorkspaceKind,
        strings: AppStrings = AppStrings(language: .en),
        copy: @escaping (CapturedScreenshot) -> Bool,
        save: @escaping (CapturedScreenshot) -> Bool,
        recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)? = nil,
        copyRecognizedText: ((String) -> Bool)? = nil,
        replaceCurrent: ((CapturedScreenshot) -> Void)? = nil,
        saveAsNew: ((CapturedScreenshot) -> Bool)? = nil,
        closeSaveChoice: (() -> ImageWorkspaceCloseSaveChoice)? = nil
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
            strings: strings,
            copy: copy,
            save: save,
            recognizeText: recognizeText,
            copyRecognizedText: copyRecognizedText,
            replaceCurrent: replaceCurrent,
            saveAsNew: saveAsNew,
            closeSaveChoice: closeSaveChoice
        )

        panel.contentView = makeContentView(for: item)
        panel.contentView?.layoutSubtreeIfNeeded()
        if panel.usesScrollableImageViewport,
           let annotationCanvas = item.annotationCanvas,
           let imageZoom = item.imageZoom {
            imageZoom.fitWidth(imageSize: screenshot.image.size, bounds: annotationCanvas.bounds)
        }
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
        let initialLayout = initialLayout(for: screenshot.image, in: visibleFrame, kind: kind)
        let contentSize = initialLayout.contentSize
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
        panel.animationBehavior = .none
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.configureResize(
            imageAspectRatio: initialLayout.usesScrollableViewport ? nil : imageAspectRatio,
            metrics: ImageWorkspaceLayout.resizeMetrics(for: kind)
        )
        panel.usesScrollableImageViewport = initialLayout.usesScrollableViewport
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

    private func initialLayout(
        for image: NSImage,
        in visibleFrame: NSRect,
        kind: ImageWorkspaceKind
    ) -> ImageWorkspaceInitialLayout {
        let aspectRatio = ImageWorkspaceLayout.imageAspectRatio(for: image)
        let resizeMetrics = ImageWorkspaceLayout.resizeMetrics(for: kind)
        let maximumContentSize = CGSize(
            width: max(440, visibleFrame.width - ImageWorkspaceLayout.initialWindowScreenMargin),
            height: max(260, visibleFrame.height - ImageWorkspaceLayout.initialWindowScreenMargin)
        )
        let maximumImageSize = CGSize(
            width: maximumContentSize.width - resizeMetrics.horizontalChromeWidth,
            height: maximumContentSize.height - resizeMetrics.fixedVerticalChromeHeight
        )
        let sourceWidth = image.size.width > 0 ? image.size.width : ImageWorkspaceLayout.fallbackImageSize.width
        let fittedImageWidth = min(maximumImageSize.width, maximumImageSize.height * aspectRatio, sourceWidth)
        let minimumImageWidth = max(1, resizeMetrics.minimumContentWidth - resizeMetrics.horizontalChromeWidth)
        let imageWidth = max(minimumImageWidth, fittedImageWidth)
        let fittedImageSize = CGSize(width: imageWidth, height: imageWidth / aspectRatio)

        let aspectLockedContentSize = CGSize(
            width: fittedImageSize.width + resizeMetrics.horizontalChromeWidth,
            height: fittedImageSize.height + resizeMetrics.fixedVerticalChromeHeight
        )
        let usesScrollableViewport = kind == .temporaryPreview
            && aspectLockedContentSize.height > maximumContentSize.height

        return ImageWorkspaceInitialLayout(
            contentSize: usesScrollableViewport
                ? CGSize(
                    width: min(aspectLockedContentSize.width, maximumContentSize.width),
                    height: maximumContentSize.height
                )
                : aspectLockedContentSize,
            usesScrollableViewport: usesScrollableViewport
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
        imageContainer.layer?.backgroundColor = NSColor.black.cgColor
        imageContainer.menuProvider = contextMenuProvider
        imageContainer.setAccessibilityLabel("Image Preview Container")

        let imageZoom = ImageWorkspaceImageZoom()
        item.imageZoom = imageZoom
        let annotationCanvas = ImageAnnotationCanvasView(
            image: item.screenshot.image,
            document: ImageAnnotationDocument(editingOptions: editingOptionsProvider()),
            imageZoom: imageZoom
        ) { [weak self, weak item] document in
            guard let item else {
                return
            }

            self?.updateDocumentControls(for: item, document: document)
        }
        annotationCanvas.onToolContextRequest = { [weak self, weak item] context in
            guard let self,
                  let item else {
                return
            }

            self.applyToolContext(context, in: item)
        }
        annotationCanvas.onEditingOptionsChange = { [weak self, weak item] in
            guard let self,
                  let item else {
                return
            }

            self.saveEditingOptions(for: item)
            self.updatePrimaryToolButtons(for: item)
            self.updateOptionMenuStates(for: item)
        }
        annotationCanvas.translatesAutoresizingMaskIntoConstraints = false
        annotationCanvas.menuProvider = contextMenuProvider
        annotationCanvas.setBaseScreenshot(item.screenshot)
        item.annotationCanvas = annotationCanvas

        let textSelectionOverlay = ImageWorkspaceTextSelectionOverlayView(
            imageSize: item.screenshot.image.size,
            imageZoom: imageZoom,
            copyText: item.copyRecognizedText ?? { _ in false }
        )
        textSelectionOverlay.translatesAutoresizingMaskIntoConstraints = false
        textSelectionOverlay.isHidden = true
        textSelectionOverlay.menuProvider = contextMenuProvider
        textSelectionOverlay.magnifyHandler = { [weak annotationCanvas] event in
            annotationCanvas?.magnify(with: event)
        }
        textSelectionOverlay.scrollWheelHandler = { [weak annotationCanvas] event in
            annotationCanvas?.scrollWheel(with: event)
        }
        imageZoom.onViewportChange = { [weak annotationCanvas, weak textSelectionOverlay] in
            annotationCanvas?.imageZoomDidChange()
            textSelectionOverlay?.imageZoomDidChange()
        }
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

        let historyStack = NSStackView()
        historyStack.orientation = .horizontal
        historyStack.alignment = .centerY
        historyStack.distribution = .fill
        historyStack.spacing = ImageWorkspaceLayout.editingToolSpacing
        historyStack.translatesAutoresizingMaskIntoConstraints = false

        let toolStack = NSStackView()
        toolStack.orientation = .horizontal
        toolStack.alignment = .centerY
        toolStack.distribution = .fill
        toolStack.spacing = ImageWorkspaceLayout.editingToolSpacing
        toolStack.translatesAutoresizingMaskIntoConstraints = false

        let undoButton = makeIconButton(
            title: item.strings.workspaceUndo,
            symbolName: "arrow.uturn.backward",
            action: #selector(undoButtonClicked),
            buttonType: .momentaryPushIn
        )
        let redoButton = makeIconButton(
            title: item.strings.workspaceRedo,
            symbolName: "arrow.uturn.forward",
            action: #selector(redoButtonClicked),
            buttonType: .momentaryPushIn
        )
        for button in [undoButton, redoButton] {
            button.isEnabled = false
            button.contentTintColor = FrameHUDChrome.disabledIcon
            button.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
            historyStack.addArrangedSubview(button)
        }
        item.undoButton = undoButton
        item.redoButton = redoButton

        let historyToolsDivider = makeToolbarDivider(identifier: "ImageWorkspaceToolbarHistoryToolsDivider")

        for toolbarItem in ImageWorkspaceToolbarToolOrder.items {
            let button = makeIconButton(
                title: title(for: toolbarItem, strings: item.strings),
                symbolName: symbolName(for: toolbarItem),
                action: action(for: toolbarItem),
                buttonType: .toggle
            )
            button.tag = tag(for: toolbarItem)
            button.isEnabled = true
            button.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
            button.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
            switch toolbarItem {
            case let .tool(tool):
                item.toolButtons.append((tool: tool, button: button))
            case let .shape(shapeKind):
                item.shapeKindButtons.append((shapeKind: shapeKind, button: button))
            }

            guard let optionsMenu = makeToolOptionsMenu(for: toolbarItem, item: item) else {
                toolStack.addArrangedSubview(button)
                continue
            }

            let optionsButton = makeIconButton(
                title: optionsTitle(for: toolbarItem, strings: item.strings),
                symbolName: "chevron.down",
                action: #selector(toolOptionsButtonClicked),
                buttonType: .momentaryPushIn,
                iconMetrics: .auxiliary
            )
            optionsButton.tag = tag(for: toolbarItem)
            optionsButton.isEnabled = true
            optionsButton.menu = optionsMenu
            optionsButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.toolOptionsButtonWidth).isActive = true
            optionsButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true

            let splitControl = ImageWorkspaceSplitToolControl(
                primaryButton: button,
                optionsButton: optionsButton
            )
            splitControl.identifier = NSUserInterfaceItemIdentifier("ImageWorkspaceToolbarMosaicSplitControl")
            toolStack.addArrangedSubview(splitControl)
        }

        let styleControl = makeHeaderStyleControl(for: item)
        item.styleControl = styleControl
        let styleDivider = makeToolbarDivider(identifier: "ImageWorkspaceToolbarStyleDivider")
        styleDivider.isHidden = true
        item.styleDivider = styleDivider

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false

        let saveEditedButton = makeIconButton(
            title: item.strings.workspaceSaveCurrent,
            symbolName: "checkmark.circle",
            action: #selector(saveEditedButtonClicked),
            buttonType: .momentaryPushIn
        )
        let copyButton = makeIconButton(
            title: item.strings.workspaceCopy,
            toolTip: item.strings.workspaceSaveAndCopy,
            symbolName: "doc.on.doc",
            action: #selector(copyButtonClicked),
            buttonType: .momentaryPushIn
        )
        let downloadButton = makeIconButton(
            title: item.strings.workspaceDownload,
            toolTip: item.strings.workspaceSaveAndDownload,
            symbolName: "square.and.arrow.down",
            action: #selector(downloadButtonClicked),
            buttonType: .momentaryPushIn
        )
        saveEditedButton.isEnabled = false
        saveEditedButton.contentTintColor = FrameHUDChrome.disabledIcon
        saveEditedButton.menu = makeSaveCurrentMenu(for: item)
        item.saveCurrentButton = saveEditedButton
        saveEditedButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.outputButtonSize).isActive = true
        saveEditedButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
        copyButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.outputButtonSize).isActive = true
        copyButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true
        downloadButton.widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.outputButtonSize).isActive = true
        downloadButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize).isActive = true

        let outputStack = NSStackView(views: [saveEditedButton, copyButton, downloadButton])
        outputStack.orientation = .horizontal
        outputStack.alignment = .centerY
        outputStack.distribution = .fill
        outputStack.spacing = ImageWorkspaceLayout.outputButtonSpacing
        outputStack.translatesAutoresizingMaskIntoConstraints = false
        let outputDivider = makeToolbarDivider(identifier: "ImageWorkspaceToolbarOutputDivider")

        contentView.addSubview(imageContainer)
        contentView.addSubview(toolbar)
        imageContainer.addSubview(annotationCanvas)
        imageContainer.addSubview(textSelectionOverlay)
        toolbar.addSubview(toolbarStack)
        toolbarStack.addArrangedSubview(historyStack)
        toolbarStack.addArrangedSubview(historyToolsDivider)
        toolbarStack.addArrangedSubview(toolStack)
        toolbarStack.addArrangedSubview(styleDivider)
        toolbarStack.addArrangedSubview(styleControl)
        toolbarStack.addArrangedSubview(spacer)
        toolbarStack.addArrangedSubview(outputDivider)
        toolbarStack.addArrangedSubview(outputStack)

        NSLayoutConstraint.activate([
            imageContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ImageWorkspaceLayout.toolbarLeading),
            imageContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ImageWorkspaceLayout.toolbarTrailing),
            imageContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: ImageWorkspaceLayout.imageTopSpacing),
            imageContainer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -ImageWorkspaceLayout.imageBottomInset),

            annotationCanvas.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            annotationCanvas.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            annotationCanvas.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            annotationCanvas.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            textSelectionOverlay.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor),
            textSelectionOverlay.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor),
            textSelectionOverlay.topAnchor.constraint(equalTo: imageContainer.topAnchor),
            textSelectionOverlay.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor),

            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: ImageWorkspaceLayout.toolbarLeading),
            toolbar.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -ImageWorkspaceLayout.toolbarTrailing),
            toolbar.topAnchor.constraint(
                equalTo: contentView.topAnchor,
                constant: -ImageWorkspaceLayout.toolbarTitlebarOverlap
            ),
            toolbar.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.toolbarHeight),

            toolbarStack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: ImageWorkspaceLayout.toolbarStackLeadingInset),
            toolbarStack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -ImageWorkspaceLayout.toolbarStackTrailingInset),
            toolbarStack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 2),
            toolbarStack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -2),

            spacer.widthAnchor.constraint(greaterThanOrEqualToConstant: ImageWorkspaceLayout.minimumSpacerWidth),
        ])

        if let selectedTool = item.state.selectedTool {
            select(selectedTool, in: item)
        }
        updatePrimaryToolButtons(for: item)
        updateDocumentControls(for: item, document: annotationCanvas.documentForTesting)

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
        imageContainer.layer?.backgroundColor = NSColor.black.cgColor
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
        toolTip: String? = nil,
        symbolName: String,
        action: Selector,
        buttonType: NSButton.ButtonType,
        iconMetrics: ImageWorkspaceToolbarIconMetrics = .primary
    ) -> ImageWorkspaceToolbarButton {
        let button = ImageWorkspaceToolbarButton(
            image: toolbarImage(symbolName: symbolName, title: title),
            iconMetrics: iconMetrics,
            target: self,
            action: action
        )
        button.toolTip = toolTip ?? title
        button.symbolConfiguration = iconMetrics.symbolConfiguration
        button.contentTintColor = FrameHUDChrome.primaryIcon
        button.setButtonType(buttonType)
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        return button
    }

    private func makeToolbarDivider(identifier: String) -> NSView {
        let divider = NSView()
        divider.identifier = NSUserInterfaceItemIdentifier(identifier)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = FrameHUDChrome.divider.cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 16).isActive = true
        return divider
    }

    private func toolbarImage(symbolName: String, title: String) -> NSImage {
        NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
            ?? NSImage(systemSymbolName: "circle", accessibilityDescription: title)
            ?? NSImage()
    }

    private func menuImage(symbolName: String, title: String) -> NSImage {
        let image = toolbarImage(symbolName: symbolName, title: title)
        image.size = NSSize(width: 14, height: 14)
        return image
    }

    private func makeHeaderStyleControl(for item: ImageWorkspaceItem) -> ImageWorkspaceHeaderStyleControlView {
        let styleControl = ImageWorkspaceHeaderStyleControlView(
            strings: item.strings,
            colors: Self.annotationColors,
            lineWidths: Self.annotationLineWidths,
            fontSizes: Self.textFontSizes
        )
        styleControl.translatesAutoresizingMaskIntoConstraints = false
        styleControl.onColorChange = { [weak self, weak item] color in
            guard let self,
                  let item else {
                return
            }

            self.applyStyleControlColor(color, in: item)
        }
        styleControl.onSizeChange = { [weak self, weak item] size in
            guard let self,
                  let item else {
                return
            }

            self.applyStyleControlSize(size, in: item)
        }
        return styleControl
    }

    private func installLifecycleCallbacks(for item: ImageWorkspaceItem) {
        item.panel.shouldClose = { [weak self, weak item] in
            guard let self,
                  let item else {
                return true
            }

            return self.shouldCloseWorkspace(item)
        }
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
        menu.addItem(makeMenuItem(title: item.strings.workspaceCopy, action: #selector(copyMenuItemClicked), representedObject: item))
        menu.addItem(makeMenuItem(title: item.strings.workspaceDownload, action: #selector(downloadMenuItemClicked), representedObject: item))
        let saveEditedMenuItem = NSMenuItem(title: item.strings.workspaceSaveCurrent, action: nil, keyEquivalent: "")
        saveEditedMenuItem.submenu = makeSaveCurrentMenu(for: item)
        saveEditedMenuItem.isEnabled = item.annotationCanvas?.documentForTesting.hasUncommittedEdits ?? false
        menu.addItem(saveEditedMenuItem)
        menu.addItem(.separator())

        for tool in ImageWorkspaceToolbarToolOrder.tools {
            let selection = ImageWorkspaceToolMenuSelection(item: item, tool: tool)
            let menuItem = makeMenuItem(
                title: item.strings.workspaceToolTitle(tool),
                action: #selector(toolMenuItemClicked),
                representedObject: selection
            )
            menuItem.state = item.state.selectedTool == tool ? .on : .off
            menuItem.isEnabled = true
            menu.addItem(menuItem)
        }

        return menu
    }

    private func makePinnedContextMenu(for item: ImageWorkspaceItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeMenuItem(title: item.strings.workspaceCopy, action: #selector(copyMenuItemClicked), representedObject: item))
        menu.addItem(makeMenuItem(title: item.strings.workspaceDownload, action: #selector(downloadMenuItemClicked), representedObject: item))
        menu.addItem(.separator())
        menu.addItem(makeMenuItem(title: item.strings.workspaceEdit, action: #selector(editMenuItemClicked), representedObject: item))
        return menu
    }

    private func makeMenuItem(title: String, action: Selector, representedObject: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = representedObject
        return item
    }

    private func makeToolOptionsMenu(for toolbarItem: ImageWorkspaceToolbarItem, item: ImageWorkspaceItem) -> NSMenu? {
        switch toolbarItem {
        case .tool(.mosaic):
            makeMosaicOptionsMenu(for: item)
        case .tool, .shape:
            nil
        }
    }

    private func makeMosaicOptionsMenu(for item: ImageWorkspaceItem) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeToolOptionItem(
            item.strings.workspaceMosaicModeTitle(.rectangle),
            item: item,
            option: .mosaicMode(.rectangle),
            symbolName: symbolName(for: ImageAnnotationMosaicMode.rectangle)
        ))
        menu.addItem(makeToolOptionItem(
            item.strings.workspaceMosaicModeTitle(.brush),
            item: item,
            option: .mosaicMode(.brush),
            symbolName: symbolName(for: ImageAnnotationMosaicMode.brush)
        ))
        updateMenuStates(menu, for: item)
        return menu
    }

    private func makeToolOptionItem(
        _ title: String,
        item: ImageWorkspaceItem,
        option: ImageWorkspaceToolOptionKind,
        symbolName: String
    ) -> NSMenuItem {
        let menuItem = makeMenuItem(
            title: title,
            action: #selector(toolOptionMenuItemClicked),
            representedObject: ImageWorkspaceToolOption(item: item, option: option)
        )
        menuItem.image = menuImage(symbolName: symbolName, title: title)
        return menuItem
    }

    private func updateOptionMenuStates(for item: ImageWorkspaceItem) {
        guard let document = item.annotationCanvas?.documentForTesting else {
            return
        }

        updateHeaderStyleControl(for: item, document: document)
    }

    private func updateMenuStates(_ menu: NSMenu?, for item: ImageWorkspaceItem) {
        guard let menu,
              let document = item.annotationCanvas?.documentForTesting else {
            return
        }

        for menuItem in menu.items {
            guard let option = (menuItem.representedObject as? ImageWorkspaceToolOption)?.option else {
                continue
            }

            menuItem.state = isOptionSelected(option, in: document) ? .on : .off
        }
    }

    private func isOptionSelected(_ option: ImageWorkspaceToolOptionKind, in document: ImageAnnotationDocument) -> Bool {
        switch option {
        case let .mosaicMode(mosaicMode):
            document.editingOptions.mosaicMode == mosaicMode
        }
    }

    private func makeSaveCurrentMenu(for item: ImageWorkspaceItem) -> NSMenu {
        let menu = NSMenu()
        let replaceItem = makeMenuItem(
            title: item.strings.workspaceReplaceCurrent,
            action: #selector(replaceCurrentMenuItemClicked),
            representedObject: item
        )
        replaceItem.image = menuImage(symbolName: "arrow.triangle.2.circlepath", title: item.strings.workspaceReplaceCurrent)
        let saveAsNewItem = makeMenuItem(
            title: item.strings.workspaceSaveAsNew,
            action: #selector(saveAsNewMenuItemClicked),
            representedObject: item
        )
        saveAsNewItem.image = menuImage(symbolName: "square.and.arrow.down", title: item.strings.workspaceSaveAsNew)
        menu.addItem(replaceItem)
        menu.addItem(saveAsNewItem)
        return menu
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
        guard sender.isEnabled,
              let item = workspaceItem(for: sender.window) else {
            return
        }

        switch saveCurrentBehaviorProvider() {
        case .askEveryTime:
            guard let menu = sender.menu else {
                return
            }

            presentSaveCurrentMenu(menu, sender)
        case .replaceCurrent:
            saveCurrentRendition(for: item)
        case .saveAsNew:
            _ = saveAsNewRendition(for: item)
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

    @objc private func shapeToolButtonClicked(_ sender: NSButton) {
        guard sender.isEnabled else {
            return
        }

        guard let item = workspaceItem(for: sender.window),
              let shapeKind = shapeKind(for: sender.tag),
              let canvas = item.annotationCanvas else {
            return
        }

        canvas.setShapeKind(shapeKind)
        saveEditingOptions(for: item)
        select(.shape, in: item)
    }

    @objc private func toolOptionsButtonClicked(_ sender: NSButton) {
        guard sender.isEnabled,
              let menu = sender.menu else {
            return
        }

        if let item = workspaceItem(for: sender.window),
           let tool = tool(for: sender.tag) {
            select(tool, in: item)
            updateMenuStates(menu, for: item)
        }

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4),
            in: sender
        )
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
            strings: item.strings,
            copy: item.copy,
            save: item.save
        )
    }

    @objc private func saveEditedMenuItemClicked(_ sender: NSMenuItem) {
        guard sender.isEnabled else {
            return
        }

        guard let item = sender.representedObject as? ImageWorkspaceItem else {
            return
        }

        saveCurrentRendition(for: item)
    }

    @objc private func replaceCurrentMenuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ImageWorkspaceItem else {
            return
        }

        saveCurrentRendition(for: item)
    }

    @objc private func saveAsNewMenuItemClicked(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ImageWorkspaceItem else {
            return
        }

        _ = saveAsNewRendition(for: item)
    }

    @objc private func undoButtonClicked(_ sender: NSButton) {
        guard sender.isEnabled else {
            return
        }

        workspaceItem(for: sender.window)?.annotationCanvas?.undo()
    }

    @objc private func redoButtonClicked(_ sender: NSButton) {
        guard sender.isEnabled else {
            return
        }

        workspaceItem(for: sender.window)?.annotationCanvas?.redo()
    }

    @objc private func toolOptionMenuItemClicked(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? ImageWorkspaceToolOption,
              let item = option.item,
              let canvas = item.annotationCanvas else {
            return
        }

        switch option.option {
        case let .mosaicMode(mosaicMode):
            canvas.setMosaicMode(mosaicMode)
            select(.mosaic, in: item)
            updatePrimaryToolButtons(for: item)
        }

        saveEditingOptions(for: item)
        updateMenuStates(sender.menu, for: item)
        updateOptionMenuStates(for: item)
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

    private func select(_ tool: ImageAnnotationTool, in item: ImageWorkspaceItem) {
        item.state.select(tool)
        item.annotationCanvas?.selectTool(tool)
        item.textSelectionOverlay?.setTextSelectionEnabled(tool == .select)
        updatePrimaryToolButtons(for: item)
        updateSelectionStates(for: item)
    }

    private func applyToolContext(_ context: ImageAnnotationCanvasToolContext, in item: ImageWorkspaceItem) {
        guard let canvas = item.annotationCanvas else {
            return
        }

        switch context {
        case let .tool(tool):
            select(tool, in: item)
        case let .shape(shapeKind):
            canvas.setShapeKind(shapeKind)
            select(.shape, in: item)
            saveEditingOptions(for: item)
        case let .mosaic(mosaicMode):
            canvas.setMosaicMode(mosaicMode)
            select(.mosaic, in: item)
            saveEditingOptions(for: item)
        }

        updateOptionMenuStates(for: item)
    }

    private func applyStyleControlColor(_ color: ImageAnnotationColor, in item: ImageWorkspaceItem) {
        guard let canvas = item.annotationCanvas else {
            return
        }

        var style = canvas.documentForTesting.editingOptions.style
        style.strokeColor = color
        canvas.setStyle(style)
        saveEditingOptions(for: item)
        updatePrimaryToolButtons(for: item)
        updateOptionMenuStates(for: item)
    }

    private func applyStyleControlSize(_ size: CGFloat, in item: ImageWorkspaceItem) {
        guard let canvas = item.annotationCanvas else {
            return
        }

        var style = canvas.documentForTesting.editingOptions.style
        switch styleControlMode(for: canvas.documentForTesting) {
        case .lineWidth:
            style.lineWidth = size
        case .fontSize:
            style.fontSize = size
        case .disabled:
            return
        }

        canvas.setStyle(style)
        saveEditingOptions(for: item)
        updatePrimaryToolButtons(for: item)
        updateOptionMenuStates(for: item)
    }

    private func saveEditingOptions(for item: ImageWorkspaceItem) {
        guard let options = item.annotationCanvas?.documentForTesting.editingOptions else {
            return
        }

        persistEditingOptions(options)
    }

    private func updateSelectionStates(for item: ImageWorkspaceItem) {
        let selectedTool = item.state.selectedTool
        let selectedShapeKind = item.annotationCanvas?.documentForTesting.editingOptions.shapeKind
        for toolButton in item.toolButtons {
            updateSelectionState(
                for: toolButton.button,
                isSelected: toolButton.tool == selectedTool
            )
        }
        for shapeButton in item.shapeKindButtons {
            updateSelectionState(
                for: shapeButton.button,
                isSelected: selectedTool == .shape && shapeButton.shapeKind == selectedShapeKind
            )
        }
    }

    private func updateSelectionState(for button: NSButton, isSelected: Bool) {
        button.state = isSelected ? .on : .off
        button.contentTintColor = isSelected
            ? FrameHUDChrome.selectedIcon
            : FrameHUDChrome.primaryIcon
        if let toolbarButton = button as? ImageWorkspaceToolbarButton {
            toolbarButton.isWorkspaceSelected = isSelected
        }
    }

    private func updatePrimaryToolButtons(for item: ImageWorkspaceItem) {
        guard let document = item.annotationCanvas?.documentForTesting else {
            return
        }

        if let mosaicButton = toolButton(for: .mosaic, in: item) {
            let title = item.strings.workspaceMosaicModeTitle(document.editingOptions.mosaicMode)
            updatePrimaryToolButton(
                mosaicButton,
                symbolName: symbolName(for: document.editingOptions.mosaicMode),
                title: title
            )
        }

        updateHeaderStyleControl(for: item, document: document)
    }

    private func updatePrimaryToolButton(_ button: NSButton, symbolName: String, title: String) {
        button.image = toolbarImage(symbolName: symbolName, title: title)
        button.toolTip = title
        button.setAccessibilityHelp(title)
    }

    private func updateHeaderStyleControl(for item: ImageWorkspaceItem, document: ImageAnnotationDocument) {
        let sizeMode = styleControlMode(for: document)
        let isVisible = sizeMode != .disabled
        item.styleControl?.isHidden = !isVisible
        item.styleDivider?.isHidden = !isVisible
        item.styleControl?.update(
            color: document.editingOptions.style.strokeColor,
            sizeMode: sizeMode,
            style: document.editingOptions.style
        )
    }

    private func styleControlMode(for document: ImageAnnotationDocument) -> ImageWorkspaceStyleControlSizeMode {
        if let selectedElementID = document.selectedElementID,
           let selectedElement = document.elements.first(where: { $0.id == selectedElementID }) {
            switch selectedElement.kind {
            case .shape, .brush, .highlight:
                return .lineWidth
            case .text:
                return .fontSize
            case .mosaic:
                return .disabled
            }
        }

        switch document.selectedTool {
        case .shape, .brush, .highlight:
            return .lineWidth
        case .text:
            return .fontSize
        case .select, .mosaic:
            return .disabled
        }
    }

    private func updateDocumentControls(for item: ImageWorkspaceItem, document: ImageAnnotationDocument) {
        item.saveCurrentButton?.isEnabled = document.hasUncommittedEdits
        item.saveCurrentButton?.contentTintColor = document.hasUncommittedEdits
            ? FrameHUDChrome.primaryIcon
            : FrameHUDChrome.disabledIcon
        updateHistoryButton(item.undoButton, isEnabled: document.canUndo)
        updateHistoryButton(item.redoButton, isEnabled: document.canRedo)
        updateHeaderStyleControl(for: item, document: document)
    }

    private func updateHistoryButton(_ button: NSButton?, isEnabled: Bool) {
        button?.isEnabled = isEnabled
        button?.contentTintColor = isEnabled
            ? FrameHUDChrome.primaryIcon
            : FrameHUDChrome.disabledIcon
    }

    private func toolButton(for tool: ImageAnnotationTool, in item: ImageWorkspaceItem) -> NSButton? {
        item.toolButtons.first { $0.tool == tool }?.button
    }

    private func copyOutput(for item: ImageWorkspaceItem) {
        guard let screenshot = renderedScreenshot(for: item),
              item.copy(screenshot) else {
            return
        }

        if item.state.kind == .temporaryPreview {
            closeWorkspace(item, prompting: false)
        }
    }

    private func downloadOutput(for item: ImageWorkspaceItem) {
        guard let screenshot = renderedScreenshot(for: item),
              item.save(screenshot) else {
            return
        }

        if item.state.kind == .temporaryPreview {
            closeWorkspace(item, prompting: false)
        }
    }

    @discardableResult
    private func saveCurrentRendition(for item: ImageWorkspaceItem) -> Bool {
        guard let screenshot = renderedScreenshot(for: item) else {
            return false
        }

        item.screenshot = screenshot
        item.annotationCanvas?.setBaseScreenshot(screenshot)
        item.annotationCanvas?.markCurrentRenditionSaved()
        item.replaceCurrent?(screenshot)
        item.saveCurrentButton?.isEnabled = false
        item.saveCurrentButton?.contentTintColor = .disabledControlTextColor
        updateDocumentControls(for: item, document: item.annotationCanvas?.documentForTesting ?? ImageAnnotationDocument())
        return true
    }

    @discardableResult
    private func saveAsNewRendition(for item: ImageWorkspaceItem) -> Bool {
        guard let screenshot = renderedScreenshot(for: item, preservingID: false) else {
            return false
        }

        if let saveAsNew = item.saveAsNew {
            return saveAsNew(screenshot)
        }

        return item.save(screenshot)
    }

    private func renderedScreenshot(for item: ImageWorkspaceItem, preservingID: Bool = true) -> CapturedScreenshot? {
        guard let canvas = item.annotationCanvas else {
            return item.screenshot
        }

        do {
            return try ImageAnnotationRenderer().render(
                screenshot: item.screenshot,
                document: canvas.documentForTesting,
                preservingID: preservingID
            )
        } catch {
            NSLog("Frame 编辑截图渲染失败: \(error.localizedDescription)")
            return nil
        }
    }

    private func shouldCloseWorkspace(_ item: ImageWorkspaceItem) -> Bool {
        guard item.state.kind == .temporaryPreview,
              item.annotationCanvas?.documentForTesting.hasUncommittedEdits == true else {
            return true
        }

        switch item.closeSaveChoice?() ?? presentCloseSaveChoice(for: item) {
        case .save:
            switch saveCurrentBehaviorProvider() {
            case .replaceCurrent:
                return saveCurrentRendition(for: item)
            case .saveAsNew:
                return saveAsNewRendition(for: item)
            case .askEveryTime:
                return false
            }
        case .replaceCurrent:
            return saveCurrentRendition(for: item)
        case .saveAsNew:
            return saveAsNewRendition(for: item)
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    private func presentCloseSaveChoice(for item: ImageWorkspaceItem) -> ImageWorkspaceCloseSaveChoice {
        let alert = NSAlert()
        alert.messageText = item.strings.workspaceUnsavedChangesTitle
        alert.informativeText = item.strings.workspaceUnsavedChangesMessage
        alert.alertStyle = .warning

        if saveCurrentBehaviorProvider() == .askEveryTime {
            alert.addButton(withTitle: item.strings.workspaceReplaceCurrent)
            alert.addButton(withTitle: item.strings.workspaceSaveAsNew)
            alert.addButton(withTitle: item.strings.workspaceDiscardEdits)
            alert.addButton(withTitle: item.strings.cancel)

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                return .replaceCurrent
            case .alertSecondButtonReturn:
                return .saveAsNew
            case .alertThirdButtonReturn:
                return .discard
            default:
                return .cancel
            }
        }

        alert.addButton(withTitle: item.strings.workspaceSaveCurrent)
        alert.addButton(withTitle: item.strings.workspaceDiscardEdits)
        alert.addButton(withTitle: item.strings.cancel)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func closeWorkspace(_ item: ImageWorkspaceItem, prompting: Bool = true) {
        item.panel.suppressesClosePrompt = !prompting
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

    private func title(for toolbarItem: ImageWorkspaceToolbarItem, strings: AppStrings) -> String {
        switch toolbarItem {
        case let .tool(tool):
            strings.workspaceToolTitle(tool)
        case let .shape(shapeKind):
            strings.workspaceShapeKindTitle(shapeKind)
        }
    }

    private func optionsTitle(for toolbarItem: ImageWorkspaceToolbarItem, strings: AppStrings) -> String {
        switch toolbarItem {
        case let .tool(tool):
            strings.workspaceToolOptionsTitle(tool)
        case let .shape(shapeKind):
            "\(strings.workspaceShapeKindTitle(shapeKind)) Options"
        }
    }

    private func action(for toolbarItem: ImageWorkspaceToolbarItem) -> Selector {
        switch toolbarItem {
        case .tool:
            #selector(toolButtonClicked)
        case .shape:
            #selector(shapeToolButtonClicked)
        }
    }

    private func symbolName(for toolbarItem: ImageWorkspaceToolbarItem) -> String {
        switch toolbarItem {
        case let .tool(tool):
            symbolName(for: tool)
        case let .shape(shapeKind):
            symbolName(for: shapeKind)
        }
    }

    private func symbolName(for tool: ImageAnnotationTool) -> String {
        switch tool {
        case .select:
            "cursorarrow"
        case .mosaic:
            symbolName(for: ImageAnnotationMosaicMode.rectangle)
        case .shape:
            symbolName(for: ImageAnnotationShapeKind.rectangle)
        case .brush:
            "pencil"
        case .text:
            "textformat"
        case .highlight:
            "highlighter"
        }
    }

    private func symbolName(for shapeKind: ImageAnnotationShapeKind) -> String {
        switch shapeKind {
        case .rectangle:
            "rectangle"
        case .ellipse:
            "circle"
        case .line:
            "line.diagonal"
        case .arrow:
            "arrow.up.right"
        }
    }

    private func symbolName(for mosaicMode: ImageAnnotationMosaicMode) -> String {
        switch mosaicMode {
        case .rectangle:
            "checkerboard.rectangle"
        case .brush:
            "paintbrush.pointed.fill"
        }
    }

    private func tag(for tool: ImageAnnotationTool) -> Int {
        switch tool {
        case .select:
            1
        case .mosaic:
            2
        case .shape:
            3
        case .brush:
            4
        case .text:
            5
        case .highlight:
            6
        }
    }

    private func tag(for shapeKind: ImageAnnotationShapeKind) -> Int {
        switch shapeKind {
        case .rectangle:
            101
        case .ellipse:
            102
        case .line:
            103
        case .arrow:
            104
        }
    }

    private func tag(for toolbarItem: ImageWorkspaceToolbarItem) -> Int {
        switch toolbarItem {
        case let .tool(tool):
            tag(for: tool)
        case let .shape(shapeKind):
            tag(for: shapeKind)
        }
    }

    private func tool(for tag: Int) -> ImageAnnotationTool? {
        switch tag {
        case 1:
            .select
        case 2:
            .mosaic
        case 3:
            .shape
        case 4:
            .brush
        case 5:
            .text
        case 6:
            .highlight
        default:
            nil
        }
    }

    private func shapeKind(for tag: Int) -> ImageAnnotationShapeKind? {
        switch tag {
        case 101:
            .rectangle
        case 102:
            .ellipse
        case 103:
            .line
        case 104:
            .arrow
        default:
            nil
        }
    }

    private static let annotationLineWidths: [CGFloat] = [1, 2, 4, 8, 12, 16, 24]
    private static let textFontSizes: [CGFloat] = [12, 14, 16, 18, 22, 28, 36, 48, 64, 80, 96]
    private static let annotationColors: [ImageAnnotationColor] = [.red, .yellow, .blue, .green, .white, .black]
}

private final class ImageWorkspaceItem {
    var state: ImageWorkspaceState
    let panel: ImageWorkspacePanel
    var screenshot: CapturedScreenshot
    let strings: AppStrings
    let copy: (CapturedScreenshot) -> Bool
    let save: (CapturedScreenshot) -> Bool
    let recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)?
    let copyRecognizedText: ((String) -> Bool)?
    let replaceCurrent: ((CapturedScreenshot) -> Void)?
    let saveAsNew: ((CapturedScreenshot) -> Bool)?
    let closeSaveChoice: (() -> ImageWorkspaceCloseSaveChoice)?
    var notificationObservers: [NSObjectProtocol] = []
    var toolButtons: [(tool: ImageAnnotationTool, button: NSButton)] = []
    var shapeKindButtons: [(shapeKind: ImageAnnotationShapeKind, button: NSButton)] = []
    weak var annotationCanvas: ImageAnnotationCanvasView?
    var imageZoom: ImageWorkspaceImageZoom?
    weak var saveCurrentButton: NSButton?
    weak var styleControl: ImageWorkspaceHeaderStyleControlView?
    weak var styleDivider: NSView?
    weak var undoButton: NSButton?
    weak var redoButton: NSButton?
    weak var textSelectionOverlay: ImageWorkspaceTextSelectionOverlayView?
    var ocrTask: Task<Void, Never>?

    init(
        state: ImageWorkspaceState,
        panel: ImageWorkspacePanel,
        screenshot: CapturedScreenshot,
        strings: AppStrings,
        copy: @escaping (CapturedScreenshot) -> Bool,
        save: @escaping (CapturedScreenshot) -> Bool,
        recognizeText: ((CapturedScreenshot) async throws -> RecognizedTextLayout)?,
        copyRecognizedText: ((String) -> Bool)?,
        replaceCurrent: ((CapturedScreenshot) -> Void)?,
        saveAsNew: ((CapturedScreenshot) -> Bool)?,
        closeSaveChoice: (() -> ImageWorkspaceCloseSaveChoice)?
    ) {
        self.state = state
        self.panel = panel
        self.screenshot = screenshot
        self.strings = strings
        self.copy = copy
        self.save = save
        self.recognizeText = recognizeText
        self.copyRecognizedText = copyRecognizedText
        self.replaceCurrent = replaceCurrent
        self.saveAsNew = saveAsNew
        self.closeSaveChoice = closeSaveChoice
    }
}

enum ImageWorkspaceCloseSaveChoice {
    case save
    case replaceCurrent
    case saveAsNew
    case discard
    case cancel
}

private final class ImageWorkspaceToolMenuSelection: NSObject {
    let item: ImageWorkspaceItem
    let tool: ImageAnnotationTool

    init(item: ImageWorkspaceItem, tool: ImageAnnotationTool) {
        self.item = item
        self.tool = tool
    }
}

private enum ImageWorkspaceToolbarItem: Equatable {
    case tool(ImageAnnotationTool)
    case shape(ImageAnnotationShapeKind)
}

private enum ImageWorkspaceToolbarToolOrder {
    static let items: [ImageWorkspaceToolbarItem] = [
        .tool(.select),
        .shape(.rectangle),
        .shape(.ellipse),
        .shape(.line),
        .shape(.arrow),
        .tool(.brush),
        .tool(.text),
        .tool(.highlight),
        .tool(.mosaic),
    ]

    static let tools: [ImageAnnotationTool] = [.select, .shape, .brush, .text, .highlight, .mosaic]
}

private final class ImageWorkspaceToolOption: NSObject {
    weak var item: ImageWorkspaceItem?
    let option: ImageWorkspaceToolOptionKind

    init(item: ImageWorkspaceItem, option: ImageWorkspaceToolOptionKind) {
        self.item = item
        self.option = option
    }
}

private enum ImageWorkspaceToolOptionKind {
    case mosaicMode(ImageAnnotationMosaicMode)
}

private enum ImageWorkspaceStyleControlSizeMode {
    case disabled
    case lineWidth
    case fontSize
}

private final class ImageWorkspaceHeaderStyleControlView: NSView {
    var onColorChange: ((ImageAnnotationColor) -> Void)?
    var onSizeChange: ((CGFloat) -> Void)?

    private let strings: AppStrings
    private let colors: [ImageAnnotationColor]
    private let lineWidths: [CGFloat]
    private let fontSizes: [CGFloat]
    private var selectedColor: ImageAnnotationColor = .red
    private var sizeMode: ImageWorkspaceStyleControlSizeMode = .disabled
    private var currentSizeValues: [CGFloat] = []
    private let colorMenuButton = NSButton()
    private let colorMenu = NSMenu()
    private var colorPaletteButtons: [(color: ImageAnnotationColor, button: NSButton)] = []
    private let sizeIconView = NSImageView()
    private let sizeSlider = NSSlider()

    init(
        strings: AppStrings,
        colors: [ImageAnnotationColor],
        lineWidths: [CGFloat],
        fontSizes: [CGFloat]
    ) {
        self.strings = strings
        self.colors = colors
        self.lineWidths = lineWidths
        self.fontSizes = fontSizes
        super.init(frame: .zero)
        configureColorMenu()
        configureView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func update(
        color: ImageAnnotationColor,
        sizeMode: ImageWorkspaceStyleControlSizeMode,
        style: ImageAnnotationStyle
    ) {
        selectedColor = color
        self.sizeMode = sizeMode
        updateColorSelection()

        let values = sizeValues(for: sizeMode)
        currentSizeValues = values
        updateSizeControlMetadata(value: nil)
        sizeSlider.isEnabled = !values.isEmpty
        sizeSlider.alphaValue = values.isEmpty ? 0.45 : 1
        sizeSlider.numberOfTickMarks = values.count
        sizeSlider.maxValue = Double(max(0, values.count - 1))

        guard !values.isEmpty else {
            sizeSlider.doubleValue = 0
            return
        }

        let currentSize: CGFloat
        switch sizeMode {
        case .lineWidth:
            currentSize = style.lineWidth
        case .fontSize:
            currentSize = style.fontSize
        case .disabled:
            currentSize = values[0]
        }

        let valueIndex = index(for: currentSize, in: values)
        sizeSlider.doubleValue = Double(valueIndex)
        updateSizeControlMetadata(value: values[valueIndex])
    }

    private func configureView() {
        wantsLayer = true
        isHidden = true
        setAccessibilityLabel("Image Workspace Header Style Control")

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        colorMenuButton.isBordered = false
        colorMenuButton.target = self
        colorMenuButton.action = #selector(colorMenuButtonClicked)
        colorMenuButton.imagePosition = .imageOnly
        colorMenuButton.wantsLayer = true
        colorMenuButton.layer?.cornerRadius = 7
        colorMenuButton.layer?.cornerCurve = .continuous
        colorMenuButton.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        colorMenuButton.menu = colorMenu
        colorMenuButton.setAccessibilityLabel(strings.workspaceColorOptions)
        colorMenuButton.widthAnchor.constraint(equalToConstant: 34).isActive = true
        colorMenuButton.heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.headerStyleControlHeight).isActive = true
        stack.addArrangedSubview(colorMenuButton)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.separatorColor.withAlphaComponent(0.3).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
        divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(divider)

        sizeIconView.imageScaling = .scaleProportionallyDown
        sizeIconView.contentTintColor = .secondaryLabelColor
        sizeIconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        sizeIconView.heightAnchor.constraint(equalToConstant: 16).isActive = true
        stack.addArrangedSubview(sizeIconView)

        sizeSlider.controlSize = .small
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeSliderChanged)
        sizeSlider.allowsTickMarkValuesOnly = true
        sizeSlider.isContinuous = true
        sizeSlider.widthAnchor.constraint(equalToConstant: 122).isActive = true
        stack.addArrangedSubview(sizeSlider)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.headerStyleControlWidth),
            heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.headerStyleControlHeight),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    private func configureColorMenu() {
        let paletteView = NSView(frame: NSRect(x: 0, y: 0, width: 124, height: 78))
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .leading
        grid.distribution = .fillEqually
        grid.spacing = 4
        grid.translatesAutoresizingMaskIntoConstraints = false
        paletteView.addSubview(grid)

        for rowColors in colors.chunked(into: 3) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = 4
            grid.addArrangedSubview(row)

            for color in rowColors {
                let title = strings.workspaceColorTitle(color)
                let button = NSButton(image: Self.colorSwatchImage(color: color, size: NSSize(width: 20, height: 20)), target: self, action: #selector(colorPaletteButtonClicked))
                button.title = ""
                button.imagePosition = .imageOnly
                button.alignment = .center
                button.isBordered = false
                button.setButtonType(.toggle)
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                button.layer?.cornerCurve = .continuous
                button.toolTip = title
                button.setAccessibilityLabel(title)
                button.widthAnchor.constraint(equalToConstant: 34).isActive = true
                button.heightAnchor.constraint(equalToConstant: 30).isActive = true
                colorPaletteButtons.append((color: color, button: button))
                row.addArrangedSubview(button)
            }
        }

        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: paletteView.leadingAnchor, constant: 6),
            grid.trailingAnchor.constraint(equalTo: paletteView.trailingAnchor, constant: -6),
            grid.topAnchor.constraint(equalTo: paletteView.topAnchor, constant: 6),
            grid.bottomAnchor.constraint(equalTo: paletteView.bottomAnchor, constant: -6),
        ])

        let paletteItem = NSMenuItem()
        paletteItem.view = paletteView
        colorMenu.addItem(paletteItem)
    }

    @objc private func colorMenuButtonClicked(_ sender: NSButton) {
        colorMenu.popUp(
            positioning: nil,
            at: NSPoint(x: sender.bounds.minX, y: sender.bounds.maxY + 4),
            in: sender
        )
    }

    @objc private func colorPaletteButtonClicked(_ sender: NSButton) {
        guard let color = colorPaletteButtons.first(where: { $0.button === sender })?.color else {
            return
        }

        selectedColor = color
        updateColorSelection()
        colorMenu.cancelTracking()
        onColorChange?(color)
    }

    @objc private func sizeSliderChanged(_ sender: NSSlider) {
        guard !currentSizeValues.isEmpty else {
            return
        }

        let valueIndex = max(0, min(currentSizeValues.count - 1, Int(sender.doubleValue.rounded())))
        sender.doubleValue = Double(valueIndex)
        let value = currentSizeValues[valueIndex]
        updateSizeControlMetadata(value: value)
        onSizeChange?(value)
    }

    private func updateColorSelection() {
        let selectedTitle = strings.workspaceColorTitle(selectedColor)
        colorMenuButton.image = Self.colorSelectorImage(color: selectedColor)
        colorMenuButton.title = ""
        colorMenuButton.toolTip = selectedTitle
        colorMenuButton.setAccessibilityHelp(selectedTitle)
        for colorButton in colorPaletteButtons {
            let isSelected = colorButton.color == selectedColor
            colorButton.button.state = isSelected ? .on : .off
            colorButton.button.layer?.backgroundColor = (isSelected ? NSColor.controlAccentColor : NSColor.clear)
                .withAlphaComponent(isSelected ? 0.16 : 0)
                .cgColor
        }
    }

    private func updateSizeControlMetadata(value: CGFloat?) {
        let title: String
        let symbolName: String
        let valueDescription: String?
        switch sizeMode {
        case .lineWidth:
            title = strings.workspaceThicknessOptions
            symbolName = "lineweight"
            valueDescription = value.map { strings.workspaceLineWidth($0) }
        case .fontSize:
            title = strings.workspaceFontSizeOptions
            symbolName = "textformat.size"
            valueDescription = value.map { strings.workspaceFontSize($0) }
        case .disabled:
            title = strings.workspaceThicknessOptions
            symbolName = "lineweight"
            valueDescription = nil
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        image?.isTemplate = true
        sizeIconView.image = image
        sizeIconView.contentTintColor = currentSizeValues.isEmpty ? .disabledControlTextColor : .secondaryLabelColor
        sizeIconView.toolTip = title
        sizeSlider.setAccessibilityLabel(title)
        sizeSlider.toolTip = valueDescription.map { "\(title): \($0)" } ?? title
    }

    private func sizeValues(for mode: ImageWorkspaceStyleControlSizeMode) -> [CGFloat] {
        switch mode {
        case .lineWidth:
            return lineWidths
        case .fontSize:
            return fontSizes
        case .disabled:
            return []
        }
    }

    private func index(for value: CGFloat, in values: [CGFloat]) -> Int {
        values
            .enumerated()
            .min { abs($0.element - value) < abs($1.element - value) }?
            .offset ?? 0
    }

    private static func colorSelectorImage(color: ImageAnnotationColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 20))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()

        drawColorSwatch(color: color, in: NSRect(x: 2, y: 2, width: 16, height: 16))

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func colorSwatchImage(color: ImageAnnotationColor, size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        drawColorSwatch(color: color, in: NSRect(x: 2, y: 2, width: size.width - 4, height: size.height - 4))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawColorSwatch(color: ImageAnnotationColor, in rect: NSRect) {
        let swatchPath = NSBezierPath(ovalIn: rect)
        color.nsColor.setFill()
        swatchPath.fill()
        NSColor.separatorColor.withAlphaComponent(color == .white ? 0.9 : 0.5).setStroke()
        swatchPath.lineWidth = 1
        swatchPath.stroke()
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { startIndex in
            Array(self[startIndex..<Swift.min(startIndex + size, count)])
        }
    }
}

private struct ImageWorkspaceInitialLayout {
    let contentSize: CGSize
    let usesScrollableViewport: Bool
}

private enum ImageWorkspaceLayout {
    static let fallbackImageSize = CGSize(width: 640, height: 420)
    static let toolbarLeading: CGFloat = 0
    static let toolbarTrailing: CGFloat = 0
    static let toolbarTitlebarOverlap: CGFloat = 2
    static let toolbarStackLeadingInset: CGFloat = 88
    static let toolbarStackTrailingInset: CGFloat = 6
    static let toolbarStackSpacing: CGFloat = 8
    static let toolbarHeight: CGFloat = 36
    static let imageTopSpacing: CGFloat = 6
    static let imageBottomInset: CGFloat = 0
    static let editingToolSize: CGFloat = 28
    static let toolOptionsButtonWidth: CGFloat = 20
    static let mosaicSplitControlWidth = editingToolSize + toolOptionsButtonWidth
    static let editingToolSpacing: CGFloat = 4
    static let outputButtonSize: CGFloat = 28
    static let outputButtonSpacing: CGFloat = 2
    static let minimumSpacerWidth: CGFloat = 12
    static let headerStyleControlWidth: CGFloat = 191
    static let headerStyleControlHeight: CGFloat = 28
    static let baseMinimumContentWidth: CGFloat = 440
    static let pinnedMinimumContentWidth: CGFloat = 320
    static let initialWindowScreenMargin: CGFloat = 80
    static let minimumScrollableViewportHeight: CGFloat = 260

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
                fixedVerticalChromeHeight: toolbarHeight - toolbarTitlebarOverlap + imageTopSpacing + imageBottomInset,
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
        let toolbarItemCount = CGFloat(ImageWorkspaceToolbarToolOrder.items.count)
        let historyButtonCount: CGFloat = 2
        let historyWidth = editingToolSize * historyButtonCount
            + editingToolSpacing * (historyButtonCount - 1)
        let toolsWidth = editingToolSize * toolbarItemCount
            + headerStyleControlWidth
            + toolOptionsButtonWidth
            + editingToolSpacing * (toolbarItemCount - 1)
        let dividerCount: CGFloat = 3
        let dividerWidth = dividerCount
        let toolbarGroupGapCount: CGFloat = 7
        let toolbarGroupSpacing = toolbarStackSpacing * toolbarGroupGapCount
        let outputControlsWidth = outputButtonSize * 3 + outputButtonSpacing * 2
        return toolbarStackLeadingInset
            + toolbarStackTrailingInset
            + historyWidth
            + toolsWidth
            + dividerWidth
            + toolbarGroupSpacing
            + minimumSpacerWidth
            + outputControlsWidth
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
    var shouldClose: (() -> Bool)?
    var suppressesClosePrompt = false
    private var imageAspectRatio: CGFloat?
    private var isLiveAspectResize = false
    private var liveResizeAxis: ImageWorkspaceResizeAxis?
    private var resizeMetrics = ImageWorkspaceResizeMetrics(
        fixedVerticalChromeHeight: 0,
        horizontalChromeWidth: 0,
        minimumContentWidth: ImageWorkspaceLayout.pinnedMinimumContentWidth
    )
    var usesScrollableImageViewport = false

    func configureResize(
        imageAspectRatio: CGFloat?,
        metrics: ImageWorkspaceResizeMetrics
    ) {
        self.imageAspectRatio = imageAspectRatio
        resizeMetrics = metrics
        if let imageAspectRatio {
            minSize = frameSize(forContentSize: metrics.minimumContentSize(for: imageAspectRatio))
        } else {
            minSize = frameSize(forContentSize: NSSize(
                width: metrics.minimumContentWidth,
                height: ImageWorkspaceLayout.minimumScrollableViewportHeight
            ))
        }
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
        if contentView != nil,
           !suppressesClosePrompt,
           shouldClose?() == false {
            return
        }

        let closeHandler = onClose
        onClose = nil
        shouldClose = nil
        closeHandler?()
        super.close()
        suppressesClosePrompt = false
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let editCommand = standardEditCommand(for: event),
           let firstResponder,
           NSApp.sendAction(editCommand, to: firstResponder, from: self) {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    private func standardEditCommand(for event: NSEvent) -> Selector? {
        guard event.type == .keyDown,
              event.modifierFlags.contains(.command),
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSubset(of: .command),
              let character = event.charactersIgnoringModifiers?.lowercased() else {
            return nil
        }

        switch character {
        case "a":
            return #selector(NSText.selectAll(_:))
        case "c":
            return #selector(NSText.copy(_:))
        case "x":
            return #selector(NSText.cut(_:))
        case "v":
            return #selector(NSText.paste(_:))
        default:
            return nil
        }
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
        alphaValue = 1
        FrameHUDChrome.configure(self, surface: .toolbar, cornerRadius: toolbarHeight / 2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class ImageWorkspaceToolbarIconView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct ImageWorkspaceToolbarIconMetrics {
    let pointSize: CGFloat
    let weight: NSFont.Weight
    let iconSide: CGFloat
    let imageScaling: NSImageScaling

    var symbolConfiguration: NSImage.SymbolConfiguration {
        NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
    }

    static let primary = ImageWorkspaceToolbarIconMetrics(
        pointSize: 12,
        weight: .medium,
        iconSide: 14,
        imageScaling: .scaleProportionallyDown
    )
    static let auxiliary = ImageWorkspaceToolbarIconMetrics(
        pointSize: 8,
        weight: .semibold,
        iconSide: 10,
        imageScaling: .scaleProportionallyDown
    )
}

private final class ImageWorkspaceSplitToolControl: NSView {
    private let primaryButton: ImageWorkspaceToolbarButton
    private let optionsButton: ImageWorkspaceToolbarButton
    private let backgroundLayer = CALayer()
    private let dividerLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            updateAppearance()
        }
    }

    var isWorkspaceSelected = false {
        didSet {
            updateAppearance()
        }
    }

    init(primaryButton: ImageWorkspaceToolbarButton, optionsButton: ImageWorkspaceToolbarButton) {
        self.primaryButton = primaryButton
        self.optionsButton = optionsButton
        super.init(frame: .zero)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        backgroundLayer.frame = bounds
        dividerLayer.frame = CGRect(
            x: ImageWorkspaceLayout.editingToolSize - 0.5,
            y: 5,
            width: 1,
            height: max(0, bounds.height - 10)
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        super.mouseExited(with: event)
    }

    func showPressFeedback() {
        animateBackground(opacity: isWorkspaceSelected ? 1 : 0.22)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        backgroundLayer.cornerRadius = 8
        backgroundLayer.cornerCurve = .continuous
        backgroundLayer.opacity = 0
        dividerLayer.backgroundColor = FrameHUDChrome.divider.cgColor
        dividerLayer.opacity = 0.24
        layer?.insertSublayer(backgroundLayer, at: 0)
        layer?.addSublayer(dividerLayer)

        primaryButton.splitToolControl = self
        optionsButton.splitToolControl = self
        addSubview(primaryButton)
        addSubview(optionsButton)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: ImageWorkspaceLayout.mosaicSplitControlWidth),
            heightAnchor.constraint(equalToConstant: ImageWorkspaceLayout.editingToolSize),
            primaryButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            primaryButton.topAnchor.constraint(equalTo: topAnchor),
            primaryButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            optionsButton.leadingAnchor.constraint(equalTo: primaryButton.trailingAnchor),
            optionsButton.topAnchor.constraint(equalTo: topAnchor),
            optionsButton.trailingAnchor.constraint(equalTo: trailingAnchor),
            optionsButton.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func updateAppearance() {
        if isWorkspaceSelected {
            backgroundLayer.backgroundColor = FrameHUDChrome.selectedFill.cgColor
            dividerLayer.opacity = 0.52
            animateBackground(opacity: 1)
            return
        }

        backgroundLayer.backgroundColor = FrameHUDChrome.hoverFill.cgColor
        dividerLayer.opacity = isHovering ? 0.36 : 0.24
        animateBackground(opacity: isHovering ? 1 : 0)
    }

    private func animateBackground(opacity: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = backgroundLayer.presentation()?.opacity ?? backgroundLayer.opacity
        animation.toValue = opacity
        animation.duration = 0.14
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        backgroundLayer.opacity = opacity
        backgroundLayer.add(animation, forKey: "opacity")
    }
}

private final class ImageWorkspaceToolbarButton: NSButton {
    private let iconMetrics: ImageWorkspaceToolbarIconMetrics
    private let hoverLayer = CALayer()
    private let iconView = ImageWorkspaceToolbarIconView()
    private var trackingArea: NSTrackingArea?
    weak var splitToolControl: ImageWorkspaceSplitToolControl?
    private var isHovering = false {
        didSet {
            updateHoverAppearance()
        }
    }
    var isWorkspaceSelected = false {
        didSet {
            if let splitToolControl {
                splitToolControl.isWorkspaceSelected = isWorkspaceSelected
                return
            }

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
    override var image: NSImage? {
        get {
            iconView.image
        }
        set {
            iconView.image = newValue
            super.image = nil
            needsLayout = true
        }
    }
    override var contentTintColor: NSColor? {
        get {
            iconView.contentTintColor
        }
        set {
            iconView.contentTintColor = newValue
        }
    }
    override var symbolConfiguration: NSImage.SymbolConfiguration? {
        get {
            iconView.symbolConfiguration
        }
        set {
            iconView.symbolConfiguration = newValue
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        iconMetrics = .primary
        super.init(frame: frameRect)
        configure()
    }

    init(
        image: NSImage,
        iconMetrics: ImageWorkspaceToolbarIconMetrics,
        target: AnyObject?,
        action: Selector?
    ) {
        self.iconMetrics = iconMetrics
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

        let iconSide = min(bounds.width, bounds.height, iconMetrics.iconSide)
        iconView.frame = CGRect(
            x: bounds.midX - iconSide / 2,
            y: bounds.midY - iconSide / 2,
            width: iconSide,
            height: iconSide
        )
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

        if let splitToolControl {
            splitToolControl.showPressFeedback()
            super.mouseDown(with: event)
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
        imageScaling = .scaleNone
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        iconView.imageScaling = iconMetrics.imageScaling
        iconView.imageAlignment = .alignCenter
        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.isEditable = false
        addSubview(iconView)
        hoverLayer.opacity = 0
        hoverLayer.backgroundColor = FrameHUDChrome.hoverFill.cgColor
        layer?.insertSublayer(hoverLayer, at: 0)
    }

    private func updateHoverAppearance() {
        if splitToolControl != nil {
            return
        }

        guard isEnabled else {
            animateHoverLayer(opacity: 0)
            return
        }

        hoverLayer.backgroundColor = hoverBackgroundColor.cgColor
        animateHoverLayer(opacity: isHovering || isWorkspaceSelected ? 1 : 0)
    }

    private var hoverBackgroundColor: NSColor {
        if isWorkspaceSelected {
            return FrameHUDChrome.selectedFill
        }

        return FrameHUDChrome.hoverFill
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

private final class ImageWorkspaceImageView: ImageWorkspaceContextMenuView, ImageWorkspaceZoomableImageSurfaceForTesting {
    private let image: NSImage
    private let imageZoom: ImageWorkspaceImageZoom

    init(
        image: NSImage,
        imageZoom: ImageWorkspaceImageZoom = ImageWorkspaceImageZoom()
    ) {
        self.image = image
        self.imageZoom = imageZoom
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var lastDrawRectForTesting: CGRect {
        drawRectForCurrentBounds()
    }

    override func magnify(with event: NSEvent) {
        if imageZoom.applyMagnification(event.magnification, imageSize: image.size, bounds: bounds) {
            needsDisplay = true
        }
    }

    override func scrollWheel(with event: NSEvent) {
        if imageZoom.applyScroll(
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            imageSize: image.size,
            bounds: bounds
        ) {
            needsDisplay = true
            return
        }

        super.scrollWheel(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let drawRect = drawRectForCurrentBounds()

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private func drawRectForCurrentBounds() -> CGRect {
        imageZoom.drawRect(imageSize: image.size, in: bounds)
    }
}
