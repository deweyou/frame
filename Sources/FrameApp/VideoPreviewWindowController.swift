import AppKit
import AVKit

@MainActor
final class VideoPreviewWindowController {
    private var items: [UUID: VideoPreviewItem] = [:]

    func show(
        recording: CapturedRecording,
        strings: AppStrings,
        copy: @escaping () -> Bool,
        download: @escaping () -> Bool
    ) {
        if let item = items[recording.id] {
            item.window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = recording.fileURL.lastPathComponent
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.center()

        let playerView = AVPlayerView()
        playerView.player = AVPlayer(url: recording.fileURL)
        playerView.controlsStyle = .floating
        playerView.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addArrangedSubview(makeButton(title: strings.videoQuickAccessCopy, symbolName: "doc.on.doc", action: copy))
        toolbar.addArrangedSubview(makeButton(title: strings.videoQuickAccessDownload, symbolName: "tray.and.arrow.down", action: download))
        toolbar.addArrangedSubview(makeDisabledButton(title: strings.videoQuickAccessEdit, symbolName: "slider.horizontal.3"))

        let root = NSView()
        root.addSubview(toolbar)
        root.addSubview(playerView)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            playerView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            playerView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            playerView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        window.contentView = root
        items[recording.id] = VideoPreviewItem(recording: recording, window: window, isEditingEnabled: false)
        window.makeKeyAndOrderFront(nil)
    }

    func isEditingEnabledForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.isEditingEnabled ?? false
    }

    private func makeButton(title: String, symbolName: String, action: @escaping () -> Bool) -> NSButton {
        let button = VideoPreviewActionButton(action: action)
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
}

private final class VideoPreviewItem {
    let recording: CapturedRecording
    let window: NSWindow
    let isEditingEnabled: Bool

    init(recording: CapturedRecording, window: NSWindow, isEditingEnabled: Bool) {
        self.recording = recording
        self.window = window
        self.isEditingEnabled = isEditingEnabled
    }
}

private final class VideoPreviewActionButton: NSButton {
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
