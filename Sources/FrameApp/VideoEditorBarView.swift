import AppKit
import FrameCore

private enum VideoEditorBarMetrics {
    static let timelineInset: CGFloat = 18
    static let timelineTrackInset: CGFloat = 7
    static let controlInset: CGFloat = timelineInset + timelineTrackInset
    static let speedTokenWidth: CGFloat = 124
    static let speedPopupWidth: CGFloat = 68
}

@MainActor
final class VideoEditorBarView: NSView {
    private let strings: AppStrings
    private let backgroundView = NSVisualEffectView()
    private let playPauseButton = VideoEditorTransportButton()
    private let playbackSummaryLabel = NSTextField(labelWithString: "")
    private let speedLabel: NSTextField
    private let speedPopupButton = NSPopUpButton()
    private let timelineView: VideoTrimTimelineView
    private(set) var state: VideoEditingState
    private var playbackTime: TimeInterval
    var onStateChanged: ((VideoEditingState) -> Void)?
    var onPlayPauseRequested: (() -> Void)?
    var onSeekRequested: ((TimeInterval) -> Void)?

    init(state: VideoEditingState, strings: AppStrings = .current()) {
        self.strings = strings
        self.state = state
        self.playbackTime = state.startTime
        self.timelineView = VideoTrimTimelineView(state: state)
        self.speedLabel = VideoEditorBarView.makeTokenLabel(strings.videoEditorSpeedShort)
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
        playbackTime = min(max(playbackTime, state.startTime), state.endTime)
        refresh()
    }

