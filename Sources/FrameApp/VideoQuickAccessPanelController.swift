import AppKit

@MainActor
final class VideoQuickAccessPanelController {
    private var items: [UUID: VideoQuickAccessItem] = [:]

    func show(
        for recording: CapturedRecording,
        preferredAnchor: CGRect?,
        strings: AppStrings,
        download: @escaping () -> Bool,
        copy: @escaping () -> Bool,
        preview: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        if let item = items[recording.id] {
            item.panel.orderFrontRegardless()
            return
        }

        let desiredPreviewSize = previewSize
        let panel = makePanel(size: desiredPreviewSize)
        let content = makeContentView(
            recording: recording,
            previewSize: desiredPreviewSize,
            strings: strings,
            download: download,
            copy: copy,
            preview: preview,
            close: { [weak self] in
                guard let self,
                      let item = self.items[recording.id] else {
                    return false
                }

                self.items[recording.id] = nil
                item.panel.orderOut(nil)
                item.close()
                return true
            }
        )
        let item = VideoQuickAccessItem(
            recording: recording,
            panel: panel,
            contentView: content,
            preferredSize: desiredPreviewSize,
            actionLabels: [
                strings.videoQuickAccessDownload,
                strings.videoQuickAccessCopy,
                strings.videoQuickAccessPreview,
                strings.videoQuickAccessEdit,
                strings.quickAccessClose,
            ],
            isEditEnabled: false,
            close: close
        )
        items[recording.id] = item
        content.frame = CGRect(origin: .zero, size: desiredPreviewSize)
        panel.contentView = content
        panel.setContentSize(desiredPreviewSize)
        position(panel, size: desiredPreviewSize, preferredAnchor: preferredAnchor)
        panel.orderFrontRegardless()
    }

    func actionLabelsForTesting(recordingID: UUID) -> [String] {
        items[recordingID]?.actionLabels ?? []
    }

