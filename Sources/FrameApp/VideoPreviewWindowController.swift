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

        let media = makeMediaView(for: recording)
        let mediaView = media.view
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        let editingState = recording.format == .mp4 ? try? VideoEditingState(sourceDuration: recording.duration) : nil
        let editorBar = editingState.map { VideoEditorBarView(state: $0) }
        let playerTimeObserver = media.player.map { player in
            player.addPeriodicTimeObserver(
                forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
                queue: .main
            ) { [weak self, weak player] time in
                Task { @MainActor [weak self, weak player] in
                    guard let self, let player else {
                        return
                    }

                    self.stopPlaybackIfNeeded(player: player, recordingID: recording.id, time: time)
                }
            }
        }

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
            editorBar: editorBar,
            player: media.player,
            playerTimeObserver: playerTimeObserver,
            saveCurrent: saveCurrent,
            isEditingEnabled: editingState != nil
        )
        editorBar?.onStateChanged = { [weak self] state in
            self?.updateEditingState(recordingID: recording.id, state: state)
        }
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

    func setTrimRangeForTesting(recordingID: UUID, start: TimeInterval, end: TimeInterval) throws {
        guard let item = items[recordingID], var state = item.editingState else {
            return
        }

        try state.setTrimRange(start: start, end: end)
        updateEditingState(recordingID: recordingID, state: state)
    }

    func setSpeedForTesting(recordingID: UUID, speed: VideoPlaybackSpeed) throws {
        guard let item = items[recordingID], var state = item.editingState else {
            return
        }

        try state.setSpeed(speed)
        updateEditingState(recordingID: recordingID, state: state)
    }

    func hasUnsavedEditsForTesting(recordingID: UUID) -> Bool {
        items[recordingID]?.editingState?.isDirty ?? false
    }

    func playbackRangeForTesting(recordingID: UUID) -> CMTimeRange? {
        guard let state = items[recordingID]?.editingState else {
            return nil
        }

        return CMTimeRange(
            start: CMTime(seconds: state.startTime, preferredTimescale: 600),
            end: CMTime(seconds: state.endTime, preferredTimescale: 600)
        )
    }

    private func makeMediaView(for recording: CapturedRecording) -> (view: NSView, player: AVPlayer?) {
        switch recording.format {
        case .gif:
            let imageView = NSImageView()
            imageView.image = NSImage(contentsOf: recording.fileURL)
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.animates = true
            imageView.wantsLayer = true
            imageView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return (imageView, nil)
        case .mp4:
            let playerView = AVPlayerView()
            let player = AVPlayer(url: recording.fileURL)
            playerView.player = player
            playerView.controlsStyle = .floating
            return (playerView, player)
        }
    }

    private func stopPlaybackIfNeeded(player: AVPlayer, recordingID: UUID, time: CMTime) {
        guard let state = items[recordingID]?.editingState,
              player.rate > 0 else {
            return
        }

        if time.seconds < state.startTime {
            player.seek(
                to: CMTime(seconds: state.startTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            player.rate = Float(state.speed.rate)
            return
        }

        if abs(player.rate - Float(state.speed.rate)) > 0.001 {
            player.rate = Float(state.speed.rate)
        }

        guard time.seconds >= state.endTime else {
            return
        }

        player.pause()
        player.seek(
            to: CMTime(seconds: state.endTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private func updateEditingState(recordingID: UUID, state: VideoEditingState) {
        guard let item = items[recordingID] else {
            return
        }

        item.editingState = state
        item.editorBar?.updateState(state)

        guard let player = item.player else {
            return
        }

        let currentTime = player.currentTime().seconds
        if currentTime < state.startTime || currentTime > state.endTime {
            player.seek(
                to: CMTime(seconds: state.startTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        if player.rate > 0 {
            player.rate = Float(state.speed.rate)
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
    weak var editorBar: VideoEditorBarView?
    let player: AVPlayer?
    let playerTimeObserver: Any?
    let saveCurrent: (CapturedRecording, VideoEditingState) -> Bool
    let isEditingEnabled: Bool

    init(
        recording: CapturedRecording,
        window: NSWindow,
        editingState: VideoEditingState?,
        editorBar: VideoEditorBarView?,
        player: AVPlayer?,
        playerTimeObserver: Any?,
        saveCurrent: @escaping (CapturedRecording, VideoEditingState) -> Bool,
        isEditingEnabled: Bool
    ) {
        self.recording = recording
        self.window = window
        self.editingState = editingState
        self.editorBar = editorBar
        self.player = player
        self.playerTimeObserver = playerTimeObserver
        self.saveCurrent = saveCurrent
        self.isEditingEnabled = isEditingEnabled
    }

    deinit {
        if let playerTimeObserver, let player {
            player.removeTimeObserver(playerTimeObserver)
        }
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
