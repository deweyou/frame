import AppKit

enum CaptureHistoryFilter: Int, CaseIterable {
    case all
    case screenshots
    case recordings

    var kind: CaptureHistoryKind? {
        switch self {
        case .all:
            nil
        case .screenshots:
            .screenshot
        case .recordings:
            .recording
        }
    }
}

@MainActor
final class CaptureHistoryWindowController: NSObject {
    private let store: CaptureHistoryStore
    private let restore: (CaptureHistoryRecord) -> Void
    private let copy: (CaptureHistoryRecord) -> Void
    private let save: (CaptureHistoryRecord) -> Void
    private let delete: (CaptureHistoryRecord) -> Void
    private var window: NSWindow?
    private var gridView: CaptureHistoryGridView?
    private var emptyLabel: NSTextField?
    private var filterControl: CaptureHistoryFilterControl?
    private var tileViewsByRecordID: [UUID: CaptureHistoryTileView] = [:]
    private var activeHoverRecordID: UUID?
    private var records: [CaptureHistoryRecord] = []
    private var strings = AppStrings.current()

    private(set) var selectedFilter: CaptureHistoryFilter = .all

    init(
        store: CaptureHistoryStore,
        restore: @escaping (CaptureHistoryRecord) -> Void = { _ in },
        copy: @escaping (CaptureHistoryRecord) -> Void = { _ in },
        save: @escaping (CaptureHistoryRecord) -> Void = { _ in },
        delete: @escaping (CaptureHistoryRecord) -> Void = { _ in }
    ) {
        self.store = store
        self.restore = restore
        self.copy = copy
        self.save = save
        self.delete = delete
        super.init()
    }

    var isWindowVisible: Bool {
        window?.isVisible == true
    }

    var usesTransparentTitlebar: Bool {
        window?.titlebarAppearsTransparent == true
    }

