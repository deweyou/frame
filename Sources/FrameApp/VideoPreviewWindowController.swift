import AppKit
import AVKit
import FrameCore

@MainActor
final class VideoPreviewWindowController {
    private var items: [UUID: VideoPreviewItem] = [:]

    func show(
        recording: CapturedRecording,
        strings: AppStrings,
        copy: @escaping () -> Bool,
        download: @escaping () -> Bool,
        saveCurrent: @escaping (CapturedRecording, VideoEditingState) -> Bool,
        focusEditor: Bool = false
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

        let mediaView = makeMediaView(for: recording)
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        let editingState = recording.format == .mp4 ? try? VideoEditingState(sourceDuration: recording.duration) : nil
        let editorBar = editingState.map { VideoEditorBarView(state: $0) }

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
        root.addSubview(mediaView)
        if let editorBar {
            root.addSubview(editorBar)
        }

        var constraints = [
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            mediaView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mediaView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
        ]
        if let editorBar {
            constraints.append(contentsOf: [
                editorBar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
                editorBar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
                editorBar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
                mediaView.bottomAnchor.constraint(equalTo: editorBar.topAnchor),
            ])
        } else {
            constraints.append(mediaView.bottomAnchor.constraint(equalTo: root.bottomAnchor))
        }
        NSLayoutConstraint.activate(constraints)

        window.contentView = root
        items[recording.id] = VideoPreviewItem(
            recording: recording,
            window: window,
            editingState: editingState,
            saveCurrent: saveCurrent,
            isEditingEnabled: editingState != nil
        )
        if focusEditor {
            editorBar?.window?.makeFirstResponder(editorBar)
        }
        window.makeKeyAndOrderFront(nil)
    }

    func isEditingEnabledForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.isEditingEnabled ?? false
    }

    func windowForTesting(recordingID: UUID) -> NSWindow? {
        items[recordingID]?.window
    }

    func editingStateForTesting(recordingID: UUID) -> VideoEditingState? {
        items[recordingID]?.editingState
    }

    private func makeMediaView(for recording: CapturedRecording) -> NSView {
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
            let playerView = AVPlayerView()
            playerView.player = AVPlayer(url: recording.fileURL)
            playerView.controlsStyle = .floating
            return playerView
        }
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
    var editingState: VideoEditingState?
    let saveCurrent: (CapturedRecording, VideoEditingState) -> Bool
    let isEditingEnabled: Bool

    init(
        recording: CapturedRecording,
        window: NSWindow,
        editingState: VideoEditingState?,
        saveCurrent: @escaping (CapturedRecording, VideoEditingState) -> Bool,
        isEditingEnabled: Bool
    ) {
        self.recording = recording
        self.window = window
        self.editingState = editingState
        self.saveCurrent = saveCurrent
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
