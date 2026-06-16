import AppKit
import AVKit

@MainActor
final class QuickAccessPanelController: NSObject {
    static let previewWindowTitle = "Frame Quick Access Preview"
    static let hoverPreviewWindowTitle = "Frame Quick Access Hover Preview"
    static let defaultHoverPreviewDelayForTesting: TimeInterval = 2

    private typealias ConfirmableAction = () -> Bool
    private typealias CloseAction = () -> Void

    private let thumbnailProvider: RecordingThumbnailProvider
    private let hoverPreviewDelay: TimeInterval
    private let hoverPreviewController = QuickAccessHoverPreviewController()
    private var previewItems: [QuickAccessPreviewItem] = []
    private var activeScreenObserver: NSObjectProtocol?
    private var followActiveScreenTimer: Timer?
    private var currentPreviewScreenID: CGDirectDisplayID?
    private var isPreviewRestorationSuppressed = false

    init(
        thumbnailProvider: RecordingThumbnailProvider = RecordingThumbnailProvider(),
        hoverPreviewDelay: TimeInterval = QuickAccessPanelController.defaultHoverPreviewDelayForTesting
    ) {
        self.thumbnailProvider = thumbnailProvider
        self.hoverPreviewDelay = hoverPreviewDelay
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
                screenshotImageView: content.imageView,
                recordingContentView: nil,
                copy: copy,
                save: save,
                recognizeText: recognizeText,
                openWorkspace: openWorkspace,
                pin: pin,
                downloadRecording: nil,
                copyRecording: nil,
                previewRecording: nil,
                editRecording: nil,
                hoverPreviewMedia: .image(captured.image),
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
        edit: @escaping () -> Bool,
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
        let content = makeRecordingContentView(
            for: recording,
            previewSize: previewSize,
            strings: strings,
            preview: preview
        )
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
                screenshotImageView: nil,
                recordingContentView: content,
                copy: nil,
                save: nil,
                recognizeText: nil,
                openWorkspace: nil,
                pin: nil,
                downloadRecording: download,
                copyRecording: copy,
                previewRecording: preview,
                editRecording: edit,
                hoverPreviewMedia: .recording(recording),
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

    @discardableResult
    func updatePreview(for screenshot: CapturedScreenshot) -> Bool {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return false
        }

        item.screenshotImageView?.setImage(screenshot.image)
        item.hoverPreviewMedia = .image(screenshot.image)
        item.hoverPreviewWorkItem?.cancel()
        item.hoverPreviewWorkItem = nil
        hoverPreviewController.close()
        return true
    }

    @discardableResult
    func updatePreview(for recording: CapturedRecording) -> Bool {
        guard let item = previewItems.first(where: { $0.recordingID == recording.id }) else {
            return false
        }

        item.hoverPreviewMedia = .recording(recording)
        item.recordingContentView?.updateDuration(recording.duration)
        item.hoverPreviewWorkItem?.cancel()
        item.hoverPreviewWorkItem = nil
        hoverPreviewController.close()
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
        for item in previewItems {
            item.isTemporarilyHidden = true
            hideTemporarily(item.panel)
        }
    }

    func closePreviewsForRecordingStart() {
        temporarilyHidePreviews()
        closeOrphanPreviewPanels()
    }

    func setPreviewRestorationSuppressed(_ isSuppressed: Bool) {
        isPreviewRestorationSuppressed = isSuppressed
        if isSuppressed {
            temporarilyHidePreviews()
        }
    }

