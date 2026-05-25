import AppKit

@MainActor
final class QuickAccessPanelController: NSObject {
    private typealias ConfirmableAction = () -> Bool
    private typealias CloseAction = () -> Void

    private var previewItems: [QuickAccessPreviewItem] = []
    private var activeScreenObserver: NSObjectProtocol?
    private var followActiveScreenTimer: Timer?
    private var currentPreviewScreenID: CGDirectDisplayID?

    func show(
        for captured: CapturedScreenshot,
        preferredAnchor: CGRect?,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        let panel = makePanel(for: captured.image)
        panel.contentView = makeContentView(for: captured.image)
        previewItems.append(
            QuickAccessPreviewItem(
                panel: panel,
                copy: copy,
                save: save,
                close: close
            )
        )
        repositionPreviewStack(preferredAnchor: preferredAnchor, force: true)
        startFollowingActiveScreen()

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
    private let previewPadding: CGFloat = 18
    private let previewSpacing: CGFloat = 12

    private func startFollowingActiveScreen() {
        guard followActiveScreenTimer == nil else {
            return
        }

        activeScreenObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor())
            }
        }

        followActiveScreenTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor())
            }
        }
    }

    private func stopFollowingActiveScreenIfNeeded() {
        guard previewItems.isEmpty else {
            return
        }

        if let activeScreenObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeScreenObserver)
            self.activeScreenObserver = nil
        }

        followActiveScreenTimer?.invalidate()
        followActiveScreenTimer = nil
        currentPreviewScreenID = nil
    }

    private func repositionPreviewStack(preferredAnchor: CGRect?, force: Bool = false) {
        let targetScreen = preferredScreen(for: preferredAnchor)
        let targetScreenID = displayID(for: targetScreen)
        guard force || targetScreenID != currentPreviewScreenID else {
            return
        }

        currentPreviewScreenID = targetScreenID
        let visibleFrame = targetScreen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSScreen.screens.first?.visibleFrame
            ?? .zero
        for (index, item) in previewItems.enumerated() {
            let panelSize = item.panel.frame.size
            let unclampedOrigin = CGPoint(
                x: visibleFrame.minX + previewPadding,
                y: visibleFrame.minY + previewPadding + CGFloat(index) * (panelSize.height + previewSpacing)
            )
            let origin = CGPoint(
                x: min(
                    max(unclampedOrigin.x, visibleFrame.minX + previewPadding),
                    visibleFrame.maxX - panelSize.width - previewPadding
                ),
                y: min(
                    max(unclampedOrigin.y, visibleFrame.minY + previewPadding),
                    visibleFrame.maxY - panelSize.height - previewPadding
                )
            )

            item.panel.setFrameOrigin(origin)
        }
    }

    private func preferredScreen(for preferredAnchor: CGRect?) -> NSScreen? {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        let anchorFrame = preferredAnchor ?? fallbackScreen?.visibleFrame ?? .zero
        return NSScreen.screens
            .max { firstScreen, secondScreen in
                intersectionArea(firstScreen.frame, anchorFrame) < intersectionArea(secondScreen.frame, anchorFrame)
            }
            ?? fallbackScreen
    }

    private func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(displayNumber.uint32Value)
    }

    private func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    @objc private func copyButtonClicked() {
        guard let item = previewItem(for: NSApp.currentEvent) else {
            return
        }

        if item.copy() {
            closePreview(item, notify: false)
        }
    }

    @objc private func saveButtonClicked() {
        guard let item = previewItem(for: NSApp.currentEvent) else {
            return
        }

        if item.save() {
            closePreview(item, notify: false)
        }
    }

    @objc private func closeButtonClicked() {
        guard let item = previewItem(for: NSApp.currentEvent) else {
            return
        }

        closePreview(item, notify: true)
    }

    private func previewItem(for event: NSEvent?) -> QuickAccessPreviewItem? {
        guard let eventWindow = event?.window else {
            return nil
        }

        return previewItems.first { $0.panel === eventWindow }
    }

    private func closePreview(_ item: QuickAccessPreviewItem, notify: Bool) {
        item.panel.close()
        previewItems.removeAll { $0 === item }
        repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(), force: true)
        stopFollowingActiveScreenIfNeeded()
        if notify {
            item.close()
        }
    }
}

private final class QuickAccessPreviewItem {
    let panel: NSPanel
    let copy: () -> Bool
    let save: () -> Bool
    let close: () -> Void

    init(
        panel: NSPanel,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        self.panel = panel
        self.copy = copy
        self.save = save
        self.close = close
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
