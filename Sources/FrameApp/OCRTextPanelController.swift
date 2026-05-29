import AppKit
import FrameCore

@MainActor
final class OCRTextPanelController: NSObject {
    private var panelItems: [OCRTextPanelItem] = []

    func show(
        layout: RecognizedTextLayout,
        for screenshot: CapturedScreenshot,
        strings: AppStrings,
        copyText: @escaping (String) -> Bool
    ) {
        let cutLayout = RecognizedTextCutLayout(textLayout: layout)
        if let existingItem = panelItem(for: screenshot) {
            existingItem.copyText = copyText
            existingItem.cutLayout = cutLayout
            existingItem.selectedCutIDs = []
            update(existingItem, screenshot: screenshot, strings: strings)
            activatePanel(existingItem.panel)
            return
        }

        let panel = makePanel(title: strings.ocrPanelTitle)
        let item = OCRTextPanelItem(
            panel: panel,
            screenshotID: screenshot.id,
            cutLayout: cutLayout,
            copyText: copyText
        )
        panel.contentView = makeContentView(screenshot: screenshot, strings: strings, item: item)
        panelItems.append(item)
        installLifecycleCallbacks(for: item)
        activatePanel(panel)
    }

    func closePanel(for screenshot: CapturedScreenshot) -> Bool {
        guard let item = panelItem(for: screenshot) else {
            return false
        }

        item.panel.close()
        return true
    }

    private func activatePanel(_ panel: NSPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func makePanel(title: String) -> OCRTextPanel {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let contentSize = NSSize(
            width: min(520, max(360, visibleFrame.width * 0.42)),
            height: min(420, max(260, visibleFrame.height * 0.42))
        )
        let contentRect = NSRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        let panel = OCRTextPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 220)
        return panel
    }

