import AppKit

@MainActor
final class ActiveRecordingHUDPanelController {
    static let recordingAccentColor = NSColor.systemRed
    private static let horizontalPadding: CGFloat = 3
    private static let panelSize = CGSize(width: 175, height: 42)
    private static let buttonGroupWidth: CGFloat = 108

    private let panel = NSPanel(
        contentRect: CGRect(origin: .zero, size: panelSize),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let rootView = RecordingHUDRootView()
    private let chromeView = RecordingHUDChromeView()
    private let buttonStackView = NSStackView()
    private let elapsedLabel = NSTextField(labelWithString: "00:00")
    private var onStop: () -> Void = {}
    private var onRestart: () -> Void = {}
    private var onDelete: () -> Void = {}
    private var isStopping = false
    private var renderedButtonState: ButtonState?

    private struct ButtonState: Equatable {
        let isStopping: Bool
    }

    init() {
        configurePanel()
        configureContent()
    }

    func show(
        near selectionRect: CGRect,
        elapsed: TimeInterval,
        isPaused: Bool,
        stop: @escaping () -> Void,
        restart: @escaping () -> Void,
        delete: @escaping () -> Void
    ) {
        onStop = stop
        onRestart = restart
        onDelete = delete
        isStopping = false
        renderedButtonState = nil
        resizePanelToContent()
        update(elapsed: elapsed, isPaused: isPaused)
        position(near: selectionRect)
        refreshPanelRendering()
        panel.orderFrontRegardless()
        enforcePanelFrameSize(display: true)
        refreshPanelRendering()
        Task { @MainActor [weak self] in
            self?.enforcePanelFrameSize(display: true)
            self?.refreshPanelRendering()
        }
    }

    func update(elapsed: TimeInterval, isPaused: Bool) {
        elapsedLabel.stringValue = formattedElapsed(elapsed)
        installButtonsIfNeeded()
    }

    func setStopping(_ isStopping: Bool) {
        guard self.isStopping != isStopping else {
            return
        }

        self.isStopping = isStopping
        installButtonsIfNeeded()
    }

    func close() {
        panel.orderOut(nil)
    }

    func buttonLabelsForTesting() -> [String] {
        buttonStackView.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .compactMap { $0.accessibilityLabel() }
    }

    func elapsedTextForTesting() -> String {
        elapsedLabel.stringValue
    }

    func elapsedTextColorForTesting() -> NSColor? {
        elapsedLabel.textColor
    }

    func buttonTintColorForTesting(accessibilityLabel: String) -> NSColor? {
        buttonStackView.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == accessibilityLabel }?
            .contentTintColor
    }

    func panelSizeForTesting() -> CGSize {
        panel.frame.size
    }

    func panelSizeLimitsForTesting() -> (minSize: CGSize, maxSize: CGSize, contentMinSize: CGSize, contentMaxSize: CGSize) {
        (
            minSize: panel.minSize,
            maxSize: panel.maxSize,
            contentMinSize: panel.contentMinSize,
            contentMaxSize: panel.contentMaxSize
        )
    }

    func panelHasSystemShadowForTesting() -> Bool {
        panel.hasShadow
    }

    func chromeColorsForTesting() -> (background: NSColor, border: NSColor) {
        RecordingHUDChromeView.colorsForTesting()
    }

    func rootViewFrameForTesting() -> CGRect {
        rootView.frame
    }

    func chromeViewFrameForTesting() -> CGRect {
        chromeView.frame
    }

    func horizontalPaddingForTesting() -> CGFloat {
        Self.horizontalPadding
    }

    func buttonObjectIDsForTesting() -> [ObjectIdentifier] {
        buttonStackView.arrangedSubviews
            .compactMap { $0 as? NSButton }
            .map(ObjectIdentifier.init)
    }

    func setPanelFrameForTesting(_ frame: CGRect) {
        panel.setFrame(frame, display: false)
    }

    func performButtonActionForTesting(accessibilityLabel: String) -> Bool {
        guard let button = buttonStackView.arrangedSubviews
            .compactMap({ $0 as? NSButton })
            .first(where: { $0.accessibilityLabel() == accessibilityLabel }) else {
            return false
        }

        switch accessibilityLabel {
        case "停止录制":
            stopClicked(button)
        case "重新开始":
            restartClicked(button)
        case "删除录制":
            deleteClicked(button)
        default:
            return false
        }
        return true
    }

    private func configurePanel() {
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
        panel.minSize = Self.panelSize
        panel.maxSize = Self.panelSize
        panel.contentMinSize = Self.panelSize
        panel.contentMaxSize = Self.panelSize
    }