    func show(strings: AppStrings) {
        self.strings = strings
        reloadRecords()

        if let window {
            window.title = strings.captureHistoryTitle
            reloadGrid()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = strings.captureHistoryTitle
        window.minSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.contentView = makeContentView()
        window.center()
        self.window = window

        reloadGrid()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.makeFirstResponder(nil)
        window?.contentView = nil
        window?.orderOut(nil)
        window?.close()
        window = nil
        gridView = nil
        emptyLabel = nil
        filterControl = nil
        tileViewsByRecordID = [:]
        activeHoverRecordID = nil
    }

    func setFilter(_ filter: CaptureHistoryFilter) {
        selectedFilter = filter
        filterControl?.selectedFilter = filter
        reloadRecords()
        reloadGrid()
    }

    func visibleRecords() -> [CaptureHistoryRecord] {
        records
    }

    func visibleColumnIdentifiers() -> [NSUserInterfaceItemIdentifier] {
        []
    }

    func visibleTileCount() -> Int {
        tileViewsByRecordID.count
    }

    func areActionsVisible(for record: CaptureHistoryRecord) -> Bool {
        tileViewsByRecordID[record.id]?.areActionsVisible == true
    }

    func setActionsVisible(_ isVisible: Bool, for record: CaptureHistoryRecord) {
        setActionsVisible(isVisible, forRecordID: record.id)
    }

    func visibleActionButtons() -> [NSButton] {
        tileViewsByRecordID.values.flatMap(\.actionButtons)
    }

    func actionButtonFrame(title: String, for record: CaptureHistoryRecord) -> NSRect? {
        tileViewsByRecordID[record.id]?.actionButtonFrame(title: title)
    }

    func previewFrame(for record: CaptureHistoryRecord) -> NSRect? {
        window?.contentView?.layoutSubtreeIfNeeded()
        guard let tileView = tileViewsByRecordID[record.id] else {
            return nil
        }

        tileView.layoutSubtreeIfNeeded()
        return tileView.previewFrame()
    }

    func tileShadowOpacity(for record: CaptureHistoryRecord) -> Float? {
        tileViewsByRecordID[record.id]?.shadowOpacity
    }

    func tileBackgroundAlpha(for record: CaptureHistoryRecord) -> CGFloat? {
        tileViewsByRecordID[record.id]?.backgroundAlpha
    }

    func tileShadowBounds(for record: CaptureHistoryRecord) -> CGRect? {
        tileViewsByRecordID[record.id]?.shadowBounds
    }

    func restoreRecord(_ record: CaptureHistoryRecord) {
        restore(record)
    }

    func copyRecord(_ record: CaptureHistoryRecord) {
        copy(record)
    }

    func saveRecord(_ record: CaptureHistoryRecord) {
        save(record)
    }

    func deleteRecord(_ record: CaptureHistoryRecord) {
        delete(record)
        reloadRecords()
        reloadGrid()
    }

    private func makeContentView() -> NSView {
        let materialView = NSVisualEffectView()
        materialView.material = .windowBackground
        materialView.blendingMode = .behindWindow
        materialView.state = .active

        let filterControl = CaptureHistoryFilterControl(strings: strings)
        filterControl.selectedFilter = selectedFilter
        filterControl.onSelectionChange = { [weak self] filter in
            self?.setFilter(filter)
        }
        filterControl.translatesAutoresizingMaskIntoConstraints = false
        self.filterControl = filterControl

        let toolbarView = NSView()
        toolbarView.translatesAutoresizingMaskIntoConstraints = false
        toolbarView.addSubview(filterControl)

        let gridView = CaptureHistoryGridView()
        gridView.translatesAutoresizingMaskIntoConstraints = false
        self.gridView = gridView

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = gridView

        let emptyLabel = NSTextField(labelWithString: strings.captureHistoryEmpty)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.font = .systemFont(ofSize: 13, weight: .medium)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        self.emptyLabel = emptyLabel

        materialView.addSubview(toolbarView)
        materialView.addSubview(scrollView)
        materialView.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            toolbarView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            toolbarView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            toolbarView.topAnchor.constraint(equalTo: materialView.topAnchor),
            toolbarView.heightAnchor.constraint(equalToConstant: 58),

            filterControl.trailingAnchor.constraint(equalTo: toolbarView.trailingAnchor, constant: -18),
            filterControl.centerYAnchor.constraint(equalTo: toolbarView.centerYAnchor, constant: 6),
            filterControl.heightAnchor.constraint(equalToConstant: 32),

            scrollView.leadingAnchor.constraint(equalTo: materialView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: materialView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: toolbarView.bottomAnchor),
            scrollView.bottomAnchor.constraint(equalTo: materialView.bottomAnchor),

            gridView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            gridView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            gridView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            gridView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: materialView.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: materialView.trailingAnchor, constant: -24),
        ])

        return materialView
    }

    private func reloadGrid() {
        tileViewsByRecordID = [:]
        activeHoverRecordID = nil
        let tileViews = records.map { record in
            let tileView = CaptureHistoryTileView(
                record: record,
                image: previewImage(for: record),
                metadata: metadataText(for: record),
                strings: strings
            )
            tileView.onRestore = { [weak self] record in self?.restoreRecord(record) }
            tileView.onCopy = { [weak self] record in self?.copyRecord(record) }
            tileView.onSave = { [weak self] record in self?.saveRecord(record) }
            tileView.onDelete = { [weak self] record in self?.deleteRecord(record) }
            tileView.onHoverChanged = { [weak self] record, isHovered in
                self?.setActionsVisible(isHovered, forRecordID: record.id)
            }
            tileViewsByRecordID[record.id] = tileView
            return tileView
        }

        gridView?.setTileViews(tileViews)
        emptyLabel?.isHidden = !records.isEmpty
    }

    private func reloadRecords() {
        records = (try? store.records(kind: selectedFilter.kind)) ?? []
    }

    private func previewImage(for record: CaptureHistoryRecord) -> NSImage {
        if record.kind == .screenshot,
           let data = try? store.data(for: record),
           let image = NSImage(data: data) {
            return image
        }

        return NSImage(systemSymbolName: "video", accessibilityDescription: kindTitle(for: record.kind)) ?? NSImage()
    }

    private func metadataText(for record: CaptureHistoryRecord) -> String {
        let size = ByteCountFormatter.string(fromByteCount: Int64(record.byteSize), countStyle: .file)
        let dimensions = "\(record.pixelWidth) x \(record.pixelHeight)"
        return "\(record.createdAt.formatted(date: .abbreviated, time: .shortened)) | \(dimensions) | \(size)"
    }

    private func kindTitle(for kind: CaptureHistoryKind) -> String {
        switch kind {
        case .screenshot:
            strings.captureHistoryKindScreenshot
        case .recording:
            strings.captureHistoryKindRecording
        }
    }

    private func setActionsVisible(_ isVisible: Bool, forRecordID recordID: UUID) {
        if isVisible {
            activeHoverRecordID = recordID
        } else if activeHoverRecordID == recordID {
            activeHoverRecordID = nil
        }

        for (tileRecordID, tileView) in tileViewsByRecordID {
            tileView.setActionsVisible(tileRecordID == activeHoverRecordID)
        }
    }
}

