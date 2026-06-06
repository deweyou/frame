import AppKit

@MainActor
final class VideoQuickAccessPanelController {
    private let thumbnailProvider: RecordingThumbnailProvider
    private var items: [UUID: VideoQuickAccessItem] = [:]

    init(thumbnailProvider: RecordingThumbnailProvider = RecordingThumbnailProvider()) {
        self.thumbnailProvider = thumbnailProvider
    }

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

        let desiredPreviewSize = previewSize(for: recording)
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
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        position(panel, size: desiredPreviewSize, preferredAnchor: preferredAnchor)
        panel.orderFrontRegardless()
        position(panel, size: desiredPreviewSize, preferredAnchor: preferredAnchor)
        content.frame = CGRect(origin: .zero, size: desiredPreviewSize)
        content.layoutSubtreeIfNeeded()
    }

    func actionLabelsForTesting(recordingID: UUID) -> [String] {
        items[recordingID]?.actionLabels ?? []
    }

    func isEditEnabledForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.isEditEnabled ?? false
    }

    func panelSizeForTesting(recordingID: UUID) -> CGSize? {
        items[recordingID]?.panel.frame.size
    }

    func contentFrameForTesting(recordingID: UUID) -> CGRect? {
        items[recordingID]?.contentView.frame
    }

    func previewSurfaceFrameForTesting(recordingID: UUID) -> CGRect? {
        items[recordingID]?.contentView.previewSurfaceFrameForTesting
    }

    func panelStyleMaskForTesting(recordingID: UUID) -> NSWindow.StyleMask? {
        items[recordingID]?.panel.styleMask
    }

    func isPanelVisibleForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.panel.isVisible ?? false
    }

    func hasThumbnailForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.contentView.hasThumbnailForTesting ?? false
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
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
        root.preferredContentSize = previewSize
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = true
        root.autoresizesSubviews = true
        root.onHoverChanged = { [weak root] isHovered in
            root?.setActionsVisible(isHovered)
        }

        let thumbnail = thumbnailProvider.thumbnail(for: recording.fileURL)
        let previewSurface: NSView
        if let thumbnail {
            let imageView = VideoThumbnailImageView(image: thumbnail)
            imageView.setAccessibilityLabel(strings.videoQuickAccessPreview)
            previewSurface = imageView
            root.hasThumbnailForTesting = true
        } else {
            let visualEffectView = NSVisualEffectView()
            visualEffectView.material = .hudWindow
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.state = .active
            visualEffectView.wantsLayer = true
            visualEffectView.layer?.cornerRadius = 12
            visualEffectView.layer?.cornerCurve = .continuous
            visualEffectView.layer?.masksToBounds = true
            visualEffectView.layer?.borderWidth = 0.5
            visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
            visualEffectView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            previewSurface = visualEffectView
        }

        let playImageView = NSImageView(
            image: NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: strings.videoQuickAccessPreview) ?? NSImage()
        )
        playImageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        playImageView.contentTintColor = .labelColor.withAlphaComponent(0.72)

        let duration = NSTextField(labelWithString: formattedDuration(recording.duration))
        duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        duration.textColor = .labelColor
        duration.alignment = .center
        duration.wantsLayer = true
        duration.layer?.cornerRadius = 10
        duration.layer?.cornerCurve = .continuous
        duration.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.72).cgColor

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.distribution = .fillEqually
        actions.spacing = 5
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessDownload, symbolName: "square.and.arrow.down", action: download))
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessCopy, symbolName: "doc.on.doc", action: copy))
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessPreview, symbolName: "play.rectangle", action: preview))
        actions.addArrangedSubview(makeDisabledButton(title: strings.videoQuickAccessEdit, symbolName: "slider.horizontal.3"))

        let overlayView = NSVisualEffectView()
        overlayView.material = .hudWindow
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
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
        root.addSubview(previewSurface)
        root.addSubview(overlayView)
        root.addSubview(closeButton)
        previewSurface.addSubview(playImageView)
        previewSurface.addSubview(duration)
        overlayView.addSubview(actions)
        root.installLayoutViews(
            previewSurface: previewSurface,
            playImageView: playImageView,
            durationLabel: duration,
            overlayView: overlayView,
            actionsView: actions,
            closeButton: closeButton,
            floatingButtonDiameter: floatingButtonDiameter
        )

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
    private func previewSize(for recording: CapturedRecording) -> CGSize {
        let sourceSize = recording.pixelSize == .zero ? recording.rect.size : recording.pixelSize
        return Self.previewSize(forSourceSize: sourceSize)
    }

    nonisolated static func previewSize(
        forSourceSize sourceSize: CGSize,
        maximumSize maxSize: CGSize = CGSize(width: 240, height: 160)
    ) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CapturePreviewMetrics.previewSize(forDesktopSize: nil)
        }

        let scale = min(maxSize.width / sourceSize.width, maxSize.height / sourceSize.height)
        return CGSize(
            width: max(64, floor(sourceSize.width * scale)),
            height: max(48, floor(sourceSize.height * scale))
        )
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
    var hasThumbnailForTesting = false
    var previewSurfaceFrameForTesting: CGRect? {
        previewSurface?.frame
    }

    private weak var previewSurface: NSView?
    private weak var playImageView: NSImageView?
    private weak var durationLabel: NSTextField?
    private weak var overlayView: NSView?
    private weak var actionsView: NSView?
    private weak var closeButton: NSButton?
    private var floatingButtonDiameter: CGFloat = 20
    var preferredContentSize: CGSize = .zero {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    override var intrinsicContentSize: NSSize {
        preferredContentSize == .zero ? super.intrinsicContentSize : preferredContentSize
    }

    override func setFrameSize(_ newSize: NSSize) {
        guard preferredContentSize != .zero else {
            super.setFrameSize(newSize)
            return
        }

        let clampedSize = CGSize(
            width: max(newSize.width, preferredContentSize.width),
            height: max(newSize.height, preferredContentSize.height)
        )
        super.setFrameSize(clampedSize)
    }

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func installLayoutViews(
        previewSurface: NSView,
        playImageView: NSImageView,
        durationLabel: NSTextField,
        overlayView: NSView,
        actionsView: NSView,
        closeButton: NSButton,
        floatingButtonDiameter: CGFloat
    ) {
        self.previewSurface = previewSurface
        self.playImageView = playImageView
        self.durationLabel = durationLabel
        self.overlayView = overlayView
        self.actionsView = actionsView
        self.closeButton = closeButton
        self.floatingButtonDiameter = floatingButtonDiameter
        needsLayout = true
    }

    override func layout() {
        super.layout()

        previewSurface?.frame = bounds
        playImageView?.frame = CGRect(
            x: floor((bounds.width - 34) / 2),
            y: floor((bounds.height - 34) / 2),
            width: 34,
            height: 34
        )
        let durationSize = CGSize(width: 52, height: 22)
        durationLabel?.frame = CGRect(
            x: bounds.maxX - durationSize.width - 9,
            y: bounds.minY + 9,
            width: durationSize.width,
            height: durationSize.height
        )
        let overlayWidth = min(126, max(88, bounds.width - 14))
        overlayView?.frame = CGRect(
            x: floor((bounds.width - overlayWidth) / 2),
            y: bounds.minY + 7,
            width: overlayWidth,
            height: 28
        )
        if let overlayView {
            actionsView?.frame = overlayView.bounds.insetBy(dx: 7, dy: 4)
        }
        closeButton?.frame = CGRect(
            x: bounds.maxX - floatingButtonDiameter - 6,
            y: bounds.maxY - floatingButtonDiameter - 6,
            width: floatingButtonDiameter,
            height: floatingButtonDiameter
        )
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

private final class VideoThumbnailImageView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: 12, yRadius: 12)
        clipPath.addClip()

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let sourceSize = image.size == .zero ? bounds.size : image.size
        let drawRect = CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: sourceSize,
            in: bounds
        )
        image.draw(
            in: drawRect,
            from: CGRect(origin: .zero, size: sourceSize),
            operation: .copy,
            fraction: 1
        )

        NSColor.white.withAlphaComponent(0.32).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), xRadius: 12, yRadius: 12)
        border.lineWidth = 0.5
        border.stroke()
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