    private func setupView() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        backgroundView.material = .contentBackground
        backgroundView.blendingMode = .withinWindow
        backgroundView.state = .active
        backgroundView.wantsLayer = true
        backgroundView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.86).cgColor
        backgroundView.layer?.borderWidth = 0.5
        backgroundView.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        backgroundView.translatesAutoresizingMaskIntoConstraints = false

        playPauseButton.symbolName = "play.fill"
        playPauseButton.target = self
        playPauseButton.action = #selector(playPauseClicked)
        playPauseButton.toolTip = strings.videoEditorPlayPause
        playPauseButton.setAccessibilityLabel(strings.videoEditorPlayPause)
        playPauseButton.translatesAutoresizingMaskIntoConstraints = false

        playbackSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        playbackSummaryLabel.textColor = .secondaryLabelColor
        playbackSummaryLabel.setContentHuggingPriority(.required, for: .horizontal)
        playbackSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        playbackSummaryLabel.lineBreakMode = .byTruncatingMiddle

        speedPopupButton.removeAllItems()
        for speed in VideoPlaybackSpeed.presets {
            speedPopupButton.addItem(withTitle: speed.displayName)
        }
        speedPopupButton.target = self
        speedPopupButton.action = #selector(speedChanged(_:))
        speedPopupButton.controlSize = .small
        speedPopupButton.isBordered = false
        speedPopupButton.font = .systemFont(ofSize: 11, weight: .semibold)
        speedPopupButton.toolTip = strings.videoEditorPlaybackSpeed
        speedPopupButton.setAccessibilityLabel(strings.videoEditorPlaybackSpeed)
        speedPopupButton.translatesAutoresizingMaskIntoConstraints = false
        speedPopupButton.setContentHuggingPriority(.required, for: .horizontal)
        speedPopupButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        timelineView.translatesAutoresizingMaskIntoConstraints = false
        timelineView.setTimeFieldAccessibilityLabels(
            start: strings.videoEditorStartTime,
            end: strings.videoEditorEndTime
        )
        timelineView.onTrimRangeChanged = { [weak self] start, end in
            self?.applyTrimRange(startTime: start, endTime: end)
        }
        timelineView.onSeekRequested = { [weak self] time in
            self?.onSeekRequested?(time)
        }

        let speedToken = makeTokenView(label: speedLabel, control: speedPopupButton, style: .plain)
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let bottomRow = NSStackView(views: [
            playPauseButton,
            playbackSummaryLabel,
            spacer,
            speedToken,
        ])
        bottomRow.orientation = .horizontal
        bottomRow.alignment = .centerY
        bottomRow.distribution = .fill
        bottomRow.spacing = 10
        bottomRow.translatesAutoresizingMaskIntoConstraints = false

        addSubview(backgroundView)
        addSubview(timelineView)
        addSubview(bottomRow)

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            timelineView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: VideoEditorBarMetrics.timelineInset),
            timelineView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -VideoEditorBarMetrics.timelineInset),
            timelineView.topAnchor.constraint(equalTo: topAnchor, constant: 11),
            timelineView.heightAnchor.constraint(equalToConstant: 40),

            bottomRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: VideoEditorBarMetrics.controlInset),
            bottomRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -VideoEditorBarMetrics.controlInset),
            bottomRow.topAnchor.constraint(equalTo: timelineView.bottomAnchor, constant: 8),
            bottomRow.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),

            playPauseButton.widthAnchor.constraint(equalToConstant: 28),
            playPauseButton.heightAnchor.constraint(equalToConstant: 28),
            speedToken.widthAnchor.constraint(equalToConstant: VideoEditorBarMetrics.speedTokenWidth),
            speedPopupButton.widthAnchor.constraint(equalToConstant: VideoEditorBarMetrics.speedPopupWidth),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 92),
        ])
    }

    @objc private func speedChanged(_ sender: NSPopUpButton) {
        let selectedIndex = sender.indexOfSelectedItem
        guard VideoPlaybackSpeed.presets.indices.contains(selectedIndex) else {
            refresh()
            return
        }

        applySpeed(VideoPlaybackSpeed.presets[selectedIndex])
    }

    @objc private func playPauseClicked() {
        onPlayPauseRequested?()
    }

    private func refresh() {
        playbackSummaryLabel.stringValue = playbackSummaryText()
        if let selectedIndex = VideoPlaybackSpeed.presets.firstIndex(of: state.speed) {
            speedPopupButton.selectItem(at: selectedIndex)
        }
        timelineView.updateState(state)
    }

    private func playbackSummaryText() -> String {
        let selectedSummary = "\(Self.formatTime(playbackTime)) / \(Self.formatTime(state.selectedDuration))"
        guard state.speed != .one else {
            return selectedSummary
        }

        return "\(selectedSummary) · \(strings.videoEditorOutputDurationShort) \(Self.formatTime(state.outputDuration))"
    }

    private func applyTrimRange(startTime: TimeInterval, endTime: TimeInterval) {
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

    func selectSpeedForTesting(_ speed: VideoPlaybackSpeed) {
        guard let index = VideoPlaybackSpeed.presets.firstIndex(of: speed) else {
            return
        }

        speedPopupButton.selectItem(at: index)
        applySpeed(speed)
    }

    func updatePlayback(time: TimeInterval, isPlaying: Bool) {
        playbackTime = min(max(time, state.startTime), state.endTime)
        timelineView.updatePlaybackTime(time)
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.symbolName = symbolName
        refresh()
    }

    var hasTimelineForTesting: Bool {
        timelineView.superview != nil
    }

    var hasSpeedDropdownForTesting: Bool {
        speedPopupButton.superview != nil
    }

    var hasTransportSummaryForTesting: Bool {
        playbackSummaryLabel.superview != nil
    }

    var playbackSummaryTextForTesting: String {
        playbackSummaryLabel.stringValue
    }

    var hasTrimRangeLabelsForTesting: Bool {
        timelineView.hasTimeLabelsForTesting
    }

    var hasEditableTrimTimeLabelsForTesting: Bool {
        timelineView.hasEditableTimeLabelsForTesting
    }

    var trimTimeLabelsPassThroughHitTestingForTesting: Bool {
        timelineView.timeLabelsPassThroughHitTestingForTesting
    }

    var timelineUsesPointingCursorForTesting: Bool {
        timelineView.usesPointingCursorForTesting
    }

    var hasInlineTrimTokenForTesting: Bool {
        false
    }

    var startFieldAccessibilityLabelForTesting: String? {
        timelineView.startFieldAccessibilityLabelForTesting
    }

    var endFieldAccessibilityLabelForTesting: String? {
        timelineView.endFieldAccessibilityLabelForTesting
    }

    var speedDropdownAccessibilityLabelForTesting: String? {
        speedPopupButton.accessibilityLabel()
    }

    func moveStartHandleForTesting(to time: TimeInterval) {
        timelineView.moveStartHandleForTesting(to: time)
    }

    func seekTimelineForTesting(to time: TimeInterval) {
        timelineView.seekForTesting(to: time)
    }

    func performPlayPauseForTesting() {
        playPauseClicked()
    }

    private func makeTokenView(label: NSTextField, control: NSControl, style: TokenStyle) -> NSView {
        let token = makeTokenShell(style: style)
        token.setContentHuggingPriority(.required, for: .horizontal)
        token.setContentCompressionResistancePriority(.required, for: .horizontal)

        label.translatesAutoresizingMaskIntoConstraints = false
        control.translatesAutoresizingMaskIntoConstraints = false
        token.addSubview(label)
        token.addSubview(control)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: token.leadingAnchor, constant: 9),
            label.centerYAnchor.constraint(equalTo: token.centerYAnchor),
            control.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
            control.trailingAnchor.constraint(equalTo: token.trailingAnchor, constant: -8),
            control.centerYAnchor.constraint(equalTo: token.centerYAnchor),
            token.heightAnchor.constraint(equalToConstant: 26),
        ])

        return token
    }

    private func makeTokenShell(style: TokenStyle) -> NSView {
        let token = NSView()
        token.wantsLayer = true
        token.layer?.cornerRadius = 13
        token.layer?.cornerCurve = .continuous
        token.layer?.backgroundColor = style.backgroundColor.cgColor
        token.layer?.borderWidth = 0
        token.translatesAutoresizingMaskIntoConstraints = false
        return token
    }

    private static func makeTokenLabel(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .tertiaryLabelColor
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }

    private enum TokenStyle {
        case plain

        var backgroundColor: NSColor {
            switch self {
            case .plain:
                NSColor.controlBackgroundColor.withAlphaComponent(0.24)
            }
        }
    }
}

