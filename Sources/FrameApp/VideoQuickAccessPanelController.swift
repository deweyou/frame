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

        let panel = makePanel()
        let item = VideoQuickAccessItem(
            recording: recording,
            panel: panel,
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
        panel.contentView = makeContentView(item: item, strings: strings, download: download, copy: copy, preview: preview)
        position(panel, preferredAnchor: preferredAnchor)
        panel.orderFrontRegardless()
    }

    func actionLabelsForTesting(recordingID: UUID) -> [String] {
        items[recordingID]?.actionLabels ?? []
    }

    func isEditEnabledForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.isEditEnabled ?? false
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 224, height: 176),
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
        return panel
    }

    private func makeContentView(
        item: VideoQuickAccessItem,
        strings: AppStrings,
        download: @escaping () -> Bool,
        copy: @escaping () -> Bool,
        preview: @escaping () -> Bool
    ) -> NSView {
        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 8
        root.layer?.cornerCurve = .continuous
        root.layer?.masksToBounds = true

        let title = NSTextField(labelWithString: item.recording.fileURL.lastPathComponent)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.lineBreakMode = .byTruncatingMiddle
        title.translatesAutoresizingMaskIntoConstraints = false

        let duration = NSTextField(labelWithString: formattedDuration(item.recording.duration))
        duration.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        duration.translatesAutoresizingMaskIntoConstraints = false

        let actions = NSStackView()
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 6
        actions.translatesAutoresizingMaskIntoConstraints = false
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessDownload, symbolName: "tray.and.arrow.down", action: download))
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessCopy, symbolName: "doc.on.doc", action: copy))
        actions.addArrangedSubview(makeButton(title: strings.videoQuickAccessPreview, symbolName: "play.rectangle", action: preview))
        actions.addArrangedSubview(makeDisabledButton(title: strings.videoQuickAccessEdit, symbolName: "slider.horizontal.3"))
        actions.addArrangedSubview(makeButton(title: strings.quickAccessClose, symbolName: "xmark", action: { [weak self, weak item] in
            guard let item else {
                return false
            }
            self?.items[item.recording.id] = nil
            item.panel.orderOut(nil)
            item.close()
            return true
        }))

        root.addSubview(title)
        root.addSubview(duration)
        root.addSubview(actions)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            title.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            duration.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            duration.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            actions.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            actions.trailingAnchor.constraint(lessThanOrEqualTo: title.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
        ])

        return root
    }

    private func makeButton(title: String, symbolName: String, action: @escaping () -> Bool) -> NSButton {
        let button = VideoQuickAccessActionButton(action: action)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.title = ""
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.toolTip = title
        button.setAccessibilityLabel(title)
        return button
    }

    private func makeDisabledButton(title: String, symbolName: String) -> NSButton {
        let button = makeButton(title: title, symbolName: symbolName, action: { false })
        button.isEnabled = false
        button.contentTintColor = .disabledControlTextColor
        return button
    }

    private func position(_ panel: NSPanel, preferredAnchor: CGRect?) {
        let anchor = preferredAnchor ?? NSScreen.main?.frame ?? .zero
        let origin = CGPoint(x: anchor.minX + 18, y: anchor.minY + 18)
        panel.setFrameOrigin(origin)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded(.down)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

private final class VideoQuickAccessItem {
    let recording: CapturedRecording
    let panel: NSPanel
    let actionLabels: [String]
    let isEditEnabled: Bool
    let close: () -> Void

    init(
        recording: CapturedRecording,
        panel: NSPanel,
        actionLabels: [String],
        isEditEnabled: Bool,
        close: @escaping () -> Void
    ) {
        self.recording = recording
        self.panel = panel
        self.actionLabels = actionLabels
        self.isEditEnabled = isEditEnabled
        self.close = close
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
