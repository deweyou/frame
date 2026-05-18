import AppKit

@MainActor
final class QuickAccessPanelController: NSObject {
    private typealias ConfirmableAction = () -> Bool
    private typealias CloseAction = () -> Void

    private var panel: NSPanel?
    private var onCopy: ConfirmableAction?
    private var onSave: ConfirmableAction?
    private var onClose: CloseAction?

    func show(
        for captured: CapturedScreenshot,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        closePanel(notify: false)

        onCopy = copy
        onSave = save
        onClose = close

        let panel = makePanel()
        panel.contentView = makeContentView()
        position(panel, near: captured.rect)

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true

        return panel
    }

    private func makeContentView() -> NSView {
        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 10
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 8
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(makeButton(title: "复制", action: #selector(copyButtonClicked)))
        stackView.addArrangedSubview(makeButton(title: "保存", action: #selector(saveButtonClicked)))
        stackView.addArrangedSubview(makeButton(title: "关闭", action: #selector(closeButtonClicked)))

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])

        return contentView
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        return button
    }

    private func position(_ panel: NSPanel, near rect: CGRect) {
        let panelSize = panel.frame.size
        let targetScreen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 10

        let proposedOrigin = CGPoint(
            x: rect.midX - panelSize.width / 2,
            y: rect.minY - panelSize.height - verticalPadding
        )

        var origin = proposedOrigin
        if origin.y < visibleFrame.minY {
            origin.y = rect.maxY + verticalPadding
        }

        origin.x = min(
            max(origin.x, visibleFrame.minX + horizontalPadding),
            visibleFrame.maxX - panelSize.width - horizontalPadding
        )
        origin.y = min(
            max(origin.y, visibleFrame.minY + verticalPadding),
            visibleFrame.maxY - panelSize.height - verticalPadding
        )

        panel.setFrameOrigin(origin)
    }

    @objc private func copyButtonClicked() {
        if onCopy?() == true {
            closePanel(notify: false)
        }
    }

    @objc private func saveButtonClicked() {
        if onSave?() == true {
            closePanel(notify: false)
        }
    }

    @objc private func closeButtonClicked() {
        closePanel(notify: true)
    }

    private func closePanel(notify: Bool) {
        panel?.close()
        panel = nil
        onCopy = nil
        onSave = nil

        let close = onClose
        onClose = nil

        if notify {
            close?()
        }
    }
}
