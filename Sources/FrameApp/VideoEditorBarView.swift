import AppKit
import FrameCore

@MainActor
final class VideoEditorBarView: NSView {
    private let startField = NSTextField()
    private let endField = NSTextField()
    private let speedControl = NSSegmentedControl()
    private(set) var state: VideoEditingState
    var onStateChanged: ((VideoEditingState) -> Void)?

    init(state: VideoEditingState) {
        self.state = state
        super.init(frame: .zero)
        setupView()
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateState(_ state: VideoEditingState) {
        self.state = state
        refresh()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        startField.isEditable = true
        startField.isBordered = true
        startField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        startField.alignment = .right
        startField.target = self
        startField.action = #selector(timeFieldChanged(_:))
        startField.identifier = NSUserInterfaceItemIdentifier("video-editor-start-field")

        endField.isEditable = true
        endField.isBordered = true
        endField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        endField.alignment = .left
        endField.target = self
        endField.action = #selector(timeFieldChanged(_:))
        endField.identifier = NSUserInterfaceItemIdentifier("video-editor-end-field")

        speedControl.segmentCount = VideoPlaybackSpeed.presets.count
        for (index, speed) in VideoPlaybackSpeed.presets.enumerated() {
            speedControl.setLabel(speed.displayName, forSegment: index)
        }
        speedControl.target = self
        speedControl.action = #selector(speedChanged(_:))

        let stack = NSStackView(views: [startField, speedControl, endField])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
    }

    @objc private func timeFieldChanged(_ sender: NSTextField) {
        applyTrimRange(startText: startField.stringValue, endText: endField.stringValue)
    }

    @objc private func speedChanged(_ sender: NSSegmentedControl) {
        let selectedSegment = sender.selectedSegment
        guard VideoPlaybackSpeed.presets.indices.contains(selectedSegment) else {
            refresh()
            return
        }

        applySpeed(VideoPlaybackSpeed.presets[selectedSegment])
    }

    private func refresh() {
        startField.stringValue = Self.formatTime(state.startTime)
        endField.stringValue = Self.formatTime(state.endTime)
        if let selectedIndex = VideoPlaybackSpeed.presets.firstIndex(of: state.speed) {
            speedControl.selectedSegment = selectedIndex
        }
    }

    private func applyTrimRange(startText: String, endText: String) {
        guard let startTime = Self.parseTime(startText),
              let endTime = Self.parseTime(endText) else {
            NSSound.beep()
            refresh()
            return
        }

        do {
            var nextState = state
            try nextState.setTrimRange(start: startTime, end: endTime)
            state = nextState
            refresh()
            onStateChanged?(nextState)
        } catch {
            NSSound.beep()
            refresh()
        }
    }

    private func applySpeed(_ speed: VideoPlaybackSpeed) {
        do {
            var nextState = state
            try nextState.setSpeed(speed)
            state = nextState
            refresh()
            onStateChanged?(nextState)
        } catch {
            NSSound.beep()
            refresh()
        }
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let minutes = Int(clamped / 60)
        let seconds = clamped - TimeInterval(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }

    static func parseTime(_ string: String) -> TimeInterval? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
        if parts.count == 1 {
            return TimeInterval(parts[0])
        }

        guard parts.count == 2,
              let minutes = TimeInterval(parts[0]),
              let seconds = TimeInterval(parts[1]) else {
            return nil
        }

        return minutes * 60 + seconds
    }

    func enterTrimRangeForTesting(start: String, end: String) {
        startField.stringValue = start
        endField.stringValue = end
        applyTrimRange(startText: start, endText: end)
    }

    func selectSpeedForTesting(_ speed: VideoPlaybackSpeed) {
        guard let index = VideoPlaybackSpeed.presets.firstIndex(of: speed) else {
            return
        }

        speedControl.selectedSegment = index
        applySpeed(speed)
    }
}
