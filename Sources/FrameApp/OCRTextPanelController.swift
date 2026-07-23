import AppKit
import FrameCore

@MainActor
final class OCRTextPanelController: NSObject {
    private var panelItems: [OCRTextPanelItem] = []
    private weak var activeScrubPanel: NSPanel?

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
            existingItem.selectionAnchorCutID = nil
            update(existingItem, strings: strings)
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
        panel.contentView = makeContentView(strings: strings, item: item)
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

    func selectCutButtonsForTesting(_ buttons: [NSButton], in panel: NSPanel) {
        guard let item = panelItem(for: panel) else {
            return
        }

        let cutIDs: [UUID] = buttons.compactMap { button in
            guard let cutButton = button as? OCRCutButton,
                  cutButton.window === panel else {
                return nil
            }

            return cutButton.cutID
        }
        item.selectedCutIDs = Set(cutIDs)
        item.selectionAnchorCutID = cutIDs.last
        refreshSelection(in: item)
    }

    func shiftSelectCutButtonForTesting(_ button: NSButton, in panel: NSPanel) {
        guard let cutButton = button as? OCRCutButton,
              cutButton.window === panel else {
            return
        }

        _ = extendSelection(to: cutButton)
    }

    func beginScrubSelectionForTesting(from button: NSButton, in panel: NSPanel) {
        guard let cutButton = button as? OCRCutButton,
              cutButton.window === panel else {
            return
        }

        _ = beginScrub(from: cutButton)
    }

    func continueScrubSelectionForTesting(through button: NSButton, in panel: NSPanel) {
        guard let cutButton = button as? OCRCutButton,
              cutButton.window === panel else {
            return
        }

        _ = continueScrub(through: cutButton)
    }

    func continueScrubSelectionForTesting(atWindowPoint point: NSPoint, in panel: NSPanel) {
        _ = continueScrub(atWindowPoint: point, in: panel)
    }

