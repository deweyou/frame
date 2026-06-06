import AppKit

@MainActor
final class QuickAccessPanelController: NSObject {
    private typealias ConfirmableAction = () -> Bool
    private typealias CloseAction = () -> Void

    private let thumbnailProvider: RecordingThumbnailProvider
    private var previewItems: [QuickAccessPreviewItem] = []
    private var activeScreenObserver: NSObjectProtocol?
    private var followActiveScreenTimer: Timer?
    private var currentPreviewScreenID: CGDirectDisplayID?

    init(thumbnailProvider: RecordingThumbnailProvider = RecordingThumbnailProvider()) {
        self.thumbnailProvider = thumbnailProvider
    }

    func show(
        for captured: CapturedScreenshot,
        preferredAnchor: CGRect?,
        strings: AppStrings = AppStrings.current(),
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        recognizeText: @escaping () -> Bool,
        openWorkspace: @escaping () -> Bool,
        pin: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        let panel = makePanel(for: captured.image)
        let content = makeContentView(for: captured, strings: strings)
        panel.contentView = content.view
        previewItems.append(
            QuickAccessPreviewItem(
                screenshotID: captured.id,
                recordingID: nil,
                panel: panel,
                ocrButton: content.ocrButton,
                ocrProgressIndicator: content.ocrProgressIndicator,
                statusLabel: content.statusLabel,
                copy: copy,
                save: save,
                recognizeText: recognizeText,
                openWorkspace: openWorkspace,
                pin: pin,
                downloadRecording: nil,
                copyRecording: nil,
                previewRecording: nil,
                close: close
            )
        )
        repositionPreviewStack(preferredAnchor: preferredAnchor, force: true)
        startFollowingActiveScreen()

        panel.orderFrontRegardless()
    }

    func show(
        for recording: CapturedRecording,
        preferredAnchor: CGRect?,
        strings: AppStrings = AppStrings.current(),
        download: @escaping () -> Bool,
        copy: @escaping () -> Bool,
        preview: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        restoreTemporarilyHiddenPreviews()
        if let item = previewItems.first(where: { $0.recordingID == recording.id }) {
            item.panel.orderFrontRegardless()
            return
        }

        let sourceSize = recording.pixelSize == .zero ? recording.rect.size : recording.pixelSize
        let previewSize = Self.recordingPreviewSize(forSourceSize: sourceSize)
        let panel = makePanel(size: previewSize)
        let content = makeRecordingContentView(for: recording, previewSize: previewSize, strings: strings)
        content.frame = CGRect(origin: .zero, size: previewSize)
        content.autoresizingMask = [.width, .height]
        panel.contentView = content
        previewItems.append(
            QuickAccessPreviewItem(
                screenshotID: nil,
                recordingID: recording.id,
                panel: panel,
                ocrButton: nil,
                ocrProgressIndicator: nil,
                statusLabel: nil,
                copy: nil,
                save: nil,
                recognizeText: nil,
                openWorkspace: nil,
                pin: nil,
                downloadRecording: download,
                copyRecording: copy,
                previewRecording: preview,
                close: close
            )
        )
        repositionPreviewStack(preferredAnchor: preferredAnchor, force: true)
        startFollowingActiveScreen()

        panel.orderFrontRegardless()
        content.layoutSubtreeIfNeeded()
    }

    @discardableResult
    func closePreview(for screenshot: CapturedScreenshot, notify: Bool) -> Bool {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return false
        }