    func restoreTemporarilyHiddenPreviews() {
        guard !isPreviewRestorationSuppressed else {
            temporarilyHidePreviews()
            return
        }

        let hiddenItems = previewItems.filter(\.isTemporarilyHidden)
        guard !hiddenItems.isEmpty else {
            return
        }

        repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(), force: true)
        for item in hiddenItems {
            item.isTemporarilyHidden = false
            restoreTemporarilyHiddenPanel(item.panel)
            item.panel.orderFrontRegardless()
        }
    }

    private func hideTemporarily(_ panel: NSPanel) {
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0
        panel.orderOut(nil)
    }

    private func restoreTemporarilyHiddenPanel(_ panel: NSPanel) {
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
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
        panel.title = Self.previewWindowTitle

        return panel
    }

    private func makeContentView(for screenshot: CapturedScreenshot, strings: AppStrings) -> QuickAccessContent {
        let contentView = ScreenshotPreviewView()
        contentView.wantsLayer = true
        contentView.onHoverChanged = { [weak self, weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
            if isHovered {
                self?.scheduleHoverPreview(for: contentView?.window)
            } else {
                self?.cancelHoverPreview(for: contentView?.window)
            }
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
            imageView: imageView,
            ocrButton: ocrButton,
            ocrProgressIndicator: ocrProgressIndicator,
            statusLabel: statusLabel
        )
    }

    private func makeRecordingContentView(
        for recording: CapturedRecording,
        previewSize: CGSize,
        strings: AppStrings,
        preview: @escaping () -> Bool
    ) -> RecordingQuickAccessContentView {
        let contentView = RecordingQuickAccessContentView()
        contentView.preferredContentSize = previewSize
        contentView.wantsLayer = true
        contentView.onPreviewRequested = preview
        contentView.onHoverChanged = { [weak self, weak contentView] isHovered in
            contentView?.setActionsVisible(isHovered)
            if isHovered {
                self?.scheduleHoverPreview(for: contentView?.window)
            } else {
                self?.cancelHoverPreview(for: contentView?.window)
            }
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
            action: #selector(editRecordingButtonClicked),
            style: .toolbar
        )
        if recording.format != .mp4 {
            editButton.isEnabled = false
            editButton.contentTintColor = .disabledControlTextColor
            editButton.toolTip = strings.videoEditingMP4Only
            editButton.setAccessibilityHelp(strings.videoEditingMP4Only)
        }
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
        CapturePreviewMetrics.quickAccessCardSize
    }

    nonisolated static func recordingPreviewSize(
        forSourceSize sourceSize: CGSize,
        maximumSize maxSize: CGSize = CGSize(width: CapturePreviewMetrics.previewWidth, height: 160)
    ) -> CGSize {
        CapturePreviewMetrics.quickAccessCardSize
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func scheduleHoverPreviewForTesting(window: NSWindow) {
        scheduleHoverPreview(for: window)
    }

    func closeHoverPreviewForTesting() {
        hoverPreviewController.close()
    }

    func hoverPreviewFrameForTesting() -> CGRect? {
        hoverPreviewController.frameForTesting()
    }

    func hoverPreviewPlayerIsMutedForTesting() -> Bool? {
        hoverPreviewController.playerIsMutedForTesting()
    }

    func hoverPreviewBubbleMetricsForTesting() -> QuickAccessHoverPreviewMetricsForTesting? {
        hoverPreviewController.bubbleMetricsForTesting()
    }

    func screenshotPreviewPNGDataForTesting(for screenshot: CapturedScreenshot) -> Data? {
        previewItems.first { $0.screenshotID == screenshot.id }?
            .screenshotImageView?
            .pngDataForTesting()
    }

    func recordingCountForTesting() -> Int {
        previewItems.filter { $0.recordingID != nil }.count
    }

    func recordingForTesting(id: UUID) -> CapturedRecording? {
        previewItems.compactMap { item -> CapturedRecording? in
            guard item.recordingID == id,
                  case let .recording(recording) = item.hoverPreviewMedia else {
                return nil
            }

            return recording
        }.first
    }

    private func scheduleHoverPreview(for window: NSWindow?) {
        guard let item = previewItem(for: window) else {
            return
        }

        item.hoverPreviewWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self, weak item] in
            guard let self,
                  let item,
                  self.previewItems.contains(where: { $0 === item }) else {
                return
            }

            self.hoverPreviewController.show(media: item.hoverPreviewMedia, near: item.panel.frame)
        }
        item.hoverPreviewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverPreviewDelay, execute: workItem)
    }

    private func cancelHoverPreview(for window: NSWindow?) {
        guard let item = previewItem(for: window) else {
            hoverPreviewController.close()
            return
        }

        item.hoverPreviewWorkItem?.cancel()
        item.hoverPreviewWorkItem = nil
        hoverPreviewController.close()
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

    @objc private func editRecordingButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.editRecording?()
    }

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
        item.hoverPreviewWorkItem?.cancel()
        hoverPreviewController.close()
        item.panel.close()
        previewItems.removeAll { $0 === item }
        repositionPreviewStack(preferredAnchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor(), force: true)
        stopFollowingActiveScreenIfNeeded()
        if notify {
            item.close()
        }
    }

    private func closeAllPreviews(notify: Bool) {
        let closingItems = previewItems
        for item in closingItems {
            item.statusResetWorkItem?.cancel()
            item.hoverPreviewWorkItem?.cancel()
            item.panel.close()
            if notify {
                item.close()
            }
        }
        previewItems.removeAll()
        hoverPreviewController.close()
        stopFollowingActiveScreenIfNeeded()
    }

    private func closeOrphanPreviewPanels() {
        for window in NSApp.windows where window.title == Self.previewWindowTitle {
            guard !previewItems.contains(where: { $0.panel === window }) else {
                continue
            }

            window.orderOut(nil)
            window.close()
        }
    }
}

