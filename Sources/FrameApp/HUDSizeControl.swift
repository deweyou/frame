import AppKit
import FrameCore

@MainActor
final class HUDSizeControl: NSView, NSTextFieldDelegate {
    var onWidthCommit: ((Int) -> Void)?
    var onHeightCommit: ((Int) -> Void)?
    var onLockToggle: (() -> Void)?
    var onRatioPreset: ((SelectionAspectRatio) -> Void)?
    var onTooltipChange: ((String?, NSView?) -> Void)?

    private let widthField = HUDSizeTextField(string: "0")
    private let linkButton = HUDSizeButton()
    private let heightField = HUDSizeTextField(string: "0")
    private let menuButton = HUDSizeButton()
    private let ratioMenu = NSMenu()
    private var editingDimension: SelectionSizeDimension?
    private var editingOriginalValue = ""
    private var maximumWidth = 9999
    private var maximumHeight = 9999
    private var foregroundColor = NSColor.white
    private var isFinishingEditing = false
    private var ignoresNextEndEditing = false
    private var suppressesCommitAfterCancel = false
    private var lastWidthValue = "0"
    private var lastHeightValue = "0"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    var isEditingSize: Bool {
        activeEditingDimension != nil
    }

    func textForTesting() -> String {
        "\(widthField.stringValue) x \(heightField.stringValue)"
    }

    func update(
        width: Int,
        height: Int,
        maximumWidth: Int,
        maximumHeight: Int,
        isLocked: Bool,
        foregroundColor: NSColor
    ) {
        self.foregroundColor = foregroundColor
        self.maximumWidth = min(maximumWidth, 9999)
        self.maximumHeight = min(maximumHeight, 9999)
        lastWidthValue = "\(width)"
        lastHeightValue = "\(height)"

        if !isEditing(.width) {
            widthField.stringValue = "\(width)"
        }
        if !isEditing(.height) {
            heightField.stringValue = "\(height)"
        }

        linkButton.image = linkImage(isLocked: isLocked)
        [widthField, heightField].forEach { field in
            field.textColor = foregroundColor
        }
        [linkButton, menuButton].forEach { button in
            button.contentTintColor = foregroundColor
        }
        linkButton.alphaValue = isLocked ? 1 : 0.32
    }

