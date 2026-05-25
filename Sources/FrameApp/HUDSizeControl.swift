import AppKit
import FrameCore

@MainActor
final class HUDSizeControl: NSView, NSTextFieldDelegate {
    var onWidthCommit: ((Int) -> Void)?
    var onHeightCommit: ((Int) -> Void)?
    var onLockToggle: (() -> Void)?
    var onRatioPreset: ((SelectionAspectRatio) -> Void)?

    private let widthField = NSTextField(string: "0")
    private let linkButton = NSButton()
    private let heightField = NSTextField(string: "0")
    private let menuButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private var editingDimension: SelectionSizeDimension?
    private var editingOriginalValue = ""
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
        editingDimension != nil
    }

    func update(width: Int, height: Int, isLocked: Bool, foregroundColor: NSColor) {
        self.foregroundColor = foregroundColor

        if editingDimension != .width {
            widthField.stringValue = "\(width)"
        }
        if editingDimension != .height {
            heightField.stringValue = "\(height)"
        }

        linkButton.image = linkImage(isLocked: isLocked)
        [widthField, heightField].forEach { field in
            field.textColor = foregroundColor
        }
        [linkButton, menuButton].forEach {
            $0.contentTintColor = foregroundColor
        }
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
        linkButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(linkButton)

        configureMenu()

        NSLayoutConstraint.activate([
            widthField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            widthField.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthField.widthAnchor.constraint(equalToConstant: 32),

            linkButton.leadingAnchor.constraint(equalTo: widthField.trailingAnchor, constant: 1),
            linkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            linkButton.widthAnchor.constraint(equalToConstant: 17),
            linkButton.heightAnchor.constraint(equalToConstant: 30),

            heightField.leadingAnchor.constraint(equalTo: linkButton.trailingAnchor, constant: 1),
            heightField.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightField.widthAnchor.constraint(equalToConstant: 32),

            menuButton.leadingAnchor.constraint(equalTo: heightField.trailingAnchor, constant: 1),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 15),
        ])
    }

    private func configureMenu() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "比例预设")
        menuButton.imagePosition = .imageOnly
        menuButton.menu?.removeAllItems()
        menuButton.addItem(withTitle: "")
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
        menuButton.menu?.addItem(item)
    }

    func controlTextDidBeginEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return
        }

        editingOriginalValue = field.stringValue
        editingDimension = field === widthField ? .width : .height
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
            finishEditing(.cancel)
            window?.makeFirstResponder(window?.contentView)
            return true
        }

        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            finishEditing(.commit)
            window?.makeFirstResponder(window?.contentView)
            return true
        }

        return false
    }

    @objc private func toggleLock() {
        onLockToggle?()
    }

    @objc private func selectRatio(_ sender: NSMenuItem) {
        guard let ratio = sender.representedObject as? SelectionAspectRatio else {
            return
        }
        onRatioPreset?(ratio)
    }

    private func finishEditing(_ action: EditingFinishAction) {
        guard let editingDimension else {
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

        guard let value = Int(field.stringValue) else {
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

    private func field(for dimension: SelectionSizeDimension) -> NSTextField {
        switch dimension {
        case .width:
            widthField
        case .height:
            heightField
        }
    }

    private func linkImage(isLocked: Bool) -> NSImage? {
        let symbolName = isLocked ? "link.circle.fill" : "link.circle"
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