struct QuickAccessHoverPreviewMetricsForTesting {
    let panelFrame: CGRect
    let mediaFrame: CGRect
}

enum QuickAccessOCRStatus: Equatable {
    case idle(accessibilityLabel: String)
    case recognizing(String)
    case message(String, resetAfter: TimeInterval?)
}

private struct QuickAccessContent {
    let view: NSView
    let imageView: AspectFillImageView
    let ocrButton: NSButton
    let ocrProgressIndicator: NSProgressIndicator
    let statusLabel: NSTextField
}

private enum QuickAccessHoverPreviewMedia {
    case image(NSImage)
    case recording(CapturedRecording)
}

private final class QuickAccessPreviewItem {
    let screenshotID: UUID?
    let recordingID: UUID?
    let panel: NSPanel
    let ocrButton: NSButton?
    let ocrProgressIndicator: NSProgressIndicator?
    let statusLabel: NSTextField?
    weak var screenshotImageView: AspectFillImageView?
    weak var recordingContentView: RecordingQuickAccessContentView?
    let copy: (() -> Bool)?
    let save: (() -> Bool)?
    let recognizeText: (() -> Bool)?
    let openWorkspace: (() -> Bool)?
    let pin: (() -> Bool)?
    let downloadRecording: (() -> Bool)?
    let copyRecording: (() -> Bool)?
    let previewRecording: (() -> Bool)?
    let editRecording: (() -> Bool)?
    var hoverPreviewMedia: QuickAccessHoverPreviewMedia
    let close: () -> Void
    var isTemporarilyHidden = false
    var statusResetWorkItem: DispatchWorkItem?
    var hoverPreviewWorkItem: DispatchWorkItem?

