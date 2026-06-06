import AppKit

@MainActor
final class ActiveRecordingHUDPanelController {
    private let panel = NSPanel(
        contentRect: CGRect(origin: .zero, size: CGSize(width: 178, height: 42)),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private let rootView = NSVisualEffectView()
    private let buttonStackView = NSStackView()
    private let elapsedLabel = NSTextField(labelWithString: "00:00")
    private var onPause: () -> Void = {}
    private var onResume: () -> Void = {}
    private var onStop: () -> Void = {}
    private var isPaused = false
    private var isStopping = false

    init() {
        configurePanel()
        configureContent()
    }

    func show(
        near selectionRect: CGRect,
        elapsed: TimeInterval,
        isPaused: Bool,
        pause: @escaping () -> Void,
        resume: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        onPause = pause
        onResume = resume
        onStop = stop
        isStopping = false
        update(elapsed: elapsed, isPaused: isPaused)
        position(near: selectionRect)
        panel.orderFrontRegardless()
    }

    func update(elapsed: TimeInterval, isPaused: Bool) {
        self.isPaused = isPaused
        elapsedLabel.stringValue = formattedElapsed(elapsed)
        installButtons()
    }

    func setStopping(_ isStopping: Bool) {
        self.isStopping = isStopping
        installButtons()
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

    func panelSizeForTesting() -> CGSize {
        panel.frame.size
    }

    private func configurePanel() {
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.sharingType = .none
    }

    private func configureContent() {
        rootView.material = .hudWindow
        rootView.blendingMode = .behindWindow
        rootView.state = .active
        rootView.wantsLayer = true
        rootView.layer?.cornerRadius = 21
        rootView.layer?.cornerCurve = .continuous
        rootView.layer?.masksToBounds = true
        rootView.layer?.borderWidth = 0.5
        rootView.layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor

        buttonStackView.orientation = .horizontal
        buttonStackView.alignment = .centerY
        buttonStackView.distribution = .fillEqually
        buttonStackView.spacing = 0
        buttonStackView.translatesAutoresizingMaskIntoConstraints = false

        elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        elapsedLabel.alignment = .center
        elapsedLabel.lineBreakMode = .byTruncatingTail
        elapsedLabel.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(buttonStackView)
        rootView.addSubview(elapsedLabel)
        panel.contentView = rootView

        NSLayoutConstraint.activate([
            buttonStackView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            buttonStackView.topAnchor.constraint(equalTo: rootView.topAnchor),
            buttonStackView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
            buttonStackView.widthAnchor.constraint(equalToConstant: 84),

            elapsedLabel.leadingAnchor.constraint(equalTo: buttonStackView.trailingAnchor, constant: 8),
            elapsedLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            elapsedLabel.centerYAnchor.constraint(equalTo: rootView.centerYAnchor),
        ])
    }

    private func installButtons(isPaused: Bool) {
        self.isPaused = isPaused
        installButtons()
    }

    private func installButtons() {
        buttonStackView.arrangedSubviews.forEach { view in
            buttonStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        buttonStackView.addArrangedSubview(
            isPaused
                ? makeButton(title: "继续", symbolName: "play.fill", action: #selector(resumeClicked))
                : makeButton(title: "暂停", symbolName: "pause.fill", action: #selector(pauseClicked))
        )
        let stopButton = makeButton(
            title: isStopping ? "正在停止" : "停止录制",
            symbolName: isStopping ? "hourglass" : "stop.fill",
            action: #selector(stopClicked)
        )
        stopButton.isEnabled = !isStopping
        stopButton.contentTintColor = isStopping ? .disabledControlTextColor : .labelColor
        buttonStackView.addArrangedSubview(stopButton)
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
        button.contentTintColor = .labelColor
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
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func formattedElapsed(_ elapsed: TimeInterval) -> String {
        let wholeSeconds = max(0, Int(elapsed.rounded(.down)))
        return String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    @objc private func pauseClicked(_ sender: NSButton) {
        onPause()
    }

    @objc private func resumeClicked(_ sender: NSButton) {
        onResume()
    }

    @objc private func stopClicked(_ sender: NSButton) {
        guard !isStopping else {
            return
        }
        setStopping(true)
        onStop()
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