    func endScrubSelectionForTesting() {
        endScrub()
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

    private func makeContentView(strings: AppStrings, item: OCRTextPanelItem) -> NSView {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = OCRCutScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.documentView = makeCutContainer(for: item)

        let selectAllButton = NSButton(title: strings.ocrSelectAll, target: self, action: #selector(selectAllButtonClicked))
        selectAllButton.translatesAutoresizingMaskIntoConstraints = false
        selectAllButton.bezelStyle = .rounded
        selectAllButton.setAccessibilityLabel(strings.ocrSelectAll)
        item.selectAllButton = selectAllButton
        item.selectAllTitle = strings.ocrSelectAll
        item.deselectAllTitle = strings.ocrDeselectAll

        let copyButton = NSButton(title: strings.ocrCopySelected, target: self, action: #selector(copySelectedButtonClicked))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .rounded
        copyButton.setAccessibilityLabel(strings.ocrCopySelected)
        copyButton.isEnabled = false
        item.copyButton = copyButton

        let copyAllButton = NSButton(title: strings.ocrCopyAll, target: self, action: #selector(copyAllButtonClicked))
        copyAllButton.translatesAutoresizingMaskIntoConstraints = false
        copyAllButton.bezelStyle = .rounded
        copyAllButton.setAccessibilityLabel(strings.ocrCopyAll)

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
        footerStack.addArrangedSubview(copyAllButton)

        contentView.addSubview(scrollView)
        contentView.addSubview(footerStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: footerStack.topAnchor, constant: -12),

            footerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            footerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            footerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        return contentView
    }

    private func makeCutContainer(for item: OCRTextPanelItem) -> NSView {
        let stackView = OCRCutContainerView()
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.rowSpacing = 6
        stackView.itemSpacing = 4

        for row in item.cutLayout.rows {
            stackView.addCutRow(row.cuts.map(makeCutButton))
        }

        stackView.updateLayout(for: 1)
        return stackView
    }

    private func makeCutButton(_ cut: RecognizedTextCut) -> OCRCutButton {
        let button = OCRCutButton(cutID: cut.id)
        button.title = cut.text
        button.target = self
        button.action = #selector(cutButtonClicked)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.font = .systemFont(ofSize: 13, weight: .regular)
        button.layer?.cornerRadius = 4
        button.layer?.masksToBounds = true
        button.setAccessibilityLabel("OCR Cut \(cut.text)")
        applyCutButtonStyle(button, isSelected: false)
        return button
    }

    private func update(_ item: OCRTextPanelItem, strings: AppStrings) {
        item.panel.contentView = makeContentView(strings: strings, item: item)
    }

    private func installLifecycleCallbacks(for item: OCRTextPanelItem) {
        item.panel.onSelectAll = { [weak self, weak item] in
            guard let self,
                  let item else {
                return false
            }

            self.selectAllCuts(in: item)
            return true
        }

        item.panel.onClose = { [weak self, weak item] in
            guard let item else {
                return
            }

            self?.removePanel(item)
        }
    }

    private func removePanel(_ item: OCRTextPanelItem) {
        if activeScrubPanel === item.panel {
            endScrub()
        }

        item.panel.onClose = nil
        item.panel.onSelectAll = nil
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

    private func panelItem(for panel: NSPanel) -> OCRTextPanelItem? {
        panelItems.first { $0.panel === panel }
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
        let isAllSelected = !item.cutLayout.allCutIDs.isEmpty && item.selectedCutIDs == item.cutLayout.allCutIDs
        item.selectAllButton?.title = isAllSelected ? item.deselectAllTitle : item.selectAllTitle
        item.selectAllButton?.setAccessibilityLabel(isAllSelected ? item.deselectAllTitle : item.selectAllTitle)
    }

    private func applyCutButtonStyle(_ button: OCRCutButton, isSelected: Bool) {
        button.applyStyle(isSelected: isSelected)
    }

    @objc private func cutButtonClicked(_ sender: OCRCutButton) {
        if sender.consumeSuppressesNextAction() {
            return
        }

        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true,
           extendSelection(to: sender) {
            return
        }

        guard let item = panelItem(for: sender.window) else {
            return
        }

        if item.selectedCutIDs.contains(sender.cutID) {
            item.selectedCutIDs.remove(sender.cutID)
            if item.selectionAnchorCutID == sender.cutID {
                item.selectionAnchorCutID = orderedCuts(in: item).last { item.selectedCutIDs.contains($0.id) }?.id
            }
        } else {
            item.selectedCutIDs.insert(sender.cutID)
            item.selectionAnchorCutID = sender.cutID
        }

        refreshSelection(in: item)
    }

    fileprivate func beginScrub(from sender: OCRCutButton) -> Bool {
        guard let item = panelItem(for: sender.window) else {
            return false
        }

        activeScrubPanel = item.panel
        return selectCutIfNeeded(sender, in: item)
    }

    fileprivate func continueScrub(through sender: OCRCutButton) -> Bool {
        guard let item = panelItem(for: sender.window),
              activeScrubPanel === item.panel else {
            return false
        }

        return selectCutIfNeeded(sender, in: item)
    }

    fileprivate func continueScrub(atWindowPoint point: NSPoint, in panel: NSPanel?) -> Bool {
        guard let panel,
              activeScrubPanel === panel,
              let item = panelItem(for: panel),
              let contentView = panel.contentView,
              let button = cutButton(atWindowPoint: point, in: contentView) else {
            return false
        }

        return selectCutIfNeeded(button, in: item)
    }

    fileprivate func endScrub() {
        activeScrubPanel = nil
    }

    fileprivate func extendSelection(to sender: OCRCutButton) -> Bool {
        guard let item = panelItem(for: sender.window) else {
            return false
        }

        let cuts = orderedCuts(in: item)
        guard let targetIndex = cuts.firstIndex(where: { $0.id == sender.cutID }) else {
            return false
        }

        if let anchorCutID = item.selectionAnchorCutID,
           let anchorIndex = cuts.firstIndex(where: { $0.id == anchorCutID }) {
            let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
            item.selectedCutIDs.formUnion(cuts[bounds].map(\.id))
        } else {
            item.selectedCutIDs.insert(sender.cutID)
        }

        item.selectionAnchorCutID = sender.cutID
        refreshSelection(in: item)
        return true
    }

    private func selectCutIfNeeded(_ sender: OCRCutButton, in item: OCRTextPanelItem) -> Bool {
        guard !item.selectedCutIDs.contains(sender.cutID) else {
            return false
        }

        item.selectedCutIDs.insert(sender.cutID)
        item.selectionAnchorCutID = sender.cutID
        refreshSelection(in: item)
        return true
    }

    private func orderedCuts(in item: OCRTextPanelItem) -> [RecognizedTextCut] {
        item.cutLayout.rows.flatMap(\.cuts)
    }

    private func cutButton(atWindowPoint point: NSPoint, in view: NSView) -> OCRCutButton? {
        for button in findCutButtons(in: view) {
            let localPoint = button.convert(point, from: nil)
            if button.bounds.contains(localPoint) {
                return button
            }
        }

        return nil
    }

    @objc private func selectAllButtonClicked(_ sender: NSButton) {
        guard let item = panelItem(for: sender.window) else {
            return
        }

        toggleAllCuts(in: item)
    }

    private func toggleAllCuts(in item: OCRTextPanelItem) {
        if item.selectedCutIDs == item.cutLayout.allCutIDs {
            item.selectedCutIDs = []
            item.selectionAnchorCutID = nil
            refreshSelection(in: item)
        } else {
            selectAllCuts(in: item)
        }
    }

    private func selectAllCuts(in item: OCRTextPanelItem) {
        item.selectedCutIDs = item.cutLayout.allCutIDs
        item.selectionAnchorCutID = orderedCuts(in: item).last?.id
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

    @objc private func copyAllButtonClicked(_ sender: NSButton) {
        guard let item = panelItem(for: sender.window) else {
            return
        }

        let text = item.cutLayout.selectedText(for: item.cutLayout.allCutIDs)
        guard !text.isEmpty else {
            return
        }

        _ = item.copyText(text)
    }
}

@MainActor
private final class OCRTextPanel: NSPanel {
    var onClose: (() -> Void)?
    var onSelectAll: (() -> Bool)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "a",
           onSelectAll?() == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }

    override func close() {
        let closeHandler = onClose
        onClose = nil
        onSelectAll = nil
        closeHandler?()
        super.close()
    }
}

private final class OCRTextPanelItem {
    let panel: OCRTextPanel
    let screenshotID: UUID
    var cutLayout: RecognizedTextCutLayout
    var selectedCutIDs: Set<UUID> = []
    var selectionAnchorCutID: UUID?
    var copyText: (String) -> Bool
    weak var selectAllButton: NSButton?
    weak var copyButton: NSButton?
    var selectAllTitle = ""
    var deselectAllTitle = ""

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

@MainActor
private final class OCRCutButton: NSButton {
    let cutID: UUID
    private var hoverTrackingArea: NSTrackingArea?
    private var suppressesNextAction = false
    private var isCutSelected = false

    init(cutID: UUID) {
        self.cutID = cutID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func applyStyle(isSelected: Bool) {
        isCutSelected = isSelected
        contentTintColor = isSelected ? .controlAccentColor : .labelColor
        updateLayerColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateLayerColors()
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.shift),
           let controller = target as? OCRTextPanelController,
           controller.extendSelection(to: self) {
            suppressesNextAction = true
            super.mouseDown(with: event)
            suppressesNextAction = false
            return
        }

        if let controller = target as? OCRTextPanelController,
           controller.beginScrub(from: self) {
            suppressesNextAction = true
        }

        super.mouseDown(with: event)
        (target as? OCRTextPanelController)?.endScrub()
        suppressesNextAction = false
    }

    override func mouseDragged(with event: NSEvent) {
        suppressesNextAction = true
        _ = (target as? OCRTextPanelController)?.continueScrub(
            atWindowPoint: event.locationInWindow,
            in: window as? NSPanel
        )
        super.mouseDragged(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        (target as? OCRTextPanelController)?.endScrub()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)

        guard let controller = target as? OCRTextPanelController else {
            return
        }

        _ = controller.continueScrub(through: self)
    }

    fileprivate func consumeSuppressesNextAction() -> Bool {
        let shouldSuppress = suppressesNextAction
        suppressesNextAction = false
        return shouldSuppress
    }

    private func updateLayerColors() {
        let backgroundColor = isCutSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.24)
            : NSColor.controlBackgroundColor
        let borderColor = isCutSelected
            ? NSColor.controlAccentColor.withAlphaComponent(0.7)
            : NSColor.separatorColor.withAlphaComponent(0.35)

        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = backgroundColor.cgColor
            layer?.borderColor = borderColor.cgColor
        }
        layer?.borderWidth = 1
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 8, height: max(24, size.height + 4))
    }
}

private final class OCRCutScrollView: NSScrollView {
    override func layout() {
        super.layout()

        guard let container = documentView as? OCRCutContainerView else {
            return
        }

        container.updateLayout(for: max(1, contentView.bounds.width))
    }
}

private final class OCRCutContainerView: NSView {
    var edgeInsets = NSEdgeInsetsZero
    var rowSpacing: CGFloat = 10
    var itemSpacing: CGFloat = 6

    private var cutRows: [[OCRCutButton]] = []

    override var isFlipped: Bool {
        true
    }

    func addCutRow(_ buttons: [OCRCutButton]) {
        cutRows.append(buttons)
        buttons.forEach(addSubview)
    }

    func updateLayout(for width: CGFloat) {
        let contentWidth = max(1, width)
        let maxLineWidth = max(1, contentWidth - edgeInsets.left - edgeInsets.right)
        var cursorY = edgeInsets.top
        var didPlaceAnyLine = false

        for cutRow in cutRows {
            var cursorX = edgeInsets.left
            var lineHeight: CGFloat = 0
            var didPlaceInCurrentLine = false
            var didPlaceInRow = false

            func advanceLine() {
                guard didPlaceInCurrentLine else {
                    return
                }

                cursorY += lineHeight + rowSpacing
                cursorX = edgeInsets.left
                lineHeight = 0
                didPlaceInCurrentLine = false
                didPlaceAnyLine = true
            }

            for button in cutRow {
                let size = button.intrinsicContentSize
                let nextX = didPlaceInCurrentLine ? cursorX + itemSpacing : cursorX
                if didPlaceInCurrentLine,
                   nextX + size.width > edgeInsets.left + maxLineWidth {
                    advanceLine()
                }

                let placedX = didPlaceInCurrentLine ? cursorX + itemSpacing : cursorX
                button.frame = NSRect(
                    x: placedX,
                    y: cursorY,
                    width: min(size.width, maxLineWidth),
                    height: size.height
                )
                cursorX = placedX + min(size.width, maxLineWidth)
                lineHeight = max(lineHeight, size.height)
                didPlaceInCurrentLine = true
                didPlaceInRow = true
            }

            if didPlaceInRow {
                advanceLine()
            }
        }

        let contentHeight = didPlaceAnyLine ? cursorY - rowSpacing + edgeInsets.bottom : edgeInsets.top + edgeInsets.bottom
        setFrameSize(NSSize(width: contentWidth, height: max(1, contentHeight)))
    }
}
