import AppKit
import FrameCore

@MainActor
final class HUDSizeControl: NSView, NSTextFieldDelegate {
    var onWidthCommit: ((Int) -> Void)?
    var onHeightCommit: ((Int) -> Void)?
    var onLockToggle: (() -> Void)?
    var onRatioPreset: ((SelectionAspectRatio) -> Void)?

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
        linkButton.alphaValue = isLocked ? 1 : 0.5
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
        linkButton.toolTip = "锁定比例"
        linkButton.isBordered = false
        linkButton.bezelStyle = .regularSquare
        linkButton.imagePosition = .imageOnly
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
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 17),
        ])
    }

    private func configureMenu() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "比例预设")
        menuButton.imagePosition = .imageOnly
        menuButton.bezelStyle = .regularSquare
        menuButton.setButtonType(.momentaryChange)
        menuButton.target = self
        menuButton.action = #selector(showRatioMenu)
        menuButton.toolTip = "比例预设"
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
        selectAll(in: field)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
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
            finishEditing(.cancel)
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
        window?.makeFirstResponder(window?.contentView)
        ratioMenu.popUp(
            positioning: nil,
            at: CGPoint(x: menuButton.bounds.minX, y: menuButton.bounds.maxY + 4),
            in: menuButton
        )
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
            field.stringValue = editingOriginalValue
            return
        }

        let rawValue = field.currentEditor()?.string ?? field.stringValue
        field.stringValue = rawValue

        guard let value = Int(rawValue) else {
            field.stringValue = editingOriginalValue
            NSSound.beep()
            return
        }

        guard value > 0,
              value <= maximumValue(for: editingDimension) else {
            field.stringValue = editingOriginalValue
            NSSound.beep()
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
        } else if control === heightField {
            editingDimension = .height
        }
    }

    private func selectAll(in field: NSTextField) {
        field.selectText(nil)
        field.currentEditor()?.selectAll(nil)
    }

    private func maximumValue(for dimension: SelectionSizeDimension) -> Int {
        switch dimension {
        case .width:
            maximumWidth
        case .height:
            maximumHeight
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

    private func isEditing(_ dimension: SelectionSizeDimension) -> Bool {
        activeEditingDimension == dimension
    }

    private func linkImage(isLocked: Bool) -> NSImage? {
        let symbolName = isLocked ? "link" : "link"
        return NSImage(systemSymbolName: symbolName, accessibilityDescription: isLocked ? "比例联动" : "自由比例")
            ?? NSImage(systemSymbolName: "link", accessibilityDescription: nil)
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
}

private final class HUDSizeButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}