    init(
        screenshotID: UUID?,
        recordingID: UUID?,
        panel: NSPanel,
        ocrButton: NSButton?,
        ocrProgressIndicator: NSProgressIndicator?,
        statusLabel: NSTextField?,
        screenshotImageView: AspectFillImageView?,
        recordingContentView: RecordingQuickAccessContentView?,
        copy: (() -> Bool)?,
        save: (() -> Bool)?,
        recognizeText: (() -> Bool)?,
        openWorkspace: (() -> Bool)?,
        pin: (() -> Bool)?,
        downloadRecording: (() -> Bool)?,
        copyRecording: (() -> Bool)?,
        previewRecording: (() -> Bool)?,
        editRecording: (() -> Bool)?,
        hoverPreviewMedia: QuickAccessHoverPreviewMedia,
        close: @escaping () -> Void
    ) {
        self.screenshotID = screenshotID
        self.recordingID = recordingID
        self.panel = panel
        self.ocrButton = ocrButton
        self.ocrProgressIndicator = ocrProgressIndicator
        self.statusLabel = statusLabel
        self.screenshotImageView = screenshotImageView
        self.recordingContentView = recordingContentView
        self.copy = copy
        self.save = save
        self.recognizeText = recognizeText
        self.openWorkspace = openWorkspace
        self.pin = pin
        self.downloadRecording = downloadRecording
        self.copyRecording = copyRecording
        self.previewRecording = previewRecording
        self.editRecording = editRecording
        self.hoverPreviewMedia = hoverPreviewMedia
        self.close = close
    }
}

@MainActor
private final class QuickAccessHoverPreviewController {
    private var panel: NSPanel?
    private var player: AVPlayer?
    private var mediaFrame: CGRect?
    private let maximumMediaSize = CGSize(width: 640, height: 420)
    private let contentInset: CGFloat = 12
    private let spacing: CGFloat = 12

    func show(media: QuickAccessHoverPreviewMedia, near anchorFrame: CGRect) {
        close()

        let mediaSize = aspectFitSize(
            sourceSize: sourceSize(for: media),
            maximumSize: maximumMediaSize
        )
        let panelSize = CGSize(
            width: contentInset * 2 + mediaSize.width,
            height: contentInset * 2 + mediaSize.height
        )
        let mediaFrame = CGRect(
            x: contentInset,
            y: contentInset,
            width: mediaSize.width,
            height: mediaSize.height
        )
        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = QuickAccessPanelController.hoverPreviewWindowTitle
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false
        panel.ignoresMouseEvents = false

        let rootView = NSView(frame: CGRect(origin: .zero, size: panelSize))
        rootView.wantsLayer = true
        rootView.autoresizingMask = [.width, .height]

        let container = NSVisualEffectView(frame: CGRect(
            x: 0,
            y: 0,
            width: panelSize.width,
            height: panelSize.height
        ))
        container.material = .hudWindow
        container.blendingMode = .withinWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.32).cgColor

        let mediaView = makeMediaView(for: media)
        mediaView.frame = mediaFrame
        mediaView.autoresizingMask = []
        rootView.addSubview(container)
        rootView.addSubview(mediaView)
        panel.contentView = rootView
        panel.setFrameOrigin(origin(near: anchorFrame, panelSize: panelSize))
        panel.orderFrontRegardless()

