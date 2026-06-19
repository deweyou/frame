import AppKit
import AVKit
import FrameCore

enum VideoPreviewSaveChoice: Equatable {
    case replaceCurrent
    case saveAsNew
}

enum VideoPreviewCloseChoice: Equatable {
    case replaceCurrent
    case saveAsNew
    case discard
    case cancel
}

@MainActor
final class VideoPreviewWindowController: NSObject, NSWindowDelegate {
    private var items: [UUID: VideoPreviewItem] = [:]
    private let closeChoiceProvider: @MainActor (AppStrings, CapturedRecording, VideoEditingState) -> VideoPreviewCloseChoice

    init(
        closeChoiceProvider: @escaping @MainActor (AppStrings, CapturedRecording, VideoEditingState) -> VideoPreviewCloseChoice = VideoPreviewWindowController.presentCloseChoice
    ) {
        self.closeChoiceProvider = closeChoiceProvider
        super.init()
    }

    func show(
        recording: CapturedRecording,
        strings: AppStrings,
        copy: @escaping (CapturedRecording, VideoEditingState?) -> Bool,
        download: @escaping (CapturedRecording, VideoEditingState?) -> Bool,
        saveCurrent: @escaping (CapturedRecording, VideoEditingState, VideoPreviewSaveChoice) -> Bool,
        focusEditor: Bool = false
    ) {
        if let item = items[recording.id] {
            item.window.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = recording.fileURL.lastPathComponent
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        let media = makeMediaView(for: recording)
        let mediaView = media.view
        mediaView.translatesAutoresizingMaskIntoConstraints = false
        let editingState = recording.format == .mp4 ? try? VideoEditingState(sourceDuration: recording.duration) : nil
        let editorBar = editingState.map { VideoEditorBarView(state: $0, strings: strings) }
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
        let headerSpacer = NSView()
        headerSpacer.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addArrangedSubview(headerSpacer)
        if editingState != nil {
            toolbar.addArrangedSubview(
                makeSaveCurrentButton(
                    title: strings.workspaceSaveCurrent,
                    symbolName: "checkmark.circle",
                    replaceTitle: strings.videoReplaceCurrent,
                    saveAsNewTitle: strings.videoSaveAsNew,
                    action: { [weak self] choice in
                        self?.performSaveCurrent(recordingID: recording.id, choice: choice) ?? false
                    }
                )
            )
        }
        toolbar.addArrangedSubview(
            makeButton(
                title: strings.videoQuickAccessCopy,
                symbolName: "doc.on.doc",
                action: { [weak self] in
                    self?.performCopy(recordingID: recording.id) ?? false
                }
            )
        )
        toolbar.addArrangedSubview(
            makeButton(
                title: strings.videoQuickAccessDownload,
                symbolName: "tray.and.arrow.down",
                action: { [weak self] in
                    self?.performDownload(recordingID: recording.id) ?? false
                }
            )
        )

        let header = makeHeaderView()
        header.addSubview(toolbar)

        let root = NSView()
        root.addSubview(header)
        root.addSubview(mediaView)
        if let editorBar {
            root.addSubview(editorBar)
        }

        var constraints = [
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 32),
            toolbar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 88),
            toolbar.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -6),
            toolbar.topAnchor.constraint(equalTo: header.topAnchor, constant: 2),
            toolbar.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -2),
            mediaView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            mediaView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            mediaView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
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
            strings: strings,
            window: window,
            editingState: editingState,
            editorBar: editorBar,
            player: media.player,
            playerTimeObserver: playerTimeObserver,
            copy: copy,
            download: download,
            saveCurrent: saveCurrent,
            isEditingEnabled: editingState != nil
        )
        editorBar?.onStateChanged = { [weak self] state in
            self?.updateEditingState(recordingID: recording.id, state: state)
        }
        editorBar?.onPlayPauseRequested = { [weak self] in
            self?.togglePlayback(recordingID: recording.id)
        }
        editorBar?.onSeekRequested = { [weak self] time in
            self?.seekPlayback(recordingID: recording.id, time: time)
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

    func performSaveCurrentForTesting(recordingID: UUID, choice: VideoPreviewSaveChoice) -> Bool {
        performSaveCurrent(recordingID: recordingID, choice: choice)
    }

    func performCopyForTesting(recordingID: UUID) -> Bool {
        performCopy(recordingID: recordingID)
    }

    func performDownloadForTesting(recordingID: UUID) -> Bool {
        performDownload(recordingID: recordingID)
    }

    func windowShouldCloseForTesting(recordingID: UUID) -> Bool {
        guard let window = items[recordingID]?.window else {
            return true
        }

        return windowShouldClose(window)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let item = item(for: sender),
              let state = item.editingState,
              state.isDirty else {
            return true
        }

        switch closeChoiceProvider(item.strings, item.recording, state) {
        case .replaceCurrent:
            return item.saveCurrent(item.recording, state, .replaceCurrent)
        case .saveAsNew:
            return item.saveCurrent(item.recording, state, .saveAsNew)
        case .discard:
            return true
        case .cancel:
            return false
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let item = item(for: window) else {
            return
        }

        items.removeValue(forKey: item.recording.id)
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
            playerView.controlsStyle = .none
            return (playerView, player)
        }
    }

    private func stopPlaybackIfNeeded(player: AVPlayer, recordingID: UUID, time: CMTime) {
        guard let item = items[recordingID],
              let state = item.editingState,
              player.rate > 0 else {
            return
        }

        item.editorBar?.updatePlayback(time: time.seconds, isPlaying: true)
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
        item.editorBar?.updatePlayback(time: state.endTime, isPlaying: false)
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
        item.editorBar?.updatePlayback(time: player.currentTime().seconds, isPlaying: player.rate > 0)
    }

    private func togglePlayback(recordingID: UUID) {
        guard let item = items[recordingID],
              let player = item.player,
              let state = item.editingState else {
            return
        }

        if player.rate > 0 {
            player.pause()
            item.editorBar?.updatePlayback(time: player.currentTime().seconds, isPlaying: false)
            return
        }

        let currentTime = player.currentTime().seconds
        if currentTime < state.startTime || currentTime >= state.endTime {
            player.seek(
                to: CMTime(seconds: state.startTime, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
            item.editorBar?.updatePlayback(time: state.startTime, isPlaying: true)
        }
        player.rate = Float(state.speed.rate)
    }

    private func seekPlayback(recordingID: UUID, time: TimeInterval) {
        guard let item = items[recordingID],
              let player = item.player else {
            return
        }

        player.seek(
            to: CMTime(seconds: time, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        item.editorBar?.updatePlayback(time: time, isPlaying: player.rate > 0)
    }

    private func makeButton(title: String, symbolName: String, action: @escaping () -> Bool) -> NSButton {
        let button = VideoPreviewActionButton(action: action)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        button.title = ""
        button.imagePosition = .imageOnly
        button.toolTip = title
        button.setAccessibilityLabel(title)
        configureActionButton(button)
        return button
    }

    private func makeHeaderView() -> NSVisualEffectView {
        let header = NSVisualEffectView()
        header.material = .hudWindow
        header.blendingMode = .withinWindow
        header.state = .active
        header.alphaValue = 1
        header.wantsLayer = true
        header.layer?.cornerRadius = 16
        header.layer?.cornerCurve = .continuous
        header.layer?.masksToBounds = true
        header.layer?.borderWidth = 0.5
        header.layer?.borderColor = NSColor.white.withAlphaComponent(0.38).cgColor
        header.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        return header
    }

    private func makeDisabledButton(title: String, symbolName: String) -> NSButton {
        let button = makeButton(title: title, symbolName: symbolName, action: { false })
        button.isEnabled = false
        button.contentTintColor = .disabledControlTextColor
        return button
    }

    private func makeSaveCurrentButton(
        title: String,
        symbolName: String,
        replaceTitle: String,
        saveAsNewTitle: String,
        action: @escaping (VideoPreviewSaveChoice) -> Bool
    ) -> NSButton {
        let button = VideoPreviewSaveButton(
            title: title,
            symbolName: symbolName,
            replaceTitle: replaceTitle,
            saveAsNewTitle: saveAsNewTitle,
            action: action
        )
        configureActionButton(button)
        return button
    }

    private func configureActionButton(_ button: NSButton) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 26),
            button.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    private func performSaveCurrent(recordingID: UUID, choice: VideoPreviewSaveChoice) -> Bool {
        guard let item = items[recordingID],
              let state = item.editingState,
              state.isDirty else {
            return false
        }

        return item.saveCurrent(item.recording, state, choice)
    }

    private func performCopy(recordingID: UUID) -> Bool {
        guard let item = items[recordingID] else {
            return false
        }

        return item.copy(item.recording, dirtyEditingState(for: item))
    }

    private func performDownload(recordingID: UUID) -> Bool {
        guard let item = items[recordingID] else {
            return false
        }

        return item.download(item.recording, dirtyEditingState(for: item))
    }

    private func dirtyEditingState(for item: VideoPreviewItem) -> VideoEditingState? {
        guard let state = item.editingState,
              state.isDirty else {
            return nil
        }

        return state
    }

    private func item(for window: NSWindow) -> VideoPreviewItem? {
        items.values.first { $0.window === window }
    }

    private static func presentCloseChoice(
        strings: AppStrings,
        recording: CapturedRecording,
        state: VideoEditingState
    ) -> VideoPreviewCloseChoice {
        let alert = NSAlert()
        alert.messageText = strings.workspaceUnsavedChangesTitle
        alert.informativeText = strings.videoUnsavedChangesMessage
        alert.addButton(withTitle: strings.videoReplaceCurrent)
        alert.addButton(withTitle: strings.videoSaveAsNew)
        alert.addButton(withTitle: strings.workspaceDiscardEdits)
        alert.addButton(withTitle: strings.cancel)

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replaceCurrent
        case .alertSecondButtonReturn:
            return .saveAsNew
        case .alertThirdButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }
}

private final class VideoPreviewItem {
    let recording: CapturedRecording
    let strings: AppStrings
    let window: NSWindow
    var editingState: VideoEditingState?
    weak var editorBar: VideoEditorBarView?
    let player: AVPlayer?
    let playerTimeObserver: Any?
    let copy: (CapturedRecording, VideoEditingState?) -> Bool
    let download: (CapturedRecording, VideoEditingState?) -> Bool
    let saveCurrent: (CapturedRecording, VideoEditingState, VideoPreviewSaveChoice) -> Bool
    let isEditingEnabled: Bool

    init(
        recording: CapturedRecording,
        strings: AppStrings,
        window: NSWindow,
        editingState: VideoEditingState?,
        editorBar: VideoEditorBarView?,
        player: AVPlayer?,
        playerTimeObserver: Any?,
        copy: @escaping (CapturedRecording, VideoEditingState?) -> Bool,
        download: @escaping (CapturedRecording, VideoEditingState?) -> Bool,
        saveCurrent: @escaping (CapturedRecording, VideoEditingState, VideoPreviewSaveChoice) -> Bool,
        isEditingEnabled: Bool
    ) {
        self.recording = recording
        self.strings = strings
        self.window = window
        self.editingState = editingState
        self.editorBar = editorBar
        self.player = player
        self.playerTimeObserver = playerTimeObserver
        self.copy = copy
        self.download = download
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

private final class VideoPreviewSaveButton: NSButton {
    private let replaceTitle: String
    private let saveAsNewTitle: String
    private let handler: (VideoPreviewSaveChoice) -> Bool

    init(
        title: String,
        symbolName: String,
        replaceTitle: String,
        saveAsNewTitle: String,
        action: @escaping (VideoPreviewSaveChoice) -> Bool
    ) {
        self.replaceTitle = replaceTitle
        self.saveAsNewTitle = saveAsNewTitle
        self.handler = action
        super.init(frame: .zero)
        image = NSImage(systemSymbolName: symbolName, accessibilityDescription: title)
        self.title = ""
        imagePosition = .imageOnly
        isBordered = false
        toolTip = title
        setAccessibilityLabel(title)
        target = self
        self.action = #selector(showMenu(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @objc private func showMenu(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(makeItem(title: replaceTitle, choice: .replaceCurrent))
        menu.addItem(makeItem(title: saveAsNewTitle, choice: .saveAsNew))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func chooseMenuItem(_ sender: NSMenuItem) {
        let choice: VideoPreviewSaveChoice = sender.tag == 0 ? .replaceCurrent : .saveAsNew
        _ = handler(choice)
    }

    private func makeItem(title: String, choice: VideoPreviewSaveChoice) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(chooseMenuItem(_:)), keyEquivalent: "")
        item.target = self
        item.tag = choice == .replaceCurrent ? 0 : 1
        return item
    }
}