        closePreview(item, notify: notify)
        return true
    }

    func setOCRStatus(_ status: QuickAccessOCRStatus, for screenshot: CapturedScreenshot) {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return
        }
        guard let ocrButton = item.ocrButton,
              let ocrProgressIndicator = item.ocrProgressIndicator,
              let statusLabel = item.statusLabel else {
            return
        }

        item.statusResetWorkItem?.cancel()
        item.statusResetWorkItem = nil

        switch status {
        case let .idle(accessibilityLabel):
            ocrButton.isEnabled = true
            ocrButton.alphaValue = 1
            ocrButton.setAccessibilityHelp(accessibilityLabel)
            ocrButton.toolTip = accessibilityLabel
            ocrProgressIndicator.stopAnimation(nil)
            ocrProgressIndicator.isHidden = true
            statusLabel.alphaValue = 0
            statusLabel.stringValue = ""
        case let .recognizing(message):
            ocrButton.isEnabled = false
            ocrButton.alphaValue = 0.18
            ocrButton.setAccessibilityHelp(message)
            ocrButton.toolTip = nil
            ocrProgressIndicator.isHidden = false
            ocrProgressIndicator.startAnimation(nil)
            statusLabel.alphaValue = 0
            statusLabel.stringValue = ""
        case let .message(message, resetAfter):
            ocrButton.isEnabled = true
            ocrButton.alphaValue = 1
            ocrProgressIndicator.stopAnimation(nil)
            ocrProgressIndicator.isHidden = true
            statusLabel.stringValue = message
            statusLabel.alphaValue = 1
            if let resetAfter {
                let workItem = DispatchWorkItem { [weak self, weak item] in
                    guard let self,
                          let item,
                          self.previewItems.contains(where: { $0 === item }) else {
                        return
                    }

                    item.statusLabel?.alphaValue = 0
                    item.statusLabel?.stringValue = ""
                }
                item.statusResetWorkItem = workItem
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + .milliseconds(Int(resetAfter * 1000)),
                    execute: workItem
                )
            }
        }
    }

    func temporarilyHidePreviews() {
        for item in previewItems where item.panel.isVisible {
            item.isTemporarilyHidden = true
            item.panel.orderOut(nil)
        }
    }

    func restoreTemporarilyHiddenPreviews() {
        let hiddenItems = previewItems.filter(\.isTemporarilyHidden)
        guard !hiddenItems.isEmpty else {
            return
        }

        repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(), force: true)
        for item in hiddenItems {
            item.isTemporarilyHidden = false
            item.panel.orderFrontRegardless()
        }
    }

    private func makePanel(for image: NSImage) -> NSPanel {
        // Non-activating panels do not reliably participate in cursor-rect updates
        // while another app is focused, so Quick Access stays a normal floating panel.
        makePanel(size: previewSize)
    }

    private func makePanel(size: CGSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false

        return panel
    }

    private func makeContentView(for screenshot: CapturedScreenshot, strings: AppStrings) -> QuickAccessContent {
        let contentView = ScreenshotPreviewView()
        contentView.wantsLayer = true
        contentView.onHoverChanged = { [weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
        }

        let imageView = AspectFillImageView(image: screenshot.image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 12
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 0.5
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor
        imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

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

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.alignment = .center
        statusLabel.font = .systemFont(ofSize: 11, weight: .medium)
        statusLabel.textColor = .labelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.alphaValue = 0
        statusLabel.wantsLayer = true
        statusLabel.layer?.cornerRadius = 10
        statusLabel.layer?.cornerCurve = .continuous
        statusLabel.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.88).cgColor
        statusLabel.layer?.borderWidth = 0.5
        statusLabel.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        statusLabel.setAccessibilityLabel("OCR Status")

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = makeIconButton(
            title: strings.quickAccessClose,
            symbolName: "xmark",
            action: #selector(closeButtonClicked),
            style: .floatingCorner
        )
        closeButton.alphaValue = 0
        let saveButton = makeIconButton(
            title: strings.quickAccessSave,
            symbolName: "square.and.arrow.down",
            action: #selector(saveButtonClicked),
            style: .toolbar
        )
        let copyButton = makeIconButton(
            title: strings.quickAccessCopy,
            symbolName: "doc.on.doc",
            action: #selector(copyButtonClicked),
            style: .toolbar
        )
        let ocrButton = makeIconButton(
            title: strings.quickAccessOCR,
            symbolName: "character.textbox",
            action: #selector(ocrButtonClicked),
            style: .toolbar
        )
        let ocrProgressIndicator = NSProgressIndicator()
        ocrProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        ocrProgressIndicator.style = .spinning
        ocrProgressIndicator.controlSize = .small
        ocrProgressIndicator.isDisplayedWhenStopped = false
        ocrProgressIndicator.isHidden = true
        ocrProgressIndicator.setAccessibilityLabel(strings.ocrRecognizing)
        let pinButton = makeIconButton(
            title: strings.quickAccessPin,
            symbolName: "pin",
            action: #selector(pinButtonClicked),
            style: .toolbar
        )
        let openWorkspaceButton = makeIconButton(
            title: strings.quickAccessOpen,
            symbolName: "arrow.up.left.and.arrow.down.right",
            action: #selector(openWorkspaceButtonClicked),
            style: .toolbar
        )

        stackView.addArrangedSubview(saveButton)
        stackView.addArrangedSubview(copyButton)
        stackView.addArrangedSubview(ocrButton)
        stackView.addArrangedSubview(pinButton)
        stackView.addArrangedSubview(openWorkspaceButton)

        contentView.actionsViews = [closeButton, overlayView]
        contentView.addSubview(imageView)
        contentView.addSubview(overlayView)
        contentView.addSubview(closeButton)
        contentView.addSubview(statusLabel)
        overlayView.addSubview(stackView)
        overlayView.addSubview(ocrProgressIndicator)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -7),
            overlayView.widthAnchor.constraint(equalToConstant: 154),
            overlayView.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            statusLabel.bottomAnchor.constraint(equalTo: overlayView.topAnchor, constant: -6),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: imageView.widthAnchor, constant: -24),
            statusLabel.heightAnchor.constraint(equalToConstant: 22),

            stackView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 7),
            stackView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -7),
            stackView.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -4),

            ocrProgressIndicator.centerXAnchor.constraint(equalTo: ocrButton.centerXAnchor),
            ocrProgressIndicator.centerYAnchor.constraint(equalTo: ocrButton.centerYAnchor),
            ocrProgressIndicator.widthAnchor.constraint(equalToConstant: 14),
            ocrProgressIndicator.heightAnchor.constraint(equalToConstant: 14),

            closeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -cornerButtonInset),
            closeButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: cornerButtonInset),
            closeButton.widthAnchor.constraint(equalToConstant: floatingButtonDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: floatingButtonDiameter),
        ])

        return QuickAccessContent(
            view: contentView,
            ocrButton: ocrButton,
            ocrProgressIndicator: ocrProgressIndicator,
            statusLabel: statusLabel
        )
    }

    private func makeRecordingContentView(
        for recording: CapturedRecording,
        previewSize: CGSize,
        strings: AppStrings
    ) -> RecordingQuickAccessContentView {
        let contentView = RecordingQuickAccessContentView()
        contentView.preferredContentSize = previewSize
        contentView.wantsLayer = true
        contentView.onHoverChanged = { [weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
        }

        let thumbnail = thumbnailProvider.thumbnail(for: recording.fileURL)
        let previewSurface: NSView
        if let thumbnail {
            let imageView = RecordingThumbnailImageView(image: thumbnail)
            imageView.setAccessibilityLabel(strings.videoQuickAccessPreview)
            previewSurface = imageView
            contentView.hasThumbnailForTesting = true
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

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 5
        stackView.addArrangedSubview(
            makeIconButton(
                title: strings.videoQuickAccessDownload,
                symbolName: "square.and.arrow.down",
                action: #selector(downloadRecordingButtonClicked),
                style: .toolbar
            )
        )
        stackView.addArrangedSubview(
            makeIconButton(
                title: strings.videoQuickAccessCopy,
                symbolName: "doc.on.doc",
                action: #selector(copyRecordingButtonClicked),
                style: .toolbar
            )
        )
        stackView.addArrangedSubview(
            makeIconButton(
                title: strings.videoQuickAccessPreview,
                symbolName: "play.rectangle",
                action: #selector(previewRecordingButtonClicked),
                style: .toolbar
            )
        )
        let editButton = makeIconButton(
            title: strings.videoQuickAccessEdit,
            symbolName: "slider.horizontal.3",
            action: #selector(disabledRecordingEditButtonClicked),
            style: .toolbar
        )
        editButton.isEnabled = false
        editButton.contentTintColor = .disabledControlTextColor
        stackView.addArrangedSubview(editButton)

        let overlayView = NSVisualEffectView()
        overlayView.material = .hudWindow
        overlayView.blendingMode = .withinWindow
        overlayView.state = .active
        overlayView.wantsLayer = true
        overlayView.layer?.cornerRadius = 14
        overlayView.layer?.cornerCurve = .continuous
        overlayView.layer?.masksToBounds = true
        overlayView.alphaValue = 0

        let closeButton = makeIconButton(
            title: strings.quickAccessClose,
            symbolName: "xmark",
            action: #selector(closeButtonClicked),
            style: .floatingCorner
        )
        closeButton.alphaValue = 0

        contentView.actionsViews = [closeButton, overlayView]
        contentView.addSubview(previewSurface)
        contentView.addSubview(overlayView)
        contentView.addSubview(closeButton)
        previewSurface.addSubview(playImageView)
        previewSurface.addSubview(duration)
        overlayView.addSubview(stackView)
        contentView.installLayoutViews(
            previewSurface: previewSurface,
            playImageView: playImageView,
            durationLabel: duration,
            overlayView: overlayView,
            actionsView: stackView,
            closeButton: closeButton,
            floatingButtonDiameter: floatingButtonDiameter
        )

        return contentView
    }

    private enum IconButtonStyle {
        case floatingCorner
        case toolbar
    }

    private func makeIconButton(
        title: String,
        symbolName: String,
        action: Selector,
        style: IconButtonStyle
    ) -> NSButton {
        let button = PointingHandButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(),
            target: self,
            action: action
        )
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.toolTip = title
        let symbolPointSize = quickAccessSymbolPointSize(symbolName: symbolName, style: style)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        button.contentTintColor = .labelColor
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        button.identifier = NSUserInterfaceItemIdentifier(symbolName)
        if style == .floatingCorner {
            button.usesManualIconRendering = true
            button.drawsCenteredXMark = true
            button.ignoresHighlight = true
            button.controlSize = .mini
            button.contentTintColor = NSColor.labelColor.withAlphaComponent(0.68)
            button.wantsLayer = true
            button.layer?.cornerRadius = floatingButtonRadius
            button.layer?.cornerCurve = .continuous
            button.layer?.masksToBounds = false
            button.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.42).cgColor
            button.layer?.borderWidth = 0.5
            button.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.18).cgColor
            button.layer?.shadowColor = NSColor.black.cgColor
            button.layer?.shadowOpacity = 0.14
            button.layer?.shadowRadius = 3
            button.layer?.shadowOffset = CGSize(width: 0, height: -1)
        }
        return button
    }

    private func quickAccessSymbolPointSize(symbolName: String, style: IconButtonStyle) -> CGFloat {
        switch style {
        case .floatingCorner:
            9.5
        case .toolbar:
            switch symbolName {
            case "square.and.arrow.down", "character.textbox":
                12.5
            default:
                11.5
            }
        }
    }

    private let floatingButtonDiameter: CGFloat = 20
    private let cornerButtonInset: CGFloat = 6
    private var floatingButtonRadius: CGFloat {
        floatingButtonDiameter / 2
    }
    private let previewPadding: CGFloat = 18
    private let previewSpacing: CGFloat = 12

    private var previewSize: CGSize {
        CapturePreviewMetrics.previewSize(forDesktopSize: (NSScreen.main ?? NSScreen.screens.first)?.frame.size)
    }

    nonisolated static func recordingPreviewSize(
        forSourceSize sourceSize: CGSize,
        maximumSize maxSize: CGSize = CGSize(width: CapturePreviewMetrics.previewWidth, height: 160)
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

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

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
        var currentY = visibleFrame.minY + previewPadding
        for item in previewItems {
            let panelSize = item.panel.frame.size
            let unclampedOrigin = CGPoint(
                x: visibleFrame.minX + previewPadding,
                y: currentY
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
            currentY = origin.y + panelSize.height + previewSpacing
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

    @objc private func copyButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.copy?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func ocrButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.recognizeText?()
    }

    @objc private func saveButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.save?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func openWorkspaceButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.openWorkspace?()
    }

    @objc private func pinButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.pin?() == true {
            closePreview(item, notify: false)
        }
    }

    @objc private func downloadRecordingButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.downloadRecording?()
    }

    @objc private func copyRecordingButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.copyRecording?()
    }

    @objc private func previewRecordingButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.previewRecording?()
    }

    @objc private func disabledRecordingEditButtonClicked(_ sender: NSButton) {}

    @objc private func closeButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        closePreview(item, notify: true)
    }

    private func previewItem(for window: NSWindow?) -> QuickAccessPreviewItem? {
        guard let window else {
            return nil
        }

        return previewItems.first { $0.panel === window }
    }

    private func closePreview(_ item: QuickAccessPreviewItem, notify: Bool) {
        item.statusResetWorkItem?.cancel()
        item.panel.close()
        previewItems.removeAll { $0 === item }
        repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(), force: true)
        stopFollowingActiveScreenIfNeeded()
        if notify {
            item.close()
        }
    }
}

