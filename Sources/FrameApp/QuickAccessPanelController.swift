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
        openWorkspace: @escaping () -> Bool,
        pin: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        let panel = makePanel(for: captured.image)
        panel.contentView = makeContentView(for: captured)
        previewItems.append(
            QuickAccessPreviewItem(
                screenshotID: captured.id,
                panel: panel,
                copy: copy,
                save: save,
                openWorkspace: openWorkspace,
                pin: pin,
                close: close
            )
        )
        repositionPreviewStack(preferredAnchor: preferredAnchor, force: true)
        startFollowingActiveScreen()

        panel.orderFrontRegardless()
    }

    @discardableResult
    func closePreview(for screenshot: CapturedScreenshot, notify: Bool) -> Bool {
        guard let item = previewItems.first(where: { $0.screenshotID == screenshot.id }) else {
            return false
        }

        closePreview(item, notify: notify)
        return true
    }

    private func makePanel(for image: NSImage) -> NSPanel {
        // Non-activating panels do not reliably participate in cursor-rect updates
        // while another app is focused, so Quick Access stays a normal floating panel.
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: previewSize),
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
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isOpaque = false

        return panel
    }

    private func makeContentView(for screenshot: CapturedScreenshot) -> NSView {
        let contentView = ScreenshotPreviewView(
            screenshot: screenshot,
            dragItemProvider: ScreenshotDragItemProvider()
        )
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
        imageView.layer?.backgroundColor = NSColor.clear.cgColor

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

        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.distribution = .fillEqually
        stackView.spacing = 5
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = makeIconButton(
            title: "关闭",
            symbolName: "xmark",
            action: #selector(closeButtonClicked),
            style: .floatingCorner
        )
        closeButton.alphaValue = 0
        let saveButton = makeIconButton(
            title: "保存",
            symbolName: "square.and.arrow.down",
            action: #selector(saveButtonClicked),
            style: .toolbar
        )
        let copyButton = makeIconButton(
            title: "复制",
            symbolName: "doc.on.doc",
            action: #selector(copyButtonClicked),
            style: .toolbar
        )
        let pinButton = makeIconButton(
            title: "固定到预览窗口",
            symbolName: "pin",
            action: #selector(pinButtonClicked),
            style: .toolbar
        )
        let openWorkspaceButton = makeIconButton(
            title: "打开预览",
            symbolName: "arrow.up.left.and.arrow.down.right",
            action: #selector(openWorkspaceButtonClicked),
            style: .toolbar
        )

        stackView.addArrangedSubview(saveButton)
        stackView.addArrangedSubview(copyButton)
        stackView.addArrangedSubview(pinButton)
        stackView.addArrangedSubview(openWorkspaceButton)

        contentView.actionsViews = [closeButton, overlayView]
        contentView.addSubview(imageView)
        contentView.addSubview(overlayView)
        contentView.addSubview(closeButton)
        overlayView.addSubview(stackView)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            overlayView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -7),
            overlayView.widthAnchor.constraint(equalToConstant: 124),
            overlayView.heightAnchor.constraint(equalToConstant: 28),

            stackView.leadingAnchor.constraint(equalTo: overlayView.leadingAnchor, constant: 7),
            stackView.trailingAnchor.constraint(equalTo: overlayView.trailingAnchor, constant: -7),
            stackView.topAnchor.constraint(equalTo: overlayView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: overlayView.bottomAnchor, constant: -4),

            closeButton.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -cornerButtonInset),
            closeButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: cornerButtonInset),
            closeButton.widthAnchor.constraint(equalToConstant: floatingButtonDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: floatingButtonDiameter),
        ])

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
        button.toolTip = title
        let symbolPointSize: CGFloat = style == .floatingCorner ? 9.5 : 10.5
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .semibold)
        button.contentTintColor = .labelColor
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setAccessibilityLabel(title)
        button.setAccessibilityHelp(title)
        if style == .floatingCorner {
            button.controlSize = .mini
            button.contentTintColor = NSColor.black.withAlphaComponent(0.82)
            button.wantsLayer = true
            button.layer?.cornerRadius = floatingButtonRadius
            button.layer?.cornerCurve = .continuous
            button.layer?.masksToBounds = false
            button.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.92).cgColor
            button.layer?.borderWidth = 0.5
            button.layer?.borderColor = NSColor.black.withAlphaComponent(0.14).cgColor
            button.layer?.shadowColor = NSColor.black.cgColor
            button.layer?.shadowOpacity = 0.22
            button.layer?.shadowRadius = 4
            button.layer?.shadowOffset = CGSize(width: 0, height: -1)
        }
        return button
    }

    private let previewImageSize = CGSize(width: 200, height: 132)
    private let floatingButtonDiameter: CGFloat = 20
    private let cornerButtonInset: CGFloat = 6
    private var floatingButtonRadius: CGFloat {
        floatingButtonDiameter / 2
    }
    private var previewSize: CGSize {
        previewImageSize
    }
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

    @objc private func copyButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.copy() {
            closePreview(item, notify: false)
        }
    }

    @objc private func saveButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.save() {
            closePreview(item, notify: false)
        }
    }

    @objc private func openWorkspaceButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        _ = item.openWorkspace()
    }

    @objc private func pinButtonClicked(_ sender: NSButton) {
        guard let item = previewItem(for: sender.window) else {
            return
        }

        if item.pin() {
            closePreview(item, notify: false)
        }
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
    let screenshotID: UUID
    let panel: NSPanel
    let copy: () -> Bool
    let save: () -> Bool
    let openWorkspace: () -> Bool
    let pin: () -> Bool
    let close: () -> Void

    init(
        screenshotID: UUID,
        panel: NSPanel,
        copy: @escaping () -> Bool,
        save: @escaping () -> Bool,
        openWorkspace: @escaping () -> Bool,
        pin: @escaping () -> Bool,
        close: @escaping () -> Void
    ) {
        self.screenshotID = screenshotID
        self.panel = panel
        self.copy = copy
        self.save = save
        self.openWorkspace = openWorkspace
        self.pin = pin
        self.close = close
    }
}

private final class ScreenshotPreviewView: NSView {
    var actionsViews: [NSView] = []
    var onHoverChanged: ((Bool) -> Void)?

    private let screenshot: CapturedScreenshot
    private let dragItemProvider: ScreenshotDragItemProvider
    private var trackingArea: NSTrackingArea?
    private var pendingHideActionsWorkItem: DispatchWorkItem?
    private var areActionsVisible = false

    init(screenshot: CapturedScreenshot, dragItemProvider: ScreenshotDragItemProvider) {
        self.screenshot = screenshot
        self.dragItemProvider = dragItemProvider
        super.init(frame: .zero)
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

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard !isPointInActions(point) else {
            return
        }

        let item = dragItemProvider.draggingItem(for: screenshot, sourceBounds: bounds)
        beginDraggingSession(with: [item], event: event, source: self)
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

private final class PointingHandButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override var alignmentRectInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
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
}

extension ScreenshotPreviewView: NSDraggingSource {
    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
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
