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

        let panel = makePanel(for: captured.image)
        panel.contentView = makeContentView(for: captured.image)
        positionAtMainScreenBottomRight(panel)

        self.panel = panel
        panel.orderFrontRegardless()
    }

    private func makePanel(for image: NSImage) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: previewSize),
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
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false

        return panel
    }

    private func makeContentView(for image: NSImage) -> NSView {
        let contentView = ScreenshotPreviewView()
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.masksToBounds = true
        contentView.layer?.borderWidth = 0.5
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        contentView.onHoverChanged = { [weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
        }

        let imageView = AspectFillImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor

        let overlayView = NSVisualEffectView()
        overlayView.material = .hudWindow
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        overlayView.layer?.cornerRadius = 10
        overlayView.layer?.cornerCurve = .continuous
        overlayView.layer?.masksToBounds = true
        overlayView.alphaValue = 0

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false

        stackView.addArrangedSubview(makeButton(title: "保存", symbolName: "square.and.arrow.down", action: #selector(saveButtonClicked)))
        stackView.addArrangedSubview(makeButton(title: "复制", symbolName: "doc.on.doc", action: #selector(copyButtonClicked)))
        stackView.addArrangedSubview(makeButton(title: "关闭", symbolName: "xmark", action: #selector(closeButtonClicked)))

        contentView.actionsView = overlayView
        contentView.addSubview(imageView)
        contentView.addSubview(overlayView)
        overlayView.addSubview(stackView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            overlayView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),
            overlayView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            overlayView.heightAnchor.constraint(equalToConstant: 36),

            stackView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 5),
            stackView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -5),
        ])

        return contentView
    }

    private func makeButton(title: String, symbolName: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .texturedRounded
        button.controlSize = .small
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.contentTintColor = .labelColor
        button.setButtonType(.momentaryPushIn)
        return button
    }

    private let previewSize = CGSize(width: 180, height: 120)

    private func positionAtMainScreenBottomRight(_ panel: NSPanel) {
        let panelSize = panel.frame.size
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        let padding: CGFloat = 18
        let origin = CGPoint(
            x: visibleFrame.maxX - panelSize.width - padding,
            y: visibleFrame.minY + padding
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

private final class ScreenshotPreviewView: NSView {
    var actionsView: NSView?
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

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
        setActionsVisible(true)
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        setActionsVisible(false)
        onHoverChanged?(false)
    }

    func setActionsVisible(_ isVisible: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            actionsView?.animator().alphaValue = isVisible ? 1 : 0
        }
    }
}

private final class AspectFillImageView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
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

        let scale = max(bounds.width / image.size.width, bounds.height / image.size.height)
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
