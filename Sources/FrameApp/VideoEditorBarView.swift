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

        startField.isEditable = false
        startField.isBordered = false
        startField.backgroundColor = .clear
        startField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        startField.alignment = .right

        endField.isEditable = false
        endField.isBordered = false
        endField.backgroundColor = .clear
        endField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        endField.alignment = .left

        speedControl.segmentCount = VideoPlaybackSpeed.presets.count
        for (index, speed) in VideoPlaybackSpeed.presets.enumerated() {
            speedControl.setLabel(speed.displayName, forSegment: index)
        }

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

    private func refresh() {
        startField.stringValue = Self.formatTime(state.startTime)
        endField.stringValue = Self.formatTime(state.endTime)
        if let selectedIndex = VideoPlaybackSpeed.presets.firstIndex(of: state.speed) {
            speedControl.selectedSegment = selectedIndex
        }
    }

    static func formatTime(_ time: TimeInterval) -> String {
        let clamped = max(0, time)
        let minutes = Int(clamped / 60)
        let seconds = clamped - TimeInterval(minutes * 60)
        return String(format: "%02d:%05.2f", minutes, seconds)
    }
}