    private func makeContentView(
        screenshot: CapturedScreenshot,
        strings: AppStrings,
        item: OCRTextPanelItem
    ) -> NSView {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(image: screenshot.image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
        imageView.setAccessibilityLabel("OCR Screenshot Preview")

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = makeCutContainer(for: item)

        let selectAllButton = NSButton(title: strings.ocrSelectAll, target: self, action: #selector(selectAllButtonClicked))
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false
        selectAllButton.bezelStyle = .rounded
        selectAllButton.setAccessibilityLabel(strings.ocrSelectAll)

        let copyButton = NSButton(title: strings.ocrCopySelected, target: self, action: #selector(copySelectedButtonClicked))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .rounded
        copyButton.setAccessibilityLabel(strings.ocrCopySelected)
        copyButton.isEnabled = false
        item.copyButton = copyButton

        let footerStack = NSStackView()
        footerStack.translatesAutoresizingMaskIntoConstraints = false
        footerStack.orientation = .horizontal
        footerStack.alignment = .centerY
        footerStack.spacing = 12

        let footerSpacer = NSView()
        footerSpacer.translatesAutoresizingMaskIntoConstraints = false
        footerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        footerStack.addArrangedSubview(selectAllButton)
        footerStack.addArrangedSubview(footerSpacer)
        footerStack.addArrangedSubview(copyButton)

        contentView.addSubview(imageView)
        contentView.addSubview(scrollView)
        contentView.addSubview(footerStack)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 180),
            imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 14),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            footerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        return contentView
    }

    private func makeCutContainer(for item: OCRTextPanelItem) -> NSView {
        let stackView = OCRCutContainerView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = true

        for row in item.cutLayout.rows {
            let rowStack = NSStackView()
            rowStack.orientation = .horizontal
            rowStack.alignment = .centerY
            rowStack.spacing = 4
            rowStack.translatesAutoresizingMaskIntoConstraints = false

            for cut in row.cuts {
                rowStack.addArrangedSubview(makeCutButton(cut))
            }

            stackView.addArrangedSubview(rowStack)
        }

        stackView.sizeToArrangedContent()
        return stackView
    }

    private func makeCutButton(_ cut: RecognizedTextCut) -> NSButton {
        let button = OCRCutButton(cutID: cut.id)
        button.title = cut.text
        button.target = self
        button.action = #selector(cutButtonClicked)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.setAccessibilityLabel("OCR Cut \(cut.text)")
        applyCutButtonStyle(button, isSelected: false)
        return button
    }

    private func update(_ item: OCRTextPanelItem, screenshot: CapturedScreenshot, strings: AppStrings) {
        item.panel.contentView = makeContentView(screenshot: screenshot, strings: strings, item: item)
    }

    private func installLifecycleCallbacks(for item: OCRTextPanelItem) {
        item.panel.onClose = { [weak self, weak item] in
            guard let item else {
                return
            }

            self?.removePanel(item)
        }
    }

    private func removePanel(_ item: OCRTextPanelItem) {
        item.panel.onClose = nil
        panelItems.removeAll { $0 === item }
    }

    private func panelItem(for screenshot: CapturedScreenshot) -> OCRTextPanelItem? {
        panelItems.first {
            $0.screenshotID == screenshot.id
        }
    }

    private func panelItem(for window: NSWindow?) -> OCRTextPanelItem? {
        guard let window else {
            return nil
        }

        return panelItems.first { $0.panel === window }
    }

    private func findCutButtons(in view: NSView) -> [OCRCutButton] {
        var buttons: [OCRCutButton] = []
        if let button = view as? OCRCutButton {
            buttons.append(button)
        }

        for subview in view.subviews {
            buttons.append(contentsOf: findCutButtons(in: subview))
        }

        if let scrollView = view as? NSScrollView,
           let documentView = scrollView.documentView {
            buttons.append(contentsOf: findCutButtons(in: documentView))
        }

        return buttons
    }

    private func refreshSelection(in item: OCRTextPanelItem) {
        guard let contentView = item.panel.contentView else {
            return
        }

        for button in findCutButtons(in: contentView) {
            applyCutButtonStyle(button, isSelected: item.selectedCutIDs.contains(button.cutID))
        }

        item.copyButton?.isEnabled = !item.selectedCutIDs.isEmpty
    }

    private func applyCutButtonStyle(_ button: OCRCutButton, isSelected: Bool) {
        button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
        button.layer?.backgroundColor = isSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
            : NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
    }

    @objc private func cutButtonClicked(_ sender: OCRCutButton) {
        guard let item = panelItem(for: sender.window) else {
            return
        }

        if item.selectedCutIDs.contains(sender.cutID) {
            item.selectedCutIDs.remove(sender.cutID)
        } else {
            item.selectedCutIDs.insert(sender.cutID)
        }

        refreshSelection(in: item)
    }

    @objc private func selectAllButtonClicked(_ sender: NSButton) {
        guard let item = panelItem(for: sender.window) else {
            return
        }

        item.selectedCutIDs = item.cutLayout.allCutIDs
        refreshSelection(in: item)
    }

    @objc private func copySelectedButtonClicked(_ sender: NSButton) {
        guard let item = panelItem(for: sender.window) else {
            return
        }

        let text = item.cutLayout.selectedText(for: item.selectedCutIDs)
        guard !text.isEmpty else {
            return
        }

        _ = item.copyText(text)
    }
}

@MainActor
private final class OCRTextPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func close() {
        let closeHandler = onClose
        onClose = nil
        closeHandler?()
        super.close()
    }
}

private final class OCRTextPanelItem {
    let panel: OCRTextPanel
    let screenshotID: UUID
    var cutLayout: RecognizedTextCutLayout
    var selectedCutIDs: Set<UUID> = []
    var copyText: (String) -> Bool
    weak var copyButton: NSButton?

    init(
        panel: OCRTextPanel,
        screenshotID: UUID,
        cutLayout: RecognizedTextCutLayout,
        copyText: @escaping (String) -> Bool
    ) {
        self.panel = panel
        self.screenshotID = screenshotID
        self.cutLayout = cutLayout
        self.copyText = copyText
    }
}

private final class OCRCutButton: NSButton {
    let cutID: UUID

    init(cutID: UUID) {
        self.cutID = cutID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}

private final class OCRCutContainerView: NSStackView {
    override func layout() {
        super.layout()
        sizeToArrangedContent()
    }

    func sizeToArrangedContent() {
        let size = fittingSize
        setFrameSize(NSSize(
            width: max(1, size.width),
            height: max(1, size.height)
        ))
    }
}