private final class CaptureHistoryFilterControl: NSVisualEffectView {
    private enum Metrics {
        static let horizontalInset: CGFloat = 3
        static let verticalInset: CGFloat = 3
        static let stackSpacing: CGFloat = 2
    }

    var onSelectionChange: ((CaptureHistoryFilter) -> Void)?
    var selectedFilter: CaptureHistoryFilter = .all {
        didSet {
            updateSelection()
        }
    }

    private var buttons: [CaptureHistoryFilterButton] = []

    init(strings: AppStrings) {
        super.init(frame: .zero)
        setAccessibilityLabel("Capture History Filter")
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        alphaValue = 1
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.spacing = Metrics.stackSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        let items: [(CaptureHistoryFilter, String)] = [
            (.all, strings.captureHistoryFilterAll),
            (.screenshots, strings.captureHistoryFilterScreenshots),
            (.recordings, strings.captureHistoryFilterRecordings),
        ]

        buttons = items.map { filter, title in
            let button = CaptureHistoryFilterButton(title: title, filter: filter)
            button.target = self
            button.action = #selector(filterButtonClicked(_:))
            stackView.addArrangedSubview(button)
            button.heightAnchor.constraint(equalToConstant: 26).isActive = true
            return button
        }

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Metrics.horizontalInset),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Metrics.horizontalInset),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Metrics.verticalInset),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Metrics.verticalInset),
        ])

        updateSelection()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let buttonsWidth = buttons.reduce(CGFloat.zero) { width, button in
            width + button.intrinsicContentSize.width
        }
        let spacing = Metrics.stackSpacing * CGFloat(max(0, buttons.count - 1))
        return NSSize(width: buttonsWidth + spacing + Metrics.horizontalInset * 2, height: 32)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
    }

    @objc private func filterButtonClicked(_ sender: CaptureHistoryFilterButton) {
        selectedFilter = sender.filter
        onSelectionChange?(sender.filter)
    }

    private func updateSelection() {
        for button in buttons {
            button.isFilterSelected = button.filter == selectedFilter
        }
    }
}

private final class CaptureHistoryFilterButton: NSButton {
    private enum Metrics {
        static let horizontalPadding: CGFloat = 16
        static let minimumWidth: CGFloat = 40
    }

    let filter: CaptureHistoryFilter

    private let hoverLayer = CALayer()
    private var trackingArea: NSTrackingArea?
    private var isHovering = false {
        didSet {
            updateAppearance()
        }
    }
    var isFilterSelected = false {
        didSet {
            updateAppearance()
        }
    }

    init(title: String, filter: CaptureHistoryFilter) {
        self.filter = filter
        super.init(frame: .zero)
        self.title = title
        configure()
        updateAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = title.size(withAttributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold)]).width
        return NSSize(width: max(Metrics.minimumWidth, ceil(textWidth) + Metrics.horizontalPadding), height: 26)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        hoverLayer.frame = bounds
        hoverLayer.cornerRadius = bounds.height / 2
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

    private func configure() {
        isBordered = false
        bezelStyle = .regularSquare
        setButtonType(.momentaryPushIn)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.masksToBounds = false
        hoverLayer.opacity = 0
        layer?.insertSublayer(hoverLayer, at: 0)
    }

    private func updateAppearance() {
        hoverLayer.backgroundColor = backgroundColor.cgColor
        hoverLayer.opacity = isFilterSelected || isHovering ? 1 : 0
        let textColor = isFilterSelected ? NSColor.controlAccentColor : NSColor.labelColor
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: textColor,
            ]
        )
    }

    private var backgroundColor: NSColor {
        if isFilterSelected {
            return NSColor.controlAccentColor.withAlphaComponent(0.18)
        }

        return NSColor.labelColor.withAlphaComponent(0.08)
    }
}