enum QuickAccessOCRStatus: Equatable {
    case idle(accessibilityLabel: String)
    case recognizing(String)
    case message(String, resetAfter: TimeInterval?)
}

private struct QuickAccessContent {
    let view: NSView
    let ocrButton: NSButton
    let ocrProgressIndicator: NSProgressIndicator
    let statusLabel: NSTextField
}

private final class QuickAccessPreviewItem {
    let screenshotID: UUID?
    let recordingID: UUID?
    let panel: NSPanel
    let ocrButton: NSButton?
    let ocrProgressIndicator: NSProgressIndicator?
    let statusLabel: NSTextField?
    let copy: (() -> Bool)?
    let save: (() -> Bool)?
    let recognizeText: (() -> Bool)?
    let openWorkspace: (() -> Bool)?
    let pin: (() -> Bool)?
    let downloadRecording: (() -> Bool)?
    let copyRecording: (() -> Bool)?
    let previewRecording: (() -> Bool)?
    let close: () -> Void
    var isTemporarilyHidden = false
    var statusResetWorkItem: DispatchWorkItem?

    init(
        screenshotID: UUID?,
        recordingID: UUID?,
        panel: NSPanel,
        ocrButton: NSButton?,
        ocrProgressIndicator: NSProgressIndicator?,
        statusLabel: NSTextField?,
        copy: (() -> Bool)?,
        save: (() -> Bool)?,
        recognizeText: (() -> Bool)?,
        openWorkspace: (() -> Bool)?,
        pin: (() -> Bool)?,
        downloadRecording: (() -> Bool)?,
        copyRecording: (() -> Bool)?,
        previewRecording: (() -> Bool)?,
        close: @escaping () -> Void
    ) {
        self.screenshotID = screenshotID
        self.recordingID = recordingID
        self.panel = panel
        self.ocrButton = ocrButton
        self.ocrProgressIndicator = ocrProgressIndicator
        self.statusLabel = statusLabel
        self.copy = copy
        self.save = save
        self.recognizeText = recognizeText
        self.openWorkspace = openWorkspace
        self.pin = pin
        self.downloadRecording = downloadRecording
        self.copyRecording = copyRecording
        self.previewRecording = previewRecording
        self.close = close
    }
}

