import AppKit
import FrameCore

@MainActor
final class HUDSizeControl: NSView, NSTextFieldDelegate {
    var onWidthCommit: ((Int) -> Void)?
    var onHeightCommit: ((Int) -> Void)?
    var onLockToggle: (() -> Void)?
    var onRatioPreset: ((SelectionAspectRatio) -> Void)?

    private let widthButton = NSButton(title: "0", target: nil, action: nil)
    private let lockButton = NSButton()
    private let heightButton = NSButton(title: "0", target: nil, action: nil)
    private let menuButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let editor = NSTextField()
    private var editingDimension: SelectionSizeDimension?
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

    func update(width: Int, height: Int, isLocked: Bool, foregroundColor: NSColor) {
        self.foregroundColor = foregroundColor
        widthButton.title = "\(width)"
        heightButton.title = "\(height)"
        lockButton.image = NSImage(
            systemSymbolName: isLocked ? "lock.fill" : "lock.open",
            accessibilityDescription: isLocked ? "锁定比例" : "自由比例"
        )
        [widthButton, lockButton, heightButton, menuButton].forEach {
            $0.contentTintColor = foregroundColor
        }
    }

    private func configure() {
        wantsLayer = true

        [widthButton, lockButton, heightButton].forEach { button in
            button.isBordered = false
            button.bezelStyle = .regularSquare
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
        }

        widthButton.target = self
        widthButton.action = #selector(editWidth)
        widthButton.alignment = .right

        lockButton.target = self
        lockButton.action = #selector(toggleLock)
        lockButton.toolTip = "锁定比例"

        heightButton.target = self
        heightButton.action = #selector(editHeight)
        heightButton.alignment = .left

        configureMenu()
        configureEditor()

        NSLayoutConstraint.activate([
            widthButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            widthButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthButton.widthAnchor.constraint(equalToConstant: 28),

            lockButton.leadingAnchor.constraint(equalTo: widthButton.trailingAnchor, constant: 1),
            lockButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            lockButton.widthAnchor.constraint(equalToConstant: 19),
            lockButton.heightAnchor.constraint(equalToConstant: 30),

            heightButton.leadingAnchor.constraint(equalTo: lockButton.trailingAnchor, constant: 1),
            heightButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightButton.widthAnchor.constraint(equalToConstant: 28),

            menuButton.leadingAnchor.constraint(equalTo: heightButton.trailingAnchor, constant: 1),
            menuButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            menuButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 18),
        ])
    }

    private func configureMenu() {
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.isBordered = false
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

    private func configureEditor() {
        editor.isHidden = true
        editor.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        editor.alignment = .center
        editor.delegate = self
        addSubview(editor)
    }

    @objc private func editWidth() {
        startEditing(.width, from: widthButton)
    }

    @objc private func editHeight() {
        startEditing(.height, from: heightButton)
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

    private func startEditing(_ dimension: SelectionSizeDimension, from button: NSButton) {
        editingDimension = dimension
        editor.stringValue = button.title
        editor.frame = button.frame
        editor.textColor = foregroundColor
        editor.isHidden = false
        window?.makeFirstResponder(editor)
        editor.selectText(nil)
    }

    private func finishEditing(_ action: EditingFinishAction) {
        guard let editingDimension else {
            cancelEditing()
            return
        }

        isFinishingEditing = true
        defer {
            isFinishingEditing = false
        }

        editor.isHidden = true
        self.editingDimension = nil

        guard action == .commit else {
            return
        }

        guard let value = Int(editor.stringValue) else {
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

    func cancelEditing() {
        editor.isHidden = true
        editingDimension = nil
    }
}

private enum EditingFinishAction {
    case commit
    case cancel
}