private final class CaptureHistoryGridView: NSView {
    private var tileViews: [CaptureHistoryTileView] = []
    private let contentInsets = NSEdgeInsets(top: 14, left: 18, bottom: 22, right: 18)
    private let horizontalSpacing: CGFloat = 14
    private let verticalSpacing: CGFloat = 22
    private let minTileWidth: CGFloat = 200
    private let maxTileWidth: CGFloat = 260
    private let metadataHeight: CGFloat = 18
    private var previewAspectRatio: CGFloat {
        CapturePreviewMetrics.desktopAspectRatio()
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: requiredHeight(for: bounds.width))
    }

    func setTileViews(_ tileViews: [CaptureHistoryTileView]) {
        for subview in self.tileViews {
            subview.removeFromSuperview()
        }

        self.tileViews = tileViews
        for tileView in tileViews {
            addSubview(tileView)
        }

        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard !tileViews.isEmpty else {
            frame.size.height = contentInsets.top + contentInsets.bottom
            return
        }

        let metrics = layoutMetrics(for: bounds.width)
        for (index, tileView) in tileViews.enumerated() {
            let row = index / metrics.columns
            let column = index % metrics.columns
            let x = contentInsets.left + CGFloat(column) * (metrics.tileWidth + horizontalSpacing)
            let y = contentInsets.top + CGFloat(row) * (metrics.tileHeight + verticalSpacing)
            tileView.frame = NSRect(x: x, y: y, width: metrics.tileWidth, height: metrics.tileHeight)
        }

        frame.size.height = requiredHeight(for: bounds.width)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        postsFrameChangedNotifications = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        invalidateIntrinsicContentSize()
    }

    private func requiredHeight(for width: CGFloat) -> CGFloat {
        guard !tileViews.isEmpty else {
            return contentInsets.top + contentInsets.bottom
        }

        let metrics = layoutMetrics(for: width)
        let rowCount = Int(ceil(Double(tileViews.count) / Double(metrics.columns)))
        return contentInsets.top
            + CGFloat(rowCount) * metrics.tileHeight
            + CGFloat(max(0, rowCount - 1)) * verticalSpacing
            + contentInsets.bottom
    }

    private func layoutMetrics(for width: CGFloat) -> LayoutMetrics {
        let availableWidth = max(minTileWidth, width - contentInsets.left - contentInsets.right)
        let possibleColumns = max(1, Int((availableWidth + horizontalSpacing) / (minTileWidth + horizontalSpacing)))
        let columns = max(1, possibleColumns)
        let unconstrainedTileWidth = (availableWidth - CGFloat(columns - 1) * horizontalSpacing) / CGFloat(columns)
        let tileWidth = min(maxTileWidth, max(minTileWidth, floor(unconstrainedTileWidth)))
        let previewHeight = floor(tileWidth * previewAspectRatio)
        return LayoutMetrics(columns: columns, tileWidth: tileWidth, tileHeight: previewHeight + metadataHeight + 6)
    }

    private struct LayoutMetrics {
        let columns: Int
        let tileWidth: CGFloat
        let tileHeight: CGFloat
    }
}

private final class CaptureHistoryTileView: NSView {
    let record: CaptureHistoryRecord
    private let previewShadowView = NSView()
    private let imageView: CaptureHistoryPreviewImageView
    private let actionsView: NSVisualEffectView
    private let deleteActionView: NSVisualEffectView
    private let imageHeightConstraint: NSLayoutConstraint
    private var trackingArea: NSTrackingArea?
    private var buttons: [NSButton] = []
    private var currentBackgroundAlpha: CGFloat = 0.18
    private var currentShadowOpacity: Float = 0.12
    private var currentShadowRadius: CGFloat = 8
    private var currentShadowOffset = CGSize(width: 0, height: -3)

    var onRestore: ((CaptureHistoryRecord) -> Void)?
    var onCopy: ((CaptureHistoryRecord) -> Void)?
    var onSave: ((CaptureHistoryRecord) -> Void)?
    var onDelete: ((CaptureHistoryRecord) -> Void)?
    var onHoverChanged: ((CaptureHistoryRecord, Bool) -> Void)?

    var areActionsVisible: Bool {
        actionsView.alphaValue > 0
    }