private class ScreenshotPreviewView: NSView {
    var actionsViews: [NSView] = []
    var onHoverChanged: ((Bool) -> Void)?

    private var trackingArea: NSTrackingArea?
    private var pendingHideActionsWorkItem: DispatchWorkItem?
    private var areActionsVisible = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
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

    override func mouseEntered(with event: NSEvent) {
        showActions()
        onHoverChanged?(true)
        updateCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        scheduleActionsHide()
    }

    override func mouseMoved(with event: NSEvent) {
        updateCursor(for: event)
        super.mouseMoved(with: event)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(for: event)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0, bounds.contains(point) else {
            return nil
        }

        for actionsView in actionsViews.reversed() {
            let actionPoint = actionsView.convert(point, from: self)
            guard actionsView.bounds.contains(actionPoint) else {
                continue
            }

            if let hitView = hitActionView(actionsView, at: actionPoint) {
                return hitView
            }

            return actionsView
        }

        return self
    }

    func setActionsVisible(_ isVisible: Bool) {
        guard areActionsVisible != isVisible else {
            return
        }

        areActionsVisible = isVisible
        window?.invalidateCursorRects(for: self)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = isVisible ? 0.16 : 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for actionsView in actionsViews {
                actionsView.layer?.removeAnimation(forKey: "opacity")
                actionsView.animator().alphaValue = isVisible ? 1 : 0
            }
        }
    }

    private func showActions() {
        pendingHideActionsWorkItem?.cancel()
        pendingHideActionsWorkItem = nil
        setActionsVisible(true)
    }

    private func scheduleActionsHide() {
        pendingHideActionsWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.isMouseInsideBounds else {
                return
            }

            self.setActionsVisible(false)
            self.onHoverChanged?(false)
            NSCursor.arrow.set()
        }
        pendingHideActionsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private var isMouseInsideBounds: Bool {
        guard let window else {
            return false
        }

        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func isPointInActions(_ point: NSPoint) -> Bool {
        guard areActionsVisible else {
            return false
        }

        return actionsViews.contains { actionsView in
            actionsView.frame.contains(point)
        }
    }

    private func hitActionView(_ view: NSView, at point: NSPoint) -> NSView? {
        guard !view.isHidden,
              view.bounds.contains(point) else {
            return nil
        }

        if view is NSButton {
            return view
        }

        for subview in view.subviews.reversed() {
            let subviewPoint = subview.convert(point, from: view)
            if let hitView = hitActionView(subview, at: subviewPoint) {
                return hitView
            }
        }

        return view
    }

    private func updateCursor(for event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if isPointInActions(point) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}

private final class RecordingQuickAccessContentView: ScreenshotPreviewView {
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
}

private final class PointingHandButton: NSButton {
    private let manualIconLayer = CAShapeLayer()
    private var trackingArea: NSTrackingArea?
    private var manualIconImage: NSImage?
    var drawsCenteredXMark = false {
        didSet {
            updateManualIcon()
        }
    }
    var ignoresHighlight = false {
        didSet {
            configureHighlightBehavior()
        }
    }
    var usesManualIconRendering = false {
        didSet {
            configureManualIconRendering()
        }
    }

    override var state: NSControl.StateValue {
        get {
            super.state
        }
        set {
            super.state = ignoresHighlight ? .off : newValue
        }
    }

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override var image: NSImage? {
        get {
            usesManualIconRendering ? manualIconImage : super.image
        }
        set {
            if usesManualIconRendering {
                manualIconImage = newValue
                updateManualIcon()
            } else {
                super.image = newValue
            }
        }
    }

    override var contentTintColor: NSColor? {
        didSet {
            updateManualIcon()
        }
    }

    override func highlight(_ flag: Bool) {
        guard !ignoresHighlight else {
            clearHighlightState()
            return
        }

        super.highlight(flag)
    }

    override func draw(_ dirtyRect: NSRect) {
        if ignoresHighlight {
            clearHighlightState()
        }

        super.draw(dirtyRect)
    }

    override func layout() {
        super.layout()

        guard usesManualIconRendering else {
            return
        }

        let iconSize = min(bounds.width, bounds.height, 9.5)
        manualIconLayer.bounds = CGRect(x: 0, y: 0, width: iconSize, height: iconSize)
        manualIconLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        updateManualIcon()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
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

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
    }

    private func configureHighlightBehavior() {
        guard ignoresHighlight else {
            return
        }

        if let cell = cell as? NSButtonCell {
            cell.highlightsBy = []
            cell.showsStateBy = []
        }
        clearHighlightState()
    }

    private func configureManualIconRendering() {
        guard usesManualIconRendering else {
            manualIconLayer.removeFromSuperlayer()
            if super.image == nil {
                super.image = manualIconImage
            }
            return
        }

        manualIconImage = super.image
        super.image = nil
        wantsLayer = true
        layer?.addSublayer(manualIconLayer)
        manualIconLayer.contentsGravity = .resizeAspect
        manualIconLayer.lineCap = .round
        manualIconLayer.lineJoin = .round
        updateManualIcon()
        needsLayout = true
    }

    private func updateManualIcon() {
        guard usesManualIconRendering else {
            return
        }

        if drawsCenteredXMark {
            manualIconLayer.contents = nil
            let inset = manualIconLayer.bounds.width * 0.18
            let path = CGMutablePath()
            path.move(to: CGPoint(x: inset, y: inset))
            path.addLine(to: CGPoint(x: manualIconLayer.bounds.maxX - inset, y: manualIconLayer.bounds.maxY - inset))
            path.move(to: CGPoint(x: manualIconLayer.bounds.maxX - inset, y: inset))
            path.addLine(to: CGPoint(x: inset, y: manualIconLayer.bounds.maxY - inset))
            manualIconLayer.path = path
            manualIconLayer.fillColor = nil
            manualIconLayer.strokeColor = (contentTintColor ?? .labelColor).cgColor
            manualIconLayer.lineWidth = 1.7
        } else {
            manualIconLayer.path = nil
            manualIconLayer.strokeColor = nil
            manualIconLayer.contents = manualIconImage?.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: [.ctm: NSAffineTransform()]
            )
        }
        manualIconLayer.contentsScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        manualIconLayer.compositingFilter = nil
    }

    private func clearHighlightState() {
        cell?.isHighlighted = false
        super.state = .off
    }
}

private final class AspectFillImageView: NSView {
    private let image: NSImage

    init(image: NSImage) {
        self.image = image
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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

        let drawRect = CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: image.size,
            in: bounds
        )

        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
    }
}

private final class RecordingThumbnailImageView: NSView {
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