final class VideoTrimTimelineView: NSView {
    var onTrimRangeChanged: ((TimeInterval, TimeInterval) -> Void)?
    var onSeekRequested: ((TimeInterval) -> Void)?

    private let startField = VideoTrimTimeLabelField()
    private let endField = VideoTrimTimeLabelField()
    private var state: VideoEditingState
    private var playbackTime: TimeInterval
    private var dragTarget: DragTarget?
    private var trackingArea: NSTrackingArea?

    init(state: VideoEditingState) {
        self.state = state
        self.playbackTime = state.startTime
        super.init(frame: .zero)
        wantsLayer = true
        setupTimeFields()
        refreshTimeFields()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 40)
    }

    func updateState(_ state: VideoEditingState) {
        self.state = state
        playbackTime = min(max(playbackTime, state.startTime), state.endTime)
        refreshTimeFields()
        needsDisplay = true
        needsLayout = true
    }

    func updatePlaybackTime(_ time: TimeInterval) {
        playbackTime = min(max(time, state.startTime), state.endTime)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let strip = stripRect
        NSColor.controlBackgroundColor.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: strip, xRadius: 9, yRadius: 9).fill()
        NSColor.separatorColor.withAlphaComponent(0.18).setStroke()
        NSBezierPath(roundedRect: strip, xRadius: 9, yRadius: 9).stroke()

        let selectedRect = selectedRect
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: strip, xRadius: 9, yRadius: 9).addClip()
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(rect: selectedRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.controlAccentColor.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: CGRect(
            x: xPosition(for: state.startTime),
            y: strip.minY,
            width: 2,
            height: strip.height
        ), xRadius: 1, yRadius: 1).fill()
        NSBezierPath(roundedRect: CGRect(
            x: xPosition(for: state.endTime) - 2,
            y: strip.minY,
            width: 2,
            height: strip.height
        ), xRadius: 1, yRadius: 1).fill()

        drawHandle(centerX: xPosition(for: state.startTime), strip: strip)
        drawHandle(centerX: xPosition(for: state.endTime), strip: strip)

        let playheadX = xPosition(for: playbackTime)
        let playheadPath = NSBezierPath(roundedRect: CGRect(
            x: playheadX - 1,
            y: strip.minY - 2,
            width: 2,
            height: strip.height + 4
        ), xRadius: 0.75, yRadius: 0.75)
        NSColor.labelColor.withAlphaComponent(0.64).setFill()
        playheadPath.fill()
    }

    override func layout() {
        super.layout()
        layoutTimeFields()
        window?.invalidateCursorRects(for: self)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(stripRect, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if stripRect.contains(point) {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragTarget = target(at: point)
        applyDrag(at: point)
    }

    override func mouseDragged(with event: NSEvent) {
        applyDrag(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        applyDrag(at: convert(event.locationInWindow, from: nil))
        dragTarget = nil
    }

    func moveStartHandleForTesting(to time: TimeInterval) {
        applyTrim(start: time, end: state.endTime)
    }

    func seekForTesting(to time: TimeInterval) {
        seek(to: time)
    }

    func setTimeFieldAccessibilityLabels(start: String, end: String) {
        startField.setAccessibilityLabel(start)
        endField.setAccessibilityLabel(end)
    }

    var hasTimeLabelsForTesting: Bool {
        startField.superview != nil && endField.superview != nil
    }

    var hasEditableTimeLabelsForTesting: Bool {
        startField.isEditable || endField.isEditable
    }

    var timeLabelsPassThroughHitTestingForTesting: Bool {
        startField.hitTest(CGPoint(x: startField.bounds.midX, y: startField.bounds.midY)) == nil
            && endField.hitTest(CGPoint(x: endField.bounds.midX, y: endField.bounds.midY)) == nil
    }

    var usesPointingCursorForTesting: Bool {
        true
    }

    var startFieldAccessibilityLabelForTesting: String? {
        startField.accessibilityLabel()
    }

    var endFieldAccessibilityLabelForTesting: String? {
        endField.accessibilityLabel()
    }

    var timeLabelPlacementForTesting: VideoTrimTimeLabelPlacement {
        timeLabelPlacement()
    }

    private var stripRect: CGRect {
        CGRect(
            x: bounds.minX + VideoTrimTimelineMetrics.trackInset,
            y: bounds.midY - 17,
            width: max(1, bounds.width - VideoTrimTimelineMetrics.trackInset * 2),
            height: 34
        )
    }

    private var selectedRect: CGRect {
        CGRect(
            x: xPosition(for: state.startTime),
            y: stripRect.minY,
            width: max(2, xPosition(for: state.endTime) - xPosition(for: state.startTime)),
            height: stripRect.height
        )
    }

    private func target(at point: CGPoint) -> DragTarget {
        let startDistance = abs(point.x - xPosition(for: state.startTime))
        let endDistance = abs(point.x - xPosition(for: state.endTime))
        if startDistance <= 10, startDistance <= endDistance {
            return .start
        }
        if endDistance <= 10 {
            return .end
        }
        return .playhead
    }

    private func applyDrag(at point: CGPoint) {
        let time = time(for: point.x)
        switch dragTarget ?? .playhead {
        case .start:
            applyTrim(start: time, end: state.endTime)
        case .end:
            applyTrim(start: state.startTime, end: time)
        case .playhead:
            seek(to: time)
        }
    }

    private func applyTrim(start: TimeInterval, end: TimeInterval) {
        do {
            var nextState = state
            try nextState.setTrimRange(start: start, end: end)
            state = nextState
            playbackTime = min(max(playbackTime, state.startTime), state.endTime)
            refreshTimeFields()
            needsDisplay = true
            needsLayout = true
            onTrimRangeChanged?(state.startTime, state.endTime)
        } catch {
            NSSound.beep()
            needsDisplay = true
        }
    }

    private func seek(to time: TimeInterval) {
        let clampedTime = min(max(time, state.startTime), state.endTime)
        playbackTime = clampedTime
        needsDisplay = true
        onSeekRequested?(clampedTime)
    }

    private func xPosition(for time: TimeInterval) -> CGFloat {
        guard state.sourceDuration > 0 else {
            return stripRect.minX
        }

        let fraction = min(max(time / state.sourceDuration, 0), 1)
        return stripRect.minX + stripRect.width * CGFloat(fraction)
    }

    private func time(for x: CGFloat) -> TimeInterval {
        guard stripRect.width > 0 else {
            return state.startTime
        }

        let fraction = min(max((x - stripRect.minX) / stripRect.width, 0), 1)
        return TimeInterval(fraction) * state.sourceDuration
    }

    private func drawHandle(centerX: CGFloat, strip: CGRect) {
        let handleRect = CGRect(x: centerX - 2.5, y: strip.midY - 15, width: 5, height: 30)
        let handlePath = NSBezierPath(roundedRect: handleRect, xRadius: 2.5, yRadius: 2.5)
        NSColor.labelColor.withAlphaComponent(0.52).setFill()
        handlePath.fill()
        NSColor.windowBackgroundColor.withAlphaComponent(0.72).setStroke()
        handlePath.lineWidth = 0.6
        handlePath.stroke()
    }

    private func setupTimeFields() {
        for field in [startField, endField] {
            field.isEditable = false
            field.isSelectable = false
            field.isBordered = false
            field.backgroundColor = .clear
            field.focusRingType = .none
            field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
            field.textColor = .secondaryLabelColor
            field.alignment = .center
            field.target = nil
            field.action = nil
            field.translatesAutoresizingMaskIntoConstraints = true
            addSubview(field)
        }
    }

    private func refreshTimeFields() {
        startField.stringValue = VideoEditorBarView.formatTime(state.startTime)
        endField.stringValue = VideoEditorBarView.formatTime(state.endTime)
    }

    private func layoutTimeFields() {
        let placement = timeLabelPlacement()
        let labelSize = VideoTrimTimelineMetrics.labelSize
        let y = stripRect.midY - labelSize.height / 2

        switch placement {
        case .insideSelection:
            startField.isHidden = false
            endField.isHidden = false
            startField.frame = CGRect(
                x: selectedRect.minX + VideoTrimTimelineMetrics.innerLabelInset,
                y: y,
                width: labelSize.width,
                height: labelSize.height
            )
            endField.frame = CGRect(
                x: selectedRect.maxX - labelSize.width - VideoTrimTimelineMetrics.innerLabelInset,
                y: y,
                width: labelSize.width,
                height: labelSize.height
            )
        case .outsideSelection:
            startField.isHidden = false
            endField.isHidden = false
            startField.frame = CGRect(
                x: selectedRect.minX - VideoTrimTimelineMetrics.outerLabelGap - labelSize.width,
                y: y,
                width: labelSize.width,
                height: labelSize.height
            )
            endField.frame = CGRect(
                x: selectedRect.maxX + VideoTrimTimelineMetrics.outerLabelGap,
                y: y,
                width: labelSize.width,
                height: labelSize.height
            )
        case .edgeClamped:
            startField.isHidden = false
            endField.isHidden = false
            let startX = max(
                stripRect.minX + VideoTrimTimelineMetrics.edgeLabelInset,
                min(selectedRect.minX + VideoTrimTimelineMetrics.innerLabelInset, stripRect.maxX - labelSize.width * 2 - 16)
            )
            let endX = min(
                stripRect.maxX - VideoTrimTimelineMetrics.edgeLabelInset - labelSize.width,
                max(selectedRect.maxX - labelSize.width - VideoTrimTimelineMetrics.innerLabelInset, startX + labelSize.width + 16)
            )
            startField.frame = CGRect(x: startX, y: y, width: labelSize.width, height: labelSize.height)
            endField.frame = CGRect(x: endX, y: y, width: labelSize.width, height: labelSize.height)
        }
    }

    private func timeLabelPlacement() -> VideoTrimTimeLabelPlacement {
        let labelWidth = VideoTrimTimelineMetrics.labelSize.width
        let selectedWidth = selectedRect.width
        if selectedWidth >= labelWidth * 2 + VideoTrimTimelineMetrics.minimumLabelSeparation {
            return .insideSelection
        }

        let leftOutsideX = selectedRect.minX - VideoTrimTimelineMetrics.outerLabelGap - labelWidth
        let rightOutsideMaxX = selectedRect.maxX + VideoTrimTimelineMetrics.outerLabelGap + labelWidth
        if leftOutsideX >= stripRect.minX, rightOutsideMaxX <= stripRect.maxX {
            return .outsideSelection
        }

        return .edgeClamped
    }

    private enum DragTarget {
        case start
        case end
        case playhead
    }
}

enum VideoTrimTimeLabelPlacement: Equatable {
    case insideSelection
    case outsideSelection
    case edgeClamped
}

private enum VideoTrimTimelineMetrics {
    static let trackInset = VideoEditorBarMetrics.timelineTrackInset
    static let labelSize = CGSize(width: 64, height: 18)
    static let innerLabelInset: CGFloat = 10
    static let outerLabelGap: CGFloat = 12
    static let edgeLabelInset: CGFloat = 8
    static let minimumLabelSeparation: CGFloat = 24
}

private final class VideoTrimTimeLabelField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class VideoEditorTransportButton: NSButton {
    private let iconView = NSImageView()
    private var trackingArea: NSTrackingArea?

    var symbolName = "play.fill" {
        didSet {
            updateIcon()
        }
    }

    override var isHighlighted: Bool {
        didSet {
            updateAppearance()
        }
    }

    override var isEnabled: Bool {
        didSet {
            updateAppearance()
            window?.invalidateCursorRects(for: self)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2

        let iconSize = CGSize(width: 14, height: 14)
        let opticalXOffset: CGFloat = symbolName == "play.fill" ? 0.8 : 0
        iconView.frame = CGRect(
            x: bounds.midX - iconSize.width / 2 + opticalXOffset,
            y: bounds.midY - iconSize.height / 2,
            width: iconSize.width,
            height: iconSize.height
        )
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if isEnabled {
            addCursorRect(bounds, cursor: .pointingHand)
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if isEnabled {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if isEnabled {
            NSCursor.pointingHand.set()
        }
        super.mouseEntered(with: event)
    }

    private func configure() {
        title = ""
        image = nil
        imagePosition = .noImage
        isBordered = false
        bezelStyle = .regularSquare
        focusRingType = .none
        setButtonType(.momentaryChange)
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 0

        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        iconView.contentTintColor = .labelColor
        iconView.translatesAutoresizingMaskIntoConstraints = true
        addSubview(iconView)

        updateIcon()
        updateAppearance()
    }

    private func updateIcon() {
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel())
        needsLayout = true
    }

    private func updateAppearance() {
        let alpha: CGFloat
        if !isEnabled {
            alpha = 0.06
        } else if isHighlighted {
            alpha = 0.16
        } else {
            alpha = 0.10
        }

        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
        iconView.contentTintColor = isEnabled ? .labelColor : .disabledControlTextColor
    }
}