    var actionButtons: [NSButton] {
        buttons
    }

    var shadowOpacity: Float {
        currentShadowOpacity
    }

    var backgroundAlpha: CGFloat {
        currentBackgroundAlpha
    }

    var shadowBounds: CGRect {
        previewShadowView.layoutSubtreeIfNeeded()
        return previewShadowView.layer?.shadowPath?.boundingBoxOfPath ?? previewShadowView.bounds
    }

    func actionButtonFrame(title: String) -> NSRect? {
        guard let button = buttons.first(where: { $0.toolTip == title }) else {
            return nil
        }

        layoutSubtreeIfNeeded()
        return button.convert(button.bounds, to: self)
    }

    func previewFrame() -> NSRect {
        layoutSubtreeIfNeeded()
        return previewShadowView.frame
    }

    init(record: CaptureHistoryRecord, image: NSImage, metadata: String, strings: AppStrings) {
        self.record = record
        imageView = CaptureHistoryPreviewImageView(image: image)
        actionsView = NSVisualEffectView()
        deleteActionView = NSVisualEffectView()
        imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: 0)
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        previewShadowView.translatesAutoresizingMaskIntoConstraints = false
        previewShadowView.wantsLayer = true
        previewShadowView.layer?.cornerRadius = 12
        previewShadowView.layer?.cornerCurve = .continuous
        previewShadowView.layer?.masksToBounds = false
        previewShadowView.layer?.shadowColor = NSColor.black.cgColor
        previewShadowView.layer?.shadowRadius = 8
        previewShadowView.layer?.shadowOffset = CGSize(width: 0, height: -3)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        applyHoverAppearance(false)

        actionsView.material = .hudWindow
        actionsView.blendingMode = .withinWindow
        actionsView.state = .active
        actionsView.translatesAutoresizingMaskIntoConstraints = false
        actionsView.wantsLayer = true
        actionsView.layer?.cornerRadius = 14
        actionsView.layer?.cornerCurve = .continuous
        actionsView.layer?.masksToBounds = true
        actionsView.alphaValue = 0

        deleteActionView.material = .hudWindow
        deleteActionView.blendingMode = .withinWindow
        deleteActionView.state = .active
        deleteActionView.translatesAutoresizingMaskIntoConstraints = false
        deleteActionView.wantsLayer = true
        deleteActionView.layer?.cornerRadius = 12
        deleteActionView.layer?.cornerCurve = .continuous
        deleteActionView.layer?.masksToBounds = true
        deleteActionView.alphaValue = 0

        let actionsStack = NSStackView()
        actionsStack.orientation = .horizontal
        actionsStack.alignment = .centerY
        actionsStack.distribution = .fillEqually
        actionsStack.spacing = 5
        actionsStack.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = makeIconButton(title: strings.quickAccessSave, symbolName: "square.and.arrow.down") { [weak self] in
            guard let self else { return }
            self.onSave?(self.record)
        }
        let copyButton = makeIconButton(title: strings.quickAccessCopy, symbolName: "doc.on.doc") { [weak self] in
            guard let self else { return }
            self.onCopy?(self.record)
        }
        let restoreButton = makeIconButton(title: strings.captureHistoryRestore, symbolName: "arrow.uturn.backward") { [weak self] in
            guard let self else { return }
            self.onRestore?(self.record)
        }
        let deleteButton = makeIconButton(title: strings.captureHistoryDelete, symbolName: "trash") { [weak self] in
            guard let self else { return }
            self.onDelete?(self.record)
        }
        buttons = [saveButton, copyButton, restoreButton, deleteButton]
        for button in [saveButton, copyButton, restoreButton] {
            actionsStack.addArrangedSubview(button)
        }

        let metadataLabel = NSTextField(labelWithString: metadata)
        metadataLabel.translatesAutoresizingMaskIntoConstraints = false
        metadataLabel.font = .systemFont(ofSize: 11, weight: .regular)
        metadataLabel.textColor = .secondaryLabelColor
        metadataLabel.lineBreakMode = .byTruncatingTail
        metadataLabel.maximumNumberOfLines = 1