    private func configure() {
        wantsLayer = true

        [widthField, heightField].forEach { field in
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            field.isEditable = true
            field.isSelectable = true
            field.focusRingType = .none
            field.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            field.alignment = .center
            field.lineBreakMode = .byClipping
            field.maximumNumberOfLines = 1
            field.delegate = self
            field.translatesAutoresizingMaskIntoConstraints = false
            addSubview(field)
        }

        widthField.identifier = NSUserInterfaceItemIdentifier("width")
        heightField.identifier = NSUserInterfaceItemIdentifier("height")

        linkButton.target = self
        linkButton.action = #selector(toggleLock)
        linkButton.identifier = NSUserInterfaceItemIdentifier("ratio-lock")
        linkButton.setAccessibilityLabel("锁定比例")
        linkButton.tooltipText = "锁定比例"
        linkButton.onHoverChange = { [weak self, weak linkButton] isHovering in
            self?.onTooltipChange?(isHovering ? "锁定比例" : nil, linkButton)
        }
        linkButton.isBordered = false
        linkButton.bezelStyle = .regularSquare
        linkButton.imagePosition = .imageOnly
        linkButton.imageScaling = .scaleProportionallyDown
        linkButton.setButtonType(.momentaryChange)
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(linkButton)

        configureMenu()

        NSLayoutConstraint.activate([
            widthField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            widthField.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthField.widthAnchor.constraint(equalToConstant: 34),

            linkButton.leadingAnchor.constraint(equalTo: widthField.trailingAnchor, constant: 3),
            linkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            linkButton.widthAnchor.constraint(equalToConstant: 17),
            linkButton.heightAnchor.constraint(equalToConstant: 30),

            heightField.leadingAnchor.constraint(equalTo: linkButton.trailingAnchor, constant: 3),
            heightField.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightField.widthAnchor.constraint(equalToConstant: 34),

            menuButton.leadingAnchor.constraint(equalTo: heightField.trailingAnchor, constant: 3),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 21),
            menuButton.heightAnchor.constraint(equalToConstant: 34),
        ])
    }

    private func configureMenu() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isBordered = false
        menuButton.identifier = NSUserInterfaceItemIdentifier("ratio-menu")
        menuButton.setAccessibilityLabel("比例预设")
        ratioMenu.title = "比例预设"
        setMenuIcon(isOpen: false, animated: false)
        menuButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .regular)
        menuButton.imagePosition = .imageOnly
        menuButton.imageScaling = .scaleProportionallyDown
        menuButton.bezelStyle = .regularSquare
        menuButton.setButtonType(.momentaryChange)
        menuButton.target = self
        menuButton.action = #selector(showRatioMenu)
        addRatioItem(title: "1:1", ratio: .square)
        addRatioItem(title: "4:3", ratio: .fourThree)
        addRatioItem(title: "3:2", ratio: .threeTwo)
        addRatioItem(title: "16:9", ratio: .sixteenNine)
        addRatioItem(title: "9:16", ratio: .nineSixteen)
        addSubview(menuButton)
    }

    private func addRatioItem(title: String, ratio: SelectionAspectRatio) {
        let item = NSMenuItem(title: title, action: #selector(selectRatio(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ratio
        ratioMenu.addItem(item)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }

        editingOriginalValue = field.stringValue
        editingDimension = field === widthField ? .width : .height
        suppressesCommitAfterCancel = false
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard !ignoresNextEndEditing else {
            ignoresNextEndEditing = false
            return
        }

        guard !isFinishingEditing else {
            return
        }

        finishEditing(.commit)
    }

    func control(
        _ control: NSControl,
        textView: NSTextView,
        doCommandBy commandSelector: Selector
    ) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            ensureEditingDimension(for: control)
            suppressesCommitAfterCancel = true
            finishEditing(.cancel)
            ignoresNextEndEditing = true
            window?.makeFirstResponder(window?.contentView)
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            ensureEditingDimension(for: control)
            finishEditing(.commit)
            window?.makeFirstResponder(window?.contentView)
            return true
        }

        if commandSelector == #selector(NSResponder.selectAll(_:)) {
            textView.selectAll(nil)
            return true
        }

        return false
    }

    @objc private func toggleLock() {
        finishActiveEditingBeforeControlAction()
        onLockToggle?()
    }

    @objc private func showRatioMenu() {
        finishActiveEditingBeforeControlAction()
        setMenuIcon(isOpen: true, animated: true)
        window?.makeFirstResponder(window?.contentView)
        ratioMenu.popUp(
            positioning: nil,
            at: CGPoint(x: menuButton.bounds.minX, y: menuButton.bounds.maxY + 10),
            in: menuButton
        )
        setMenuIcon(isOpen: false, animated: true)
    }

    @objc private func selectRatio(_ sender: NSMenuItem) {
        guard let ratio = sender.representedObject as? SelectionAspectRatio else {
            return
        }
        onRatioPreset?(ratio)
    }

    private func finishEditing(_ action: EditingFinishAction) {
        guard let editingDimension = activeEditingDimension else {
            cancelEditing()
            return
        }

        let field = field(for: editingDimension)

        isFinishingEditing = true
        defer {
            isFinishingEditing = false
        }

        self.editingDimension = nil

        guard action == .commit else {
            restore(field)
            return
        }

        guard !suppressesCommitAfterCancel else {
            restore(field)
            suppressesCommitAfterCancel = false
            return
        }

        let rawValue = field.currentEditor()?.string ?? field.stringValue
        field.stringValue = rawValue

        guard let value = Int(rawValue) else {
            restore(field)
            return
        }

        guard value > 0 else {
            restore(field)
            return
        }

        switch editingDimension {
        case .width:
            onWidthCommit?(value)
        case .height:
            onHeightCommit?(value)
        }
    }

    private func maximumValueForActiveDimension() -> Int {
        switch activeEditingDimension {
        case .width:
            maximumWidth
        case .height:
            maximumHeight
        case nil:
            9999
        }
    }

    private func finishActiveEditingBeforeControlAction() {
        guard activeEditingDimension != nil else {
            return
        }

        finishEditing(.commit)
    }

    private var activeEditingDimension: SelectionSizeDimension? {
        if let editingDimension {
            return editingDimension
        }

        if widthField.currentEditor() != nil {
            return .width
        }

        if heightField.currentEditor() != nil {
            return .height
        }

        return nil
    }

    private func ensureEditingDimension(for control: NSControl) {
        if control === widthField {
            editingDimension = .width
            if editingOriginalValue.isEmpty {
                editingOriginalValue = lastWidthValue
            }
        } else if control === heightField {
            editingDimension = .height
            if editingOriginalValue.isEmpty {
                editingOriginalValue = lastHeightValue
            }
        }
    }

    private func field(for dimension: SelectionSizeDimension) -> NSTextField {
        switch dimension {
        case .width:
            widthField
        case .height:
            heightField
        }
    }

    private func restore(_ field: NSTextField) {
        ignoresNextEndEditing = true
        field.currentEditor()?.string = editingOriginalValue
        field.abortEditing()
        field.stringValue = editingOriginalValue
    }

    private func isEditing(_ dimension: SelectionSizeDimension) -> Bool {
        activeEditingDimension == dimension
    }

    private func linkImage(isLocked: Bool) -> NSImage? {
        let image = NSImage(size: CGSize(width: 12, height: 12), flipped: false) { rect in
            NSColor.black.setStroke()

            let strokeWidth: CGFloat = 1.35
            let linkSize = isLocked ? CGSize(width: 6.2, height: 4.2) : CGSize(width: 5.0, height: 4.2)
            let leftX = isLocked ? rect.midX - 5.0 : rect.midX - 5.6
            let rightX = isLocked ? rect.midX - 1.2 : rect.midX + 0.6
            let leftRect = CGRect(
                x: leftX,
                y: rect.midY - linkSize.height / 2,
                width: linkSize.width,
                height: linkSize.height
            )
            let rightRect = CGRect(
                x: rightX,
                y: rect.midY - linkSize.height / 2,
                width: linkSize.width,
                height: linkSize.height
            )

            for linkRect in [leftRect, rightRect] {
                let path = NSBezierPath(roundedRect: linkRect, xRadius: linkSize.height / 2, yRadius: linkSize.height / 2)
                path.lineWidth = strokeWidth
                path.stroke()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = isLocked ? "比例联动" : "自由比例"
        return image
    }

    private func setMenuIcon(isOpen: Bool, animated: Bool) {
        if animated {
            menuButton.wantsLayer = true
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.14
            transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
            menuButton.layer?.add(transition, forKey: "ratio-menu-icon")
        }

        menuButton.image = NSImage(
            systemSymbolName: isOpen ? "chevron.up" : "chevron.down",
            accessibilityDescription: "比例预设"
        )
    }

    func cancelEditing() {
        if let editingDimension {
            field(for: editingDimension).stringValue = editingOriginalValue
        }
        editingDimension = nil
    }
}

private enum EditingFinishAction {
    case commit
    case cancel
}

private final class HUDSizeTextField: NSTextField {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              event.charactersIgnoringModifiers?.lowercased() == "a",
              let editor = currentEditor() else {
            return super.performKeyEquivalent(with: event)
        }

        editor.selectAll(nil)
        return true
    }
}

private final class HUDSizeButton: NSButton {
    private var trackingArea: NSTrackingArea?
    var tooltipText: String?
    var onHoverChange: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
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
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