        self.panel = panel
        self.mediaFrame = mediaFrame
    }

    func close() {
        player?.pause()
        player = nil
        mediaFrame = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    func frameForTesting() -> CGRect? {
        panel?.frame
    }

    func playerIsMutedForTesting() -> Bool? {
        player?.isMuted
    }

    func bubbleMetricsForTesting() -> QuickAccessHoverPreviewMetricsForTesting? {
        guard let panel,
              let mediaFrame else {
            return nil
        }

        return QuickAccessHoverPreviewMetricsForTesting(
            panelFrame: panel.frame,
            mediaFrame: mediaFrame
        )
    }

    private func makeMediaView(for media: QuickAccessHoverPreviewMedia) -> NSView {
        switch media {
        case let .image(image):
            let imageView = AspectFitImageView(image: image)
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return imageView
        case let .recording(recording):
            switch recording.format {
            case .gif:
                let imageView = NSImageView()
                imageView.image = NSImage(contentsOf: recording.fileURL)
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.animates = true
                imageView.wantsLayer = true
                imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
                return imageView
            case .mp4:
                let player = AVPlayer(url: recording.fileURL)
                player.isMuted = true
                player.actionAtItemEnd = .none
                let playerView = AVPlayerView()
                playerView.controlsStyle = .none
                playerView.videoGravity = .resizeAspect
                playerView.player = player
                self.player = player
                player.play()
                return playerView
            }
        }
    }

    private func sourceSize(for media: QuickAccessHoverPreviewMedia) -> CGSize {
        switch media {
        case let .image(image):
            return image.size == .zero ? maximumMediaSize : image.size
        case let .recording(recording):
            if recording.pixelSize.width > 0, recording.pixelSize.height > 0 {
                return recording.pixelSize
            }

            return recording.rect.size == .zero ? maximumMediaSize : recording.rect.size
        }
    }

    private func aspectFitSize(sourceSize: CGSize, maximumSize: CGSize) -> CGSize {
        guard sourceSize.width > 0,
              sourceSize.height > 0,
              maximumSize.width > 0,
              maximumSize.height > 0 else {
            return maximumSize
        }

        let scale = min(maximumSize.width / sourceSize.width, maximumSize.height / sourceSize.height)
        return CGSize(width: floor(sourceSize.width * scale), height: floor(sourceSize.height * scale))
    }

    private func origin(near anchorFrame: CGRect, panelSize: CGSize) -> CGPoint {
        let fallbackVisibleFrame = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? anchorFrame
        let targetScreen = NSScreen.screens.first { $0.visibleFrame.intersects(anchorFrame) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? fallbackVisibleFrame
        let preferredX = anchorFrame.maxX + spacing
        let fallbackX = anchorFrame.minX - panelSize.width - spacing
        let x = preferredX + panelSize.width <= visibleFrame.maxX - spacing ? preferredX : fallbackX
        let centeredY = anchorFrame.midY - panelSize.height / 2
        let y = min(max(centeredY, visibleFrame.minY + spacing), visibleFrame.maxY - panelSize.height - spacing)
        return CGPoint(x: x, y: y)
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
    var onPreviewRequested: (() -> Bool)?
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

    func updateDuration(_ duration: TimeInterval) {
        let seconds = max(0, Int(duration.rounded(.down)))
        durationLabel?.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    override var intrinsicContentSize: NSSize {
        preferredContentSize == .zero ? super.intrinsicContentSize : preferredContentSize
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point),
              isPointInPlayOverlay(point),
              !isPointInActionControls(point) else {
            super.mouseUp(with: event)
            return
        }

        _ = onPreviewRequested?()
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point),
           isPointInPlayOverlay(point),
           !isPointInActionControls(point) {
            NSCursor.pointingHand.set()
            return
        }

        super.cursorUpdate(with: event)
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

    private func isPointInActionControls(_ point: NSPoint) -> Bool {
        [overlayView, closeButton].contains { view in
            view?.frame.contains(point) == true
        }
    }

    private func isPointInPlayOverlay(_ point: NSPoint) -> Bool {
        guard let playImageView else {
            return false
        }

        return playImageView.frame.insetBy(dx: -8, dy: -8).contains(point)
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
    private var image: NSImage

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

    func setImage(_ image: NSImage) {
        self.image = image
        needsDisplay = true
    }

    func pngDataForTesting() -> Data? {
        image.pngData()
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

private final class AspectFitImageView: NSView {
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

        let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
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

@MainActor
protocol RecordingThumbnailDrawableForTesting: AnyObject {
    var lastDrawRectForTesting: CGRect { get }
}

private final class RecordingThumbnailImageView: NSView, RecordingThumbnailDrawableForTesting {
    private let image: NSImage

    var lastDrawRectForTesting: CGRect {
        drawRectForCurrentBounds()
    }

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
        let drawRect = drawRectForCurrentBounds()
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

    private func drawRectForCurrentBounds() -> CGRect {
        let sourceSize = image.size == .zero ? bounds.size : image.size
        return CapturePreviewMetrics.aspectFillDrawRect(
            imageSize: sourceSize,
            in: bounds
        )
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}