        addSubview(previewShadowView)
        addSubview(metadataLabel)
        previewShadowView.addSubview(imageView)
        imageView.addSubview(actionsView)
        imageView.addSubview(deleteActionView)
        actionsView.addSubview(actionsStack)
        deleteActionView.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            previewShadowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            previewShadowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            previewShadowView.topAnchor.constraint(equalTo: topAnchor),
            imageHeightConstraint,

            imageView.leadingAnchor.constraint(equalTo: previewShadowView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: previewShadowView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: previewShadowView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: previewShadowView.bottomAnchor),

            metadataLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            metadataLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            metadataLabel.topAnchor.constraint(equalTo: previewShadowView.bottomAnchor, constant: 6),

            actionsView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            actionsView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -7),
            actionsView.widthAnchor.constraint(equalToConstant: 96),
            actionsView.heightAnchor.constraint(equalToConstant: 28),

            actionsStack.leadingAnchor.constraint(equalTo: actionsView.leadingAnchor, constant: 7),
            actionsStack.trailingAnchor.constraint(equalTo: actionsView.trailingAnchor, constant: -7),
            actionsStack.topAnchor.constraint(equalTo: actionsView.topAnchor, constant: 4),
            actionsStack.bottomAnchor.constraint(equalTo: actionsView.bottomAnchor, constant: -4),

            deleteActionView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -7),
            deleteActionView.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 7),
            deleteActionView.widthAnchor.constraint(equalToConstant: 24),
            deleteActionView.heightAnchor.constraint(equalToConstant: 24),

            deleteButton.leadingAnchor.constraint(equalTo: deleteActionView.leadingAnchor, constant: 4),
            deleteButton.trailingAnchor.constraint(equalTo: deleteActionView.trailingAnchor, constant: -4),
            deleteButton.topAnchor.constraint(equalTo: deleteActionView.topAnchor, constant: 4),
            deleteButton.bottomAnchor.constraint(equalTo: deleteActionView.bottomAnchor, constant: -4),
        ])
    }

    override func layout() {
        imageHeightConstraint.constant = floor(bounds.width * CapturePreviewMetrics.desktopAspectRatio())
        super.layout()
        applyLayerAppearance()
        previewShadowView.layer?.shadowPath = CGPath(
            roundedRect: previewShadowView.bounds,
            cornerWidth: 12,
            cornerHeight: 12,
            transform: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(record, true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(record, false)
    }

    func setActionsVisible(_ isVisible: Bool) {
        actionsView.animator().alphaValue = isVisible ? 1 : 0
        deleteActionView.animator().alphaValue = isVisible ? 1 : 0
        applyHoverAppearance(isVisible)
    }

    private func applyHoverAppearance(_ isHovered: Bool) {
        currentBackgroundAlpha = isHovered ? 0.36 : 0.18
        currentShadowOpacity = isHovered ? 0.24 : 0.12
        currentShadowRadius = isHovered ? 12 : 8
        currentShadowOffset = CGSize(width: 0, height: isHovered ? -4 : -3)
        applyLayerAppearance()
    }

    private func applyLayerAppearance() {
        imageView.layer?.backgroundColor = NSColor.controlBackgroundColor
            .withAlphaComponent(currentBackgroundAlpha)
            .cgColor
        previewShadowView.layer?.shadowOpacity = currentShadowOpacity
        previewShadowView.layer?.shadowRadius = currentShadowRadius
        previewShadowView.layer?.shadowOffset = currentShadowOffset
    }

    private func makeIconButton(title: String, symbolName: String, action: @escaping () -> Void) -> NSButton {
        let button = CaptureHistoryActionButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(),
            action: action
        )
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10.5, weight: .semibold)
        button.contentTintColor = .labelColor
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}

private final class CaptureHistoryPreviewImageView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard image.size.width > 0, image.size.height > 0, bounds.width > 0, bounds.height > 0 else {
            return
        }

        let drawRect = CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: image.size,
            in: bounds
        )

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

private final class CaptureHistoryActionButton: NSButton {
    private let actionHandler: () -> Void
    private var trackingArea: NSTrackingArea?

    init(image: NSImage, action: @escaping () -> Void) {
        actionHandler = action
        super.init(frame: .zero)
        self.image = image
        target = self
        self.action = #selector(runAction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runAction() {
        actionHandler()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.pointingHand.set()
        super.mouseEntered(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
        super.mouseMoved(with: event)
    }
}