    func isEditEnabledForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.isEditEnabled ?? false
    }

    func panelSizeForTesting(recordingID: UUID) -> CGSize? {
        items[recordingID]?.preferredSize
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.setContentSize(size)
        return panel
    }

    private func makeContentView(
        recording: CapturedRecording,
        previewSize: CGSize,
        strings: AppStrings,
        download: @escaping () -> Bool,
        copy: @escaping () -> Bool,
        preview: @escaping () -> Bool,
        close: @escaping () -> Bool
    ) -> VideoQuickAccessContentView {
        let root = VideoQuickAccessContentView()
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false
        root.onHoverChanged = { [weak root] isHovered in
            root?.setActionsVisible(isHovered)
        }

        let previewView = NSVisualEffectView()
        previewView.material = .hudWindow
        previewView.blendingMode = .behindWindow
        previewView.state = .active
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.wantsLayer = true
        previewView.layer?.cornerRadius = 12
        previewView.layer?.cornerCurve = .continuous
        previewView.layer?.masksToBounds = true
        previewView.layer?.borderWidth = 0.5
        previewView.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        previewView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let playImageView = NSImageView(
            image: NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: strings.videoQuickAccessPreview) ?? NSImage()
        )
        playImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        playImageView.contentTintColor = .labelColor.withAlphaComponent(0.72)
        playImageView.translatesAutoresizingMaskIntoConstraints = false

        let duration = NSTextField(labelWithString: formattedDuration(recording.duration))
        duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        duration.textColor = .labelColor
        duration.alignment = .center
        duration.translatesAutoresizingMaskIntoConstraints = false
        duration.wantsLayer = true
        duration.layer?.cornerRadius = 10
        duration.layer?.cornerCurve = .continuous
        duration.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.distribution = .fillEqually
        actions.spacing = 5
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessDownload, symbolName: "square.and.arrow.down", action: download))
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessCopy, symbolName: "doc.on.doc", action: copy))
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessPreview, symbolName: "play.rectangle", action: preview))
        actions.addArrangedSubview(makeDisabledButton(title: strings.videoQuickAccessEdit, symbolName: "slider.horizontal.3"))

        let overlayView = NSVisualEffectView()
        overlayView.material = .hudWindow
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.wantsLayer = true
        overlayView.layer?.cornerRadius = 14
        overlayView.layer?.cornerCurve = .continuous
        overlayView.layer?.masksToBounds = true
        overlayView.alphaValue = 0

        let closeButton = makeButton(title: strings.quickAccessClose, symbolName: "xmark", action: close)
        closeButton.alphaValue = 0
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = floatingButtonDiameter / 2
        closeButton.layer?.cornerCurve = .continuous
        closeButton.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor

        root.actionsViews = [overlayView, closeButton]
        root.addSubview(previewView)
        root.addSubview(overlayView)
        root.addSubview(closeButton)
        previewView.addSubview(playImageView)
        previewView.addSubview(duration)
        overlayView.addSubview(actions)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: previewSize.width),
            root.heightAnchor.constraint(equalToConstant: previewSize.height),

            previewView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            previewView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            previewView.topAnchor.constraint(equalTo: root.topAnchor),
            previewView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            playImageView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            playImageView.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),

            duration.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -9),
            duration.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -9),
            duration.widthAnchor.constraint(greaterThanOrEqualToConstant: 48),
            duration.heightAnchor.constraint(equalToConstant: 22),

            overlayView.centerXAnchor.constraint(equalTo: previewView.centerXAnchor),
            overlayView.bottomAnchor.constraint(equalTo: previewView.bottomAnchor, constant: -7),
            overlayView.widthAnchor.constraint(equalToConstant: 126),
            overlayView.heightAnchor.constraint(equalToConstant: 28),

            actions.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 7),
            actions.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -7),
            actions.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 4),
            actions.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -6),
            closeButton.topAnchor.constraint(equalTo: previewView.topAnchor, constant: 6),
            closeButton.widthAnchor.constraint(equalToConstant: floatingButtonDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: floatingButtonDiameter),
        ])

        return root
    }

    private func makeButton(title: String, symbolName: String, action: @escaping () -> Bool) -> NSButton {
        let button = VideoQuickAccessActionButton(action: action)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.isBordered = false
        button.toolTip = title
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11.5, weight: .semibold)
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel(title)
        return button
    }

    private func makeDisabledButton(title: String, symbolName: String) -> NSButton {
        let button = makeButton(title: title, symbolName: symbolName, action: { false })
        button.isEnabled = false
        button.contentTintColor = .disabledControlTextColor
        return button
    }

    private func position(_ panel: NSPanel, size: CGSize, preferredAnchor: CGRect?) {
        let visibleFrame = preferredScreen(for: preferredAnchor)?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let origin = CGPoint(x: visibleFrame.minX + previewPadding, y: visibleFrame.minY + previewPadding)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
    }

    private func preferredScreen(for preferredAnchor: CGRect?) -> NSScreen? {
        let fallbackScreen = NSScreen.main ?? NSScreen.screens.first
        let anchorFrame = preferredAnchor ?? fallbackScreen?.visibleFrame ?? .zero
        return NSScreen.screens.max { firstScreen, secondScreen in
            intersectionArea(firstScreen.frame, anchorFrame) < intersectionArea(secondScreen.frame, anchorFrame)
        } ?? fallbackScreen
    }

    private func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private let floatingButtonDiameter: CGFloat = 20
    private let previewPadding: CGFloat = 18
    private var previewSize: CGSize {
        CapturePreviewMetrics.previewSize(forDesktopSize: (NSScreen.main ?? NSScreen.screens.first)?.frame.size)
    }
}

private final class VideoQuickAccessItem {
    let recording: CapturedRecording
    let panel: NSPanel
    let contentView: VideoQuickAccessContentView
    let preferredSize: CGSize
    let actionLabels: [String]
    let isEditEnabled: Bool
    let close: () -> Void

    init(
        recording: CapturedRecording,
        panel: NSPanel,
        contentView: VideoQuickAccessContentView,
        preferredSize: CGSize,
        actionLabels: [String],
        isEditEnabled: Bool,
        close: @escaping () -> Void
    ) {
        self.recording = recording
        self.panel = panel
        self.contentView = contentView
        self.preferredSize = preferredSize
        self.actionLabels = actionLabels
        self.isEditEnabled = isEditEnabled
        self.close = close
    }
}

private final class VideoQuickAccessContentView: NSView {
    var actionsViews: [NSView] = []
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        trackingArea = area
        addTrackingArea(area)
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
            for view in actionsViews {
                view.animator().alphaValue = isVisible ? 1 : 0
            }
        }
    }
}

private final class VideoQuickAccessActionButton: NSButton {
    private let handler: () -> Bool

    init(action: @escaping () -> Bool) {
        self.handler = action
        super.init(frame: .zero)
        target = self
        self.action = #selector(performAction(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func performAction(_ sender: NSButton) {
        _ = handler()
    }
}