    private func configureContent() {
        rootView.frame = CGRect(origin: .zero, size: Self.panelSize)
        rootView.autoresizingMask = [.width, .height]
        rootView.wantsLayer = true
        rootView.layer?.isOpaque = false
        rootView.layer?.backgroundColor = NSColor.clear.cgColor

        chromeView.frame = CGRect(origin: .zero, size: Self.panelSize)
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.wantsLayer = true
        chromeView.layer?.isOpaque = false

        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.distribution = .fillEqually
        buttonStackView.spacing = 0
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        elapsedLabel.alignment = .center
        elapsedLabel.lineBreakMode = .byTruncatingTail
        elapsedLabel.textColor = Self.recordingAccentColor
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

        chromeView.addSubview(buttonStackView)
        chromeView.addSubview(elapsedLabel)
        rootView.chromeView = chromeView
        rootView.addSubview(chromeView)
        panel.contentView = rootView

        NSLayoutConstraint.activate([
            chromeView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            chromeView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            chromeView.widthAnchor.constraint(equalToConstant: Self.panelSize.width),
            chromeView.heightAnchor.constraint(equalToConstant: Self.panelSize.height),

            buttonStackView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: Self.horizontalPadding),
            buttonStackView.topAnchor.constraint(equalTo: chromeView.topAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),
            buttonStackView.widthAnchor.constraint(equalToConstant: Self.buttonGroupWidth),

            elapsedLabel.leadingAnchor.constraint(equalTo: buttonStackView.trailingAnchor, constant: 4),
            elapsedLabel.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -10),
            elapsedLabel.centerYAnchor.constraint(equalTo: chromeView.centerYAnchor),
        ])
        resizePanelToContent()
    }

    private func installButtonsIfNeeded() {
        let nextButtonState = ButtonState(isStopping: isStopping)
        guard renderedButtonState != nextButtonState else {
            return
        }

        renderedButtonState = nextButtonState
        buttonStackView.arrangedSubviews.forEach { view in
            buttonStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let stopButton = makeButton(
            title: isStopping ? "正在停止" : "停止录制",
            symbolName: isStopping ? "hourglass" : "stop.fill",
            action: #selector(stopClicked)
        )
        stopButton.isEnabled = !isStopping
        stopButton.contentTintColor = isStopping ? .disabledControlTextColor : Self.recordingAccentColor
        buttonStackView.addArrangedSubview(stopButton)
        buttonStackView.addArrangedSubview(
            makeButton(title: "重新开始", symbolName: "arrow.clockwise", action: #selector(restartClicked))
        )
        let deleteButton = makeButton(
            title: "删除录制",
            symbolName: "trash",
            action: #selector(deleteClicked)
        )
        deleteButton.contentTintColor = HUDChromePalette.deepGlassForegroundColor
        buttonStackView.addArrangedSubview(deleteButton)
    }

    private func resizePanelToContent() {
        panel.setContentSize(Self.panelSize)
        rootView.frame = CGRect(origin: .zero, size: Self.panelSize)
        chromeView.frame = CGRect(origin: .zero, size: Self.panelSize)
        enforcePanelFrameSize(display: false)
    }

    private func refreshPanelRendering() {
        rootView.needsLayout = true
        rootView.layoutSubtreeIfNeeded()
        rootView.needsDisplay = true
        rootView.layer?.setNeedsDisplay()
        chromeView.needsDisplay = true
        chromeView.layer?.setNeedsDisplay()
        panel.contentView?.needsDisplay = true
        panel.displayIfNeeded()
    }

    private func makeButton(title: String, symbolName: String, action: Selector) -> NSButton {
        let button = RecordingHUDButton(
            image: NSImage(systemSymbolName: symbolName, accessibilityDescription: title) ?? NSImage(),
            target: self,
            action: action
        )
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleNone
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        button.contentTintColor = HUDChromePalette.deepGlassForegroundColor
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
    }

    private func position(near selectionRect: CGRect) {
        let visibleFrame = NSScreen.screens
            .first { $0.frame.intersects(selectionRect) }?
            .visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let panelSize = panel.frame.size
        let spacing: CGFloat = 10
        let inset: CGFloat = 12
        let belowY = selectionRect.minY - panelSize.height - spacing
        let aboveY = selectionRect.maxY + spacing
        let y = if belowY >= visibleFrame.minY + inset {
            belowY
        } else if aboveY + panelSize.height <= visibleFrame.maxY - inset {
            aboveY
        } else {
            min(max(selectionRect.minY + inset, visibleFrame.minY + inset), visibleFrame.maxY - panelSize.height - inset)
        }
        let x = min(
            max(selectionRect.midX - panelSize.width / 2, visibleFrame.minX + inset),
            visibleFrame.maxX - panelSize.width - inset
        )
        panel.setFrame(
            CGRect(origin: CGPoint(x: x, y: y), size: Self.panelSize),
            display: true
        )
    }

    private func enforcePanelFrameSize(display: Bool) {
        guard panel.frame.size != Self.panelSize else {
            return
        }

        panel.setFrame(
            CGRect(origin: panel.frame.origin, size: Self.panelSize),
            display: display
        )
    }

    private func formattedElapsed(_ elapsed: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    @objc private func stopClicked(_ sender: NSButton) {
        guard !isStopping else {
            return
        }
        setStopping(true)
        onStop()
    }

    @objc private func restartClicked(_ sender: NSButton) {
        onRestart()
    }

    @objc private func deleteClicked(_ sender: NSButton) {
        onDelete()
    }
}

private final class RecordingHUDButton: NSButton {
    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }
}

private final class RecordingHUDChromeView: NSView {
    override var isOpaque: Bool {
        false
    }

    static func colorsForTesting() -> (background: NSColor, border: NSColor) {
        (HUDChromePalette.deepGlassBackgroundColor, HUDChromePalette.deepGlassBorderColor)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let path = NSBezierPath(
            roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
            xRadius: 20.5,
            yRadius: 20.5
        )
        HUDChromePalette.deepGlassBackgroundColor.setFill()
        path.fill()
        HUDChromePalette.deepGlassBorderColor.setStroke()
        path.lineWidth = 0.5
        path.stroke()
    }
}

private final class RecordingHUDRootView: NSView {
    weak var chromeView: NSView?

    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let chromeView,
              chromeView.frame.contains(point) else {
            return nil
        }

        return super.hitTest(point)
    }
}
