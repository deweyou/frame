import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoEditorBarViewTests: XCTestCase {
    func testEditorBarGroupsPlaybackTrimAndSpeedControls() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state, strings: AppStrings(language: .en))

        XCTAssertTrue(editorBar.hasTransportSummaryForTesting)
        XCTAssertEqual(editorBar.playbackSummaryTextForTesting, "00:00.00 / 00:24.00")
        XCTAssertTrue(editorBar.hasTrimRangeLabelsForTesting)
        XCTAssertFalse(editorBar.hasEditableTrimTimeLabelsForTesting)
        XCTAssertTrue(editorBar.trimTimeLabelsPassThroughHitTestingForTesting)
        XCTAssertTrue(editorBar.timelineUsesPointingCursorForTesting)
        XCTAssertFalse(editorBar.hasInlineTrimTokenForTesting)
        XCTAssertEqual(editorBar.startFieldAccessibilityLabelForTesting, "Start time")
        XCTAssertEqual(editorBar.endFieldAccessibilityLabelForTesting, "End time")
        XCTAssertEqual(editorBar.speedDropdownAccessibilityLabelForTesting, "Playback speed")
    }

    func testEditorBarUsesCompactMediaControlDensity() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state, strings: AppStrings(language: .en))

        let minimumHeight = try XCTUnwrap(editorBar.constraints.first {
            $0.firstAttribute == .height && $0.relation == .greaterThanOrEqual
        }?.constant)
        XCTAssertLessThanOrEqual(minimumHeight, 92)

        let timelineView = try XCTUnwrap(findSubview(of: VideoTrimTimelineView.self, in: editorBar))
        let timelineHeight = try XCTUnwrap(heightConstraintConstant(for: timelineView, in: editorBar))
        XCTAssertGreaterThanOrEqual(timelineHeight, 38)
        XCTAssertLessThanOrEqual(timelineHeight, 44)
    }

    func testEditorBarAlignsTransportControlsToTimelineTrackEdges() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state, strings: AppStrings(language: .en))

        let timelineView = try XCTUnwrap(findSubview(of: VideoTrimTimelineView.self, in: editorBar))
        let playButton = try XCTUnwrap(findButton(accessibilityLabel: "Play/Pause", in: editorBar))
        let bottomRow = try XCTUnwrap(playButton.superview)

        let timelineInset = try XCTUnwrap(leadingConstraintConstant(for: timelineView, in: editorBar))
        let bottomInset = try XCTUnwrap(leadingConstraintConstant(for: bottomRow, in: editorBar))
        let bottomTrailingInset = try XCTUnwrap(trailingConstraintConstant(for: bottomRow, in: editorBar))
        let timelineTrackInset: CGFloat = 7

        XCTAssertEqual(bottomInset, timelineInset + timelineTrackInset)
        XCTAssertEqual(bottomTrailingInset, -(timelineInset + timelineTrackInset))
    }

    func testSpeedControlFitsChineseLabelAndLongestPreset() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state, strings: AppStrings(language: .zhHans))

        let popup = try XCTUnwrap(findPopUpButton(accessibilityLabel: "播放速度", in: editorBar))
        let speedToken = try XCTUnwrap(popup.superview)
        let tokenWidth = try XCTUnwrap(widthConstraintConstant(for: speedToken, in: editorBar))
        let popupWidth = try XCTUnwrap(widthConstraintConstant(for: popup, in: editorBar))

        XCTAssertGreaterThanOrEqual(tokenWidth, 124)
        XCTAssertGreaterThanOrEqual(popupWidth, 68)
    }

    func testPlayPauseControlIsCircularAndBorderless() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state, strings: AppStrings(language: .en))

        let playButton = try XCTUnwrap(findButton(accessibilityLabel: "Play/Pause", in: editorBar))
        let width = try XCTUnwrap(widthConstraintConstant(for: playButton, in: editorBar))
        let height = try XCTUnwrap(heightConstraintConstant(for: playButton, in: editorBar))

        XCTAssertEqual(width, height)
        XCTAssertEqual(width, 28)
        XCTAssertEqual(playButton.layer?.cornerRadius, width / 2)
        XCTAssertEqual(playButton.layer?.borderWidth ?? 0, 0)
        XCTAssertEqual(playButton.focusRingType, .none)
        XCTAssertNil(playButton.image)

        editorBar.updatePlayback(time: 1, isPlaying: true)

        XCTAssertNil(playButton.image)
    }

    func testEditorBarEmitsSpeedSelection() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state)
        var emittedState: VideoEditingState?
        editorBar.onStateChanged = { emittedState = $0 }

        editorBar.selectSpeedForTesting(.quadruple)

        XCTAssertEqual(try XCTUnwrap(emittedState).speed, .quadruple)
        XCTAssertTrue(editorBar.hasSpeedDropdownForTesting)
    }

    func testEditorBarShowsOutputDurationWhenSpeedChanges() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state, strings: AppStrings(language: .en))

        editorBar.selectSpeedForTesting(.double)

        XCTAssertEqual(editorBar.playbackSummaryTextForTesting, "00:00.00 / 00:24.00 · Output 00:12.00")
    }

    func testEditorBarTimelineEmitsTrimAndSeekChanges() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state)
        var emittedState: VideoEditingState?
        var requestedSeek: TimeInterval?
        editorBar.onStateChanged = { emittedState = $0 }
        editorBar.onSeekRequested = { requestedSeek = $0 }

        editorBar.moveStartHandleForTesting(to: 4)
        editorBar.seekTimelineForTesting(to: 9)

        XCTAssertEqual(try XCTUnwrap(emittedState).startTime, 4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(requestedSeek), 9, accuracy: 0.0001)
        XCTAssertTrue(editorBar.hasTimelineForTesting)
    }

    func testMiniTimelinePlacesTrimTimesInsideWhenSelectedRangeIsWide() throws {
        let state = try VideoEditingState(sourceDuration: 100)
        let timeline = VideoTrimTimelineView(state: state)
        timeline.frame = CGRect(x: 0, y: 0, width: 420, height: 40)

        XCTAssertEqual(timeline.timeLabelPlacementForTesting, .insideSelection)
    }

    func testMiniTimelinePlacesTrimTimesOutsideWhenSelectedRangeIsTiny() throws {
        var state = try VideoEditingState(sourceDuration: 100)
        try state.setTrimRange(start: 51, end: 56)
        let timeline = VideoTrimTimelineView(state: state)
        timeline.frame = CGRect(x: 0, y: 0, width: 420, height: 40)

        XCTAssertEqual(timeline.timeLabelPlacementForTesting, .outsideSelection)
    }

    func testMiniTimelineClampsTrimTimesAtCrowdedEdges() throws {
        var state = try VideoEditingState(sourceDuration: 100)
        try state.setTrimRange(start: 1, end: 6)
        let timeline = VideoTrimTimelineView(state: state)
        timeline.frame = CGRect(x: 0, y: 0, width: 220, height: 40)

        XCTAssertEqual(timeline.timeLabelPlacementForTesting, .edgeClamped)
    }

    func testEditorBarPlayPauseButtonEmitsAction() throws {
        let state = try VideoEditingState(sourceDuration: 24)
        let editorBar = VideoEditorBarView(state: state)
        var callCount = 0
        editorBar.onPlayPauseRequested = { callCount += 1 }

        editorBar.performPlayPauseForTesting()

        XCTAssertEqual(callCount, 1)
    }

    private func findSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let view = view as? T {
            return view
        }

        for subview in view.subviews {
            if let matchingView = findSubview(of: type, in: subview) {
                return matchingView
            }
        }

        return nil
    }

    private func findButton(accessibilityLabel: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton,
           button.accessibilityLabel() == accessibilityLabel {
            return button
        }

        for subview in view.subviews {
            if let matchingButton = findButton(accessibilityLabel: accessibilityLabel, in: subview) {
                return matchingButton
            }
        }

        return nil
    }

    private func findPopUpButton(accessibilityLabel: String, in view: NSView) -> NSPopUpButton? {
        if let popup = view as? NSPopUpButton,
           popup.accessibilityLabel() == accessibilityLabel {
            return popup
        }

        for subview in view.subviews {
            if let matchingPopup = findPopUpButton(accessibilityLabel: accessibilityLabel, in: subview) {
                return matchingPopup
            }
        }

        return nil
    }

    private func widthConstraintConstant(for target: NSView, in view: NSView) -> CGFloat? {
        if let constraint = view.constraints.first(where: {
            $0.firstItem === target && $0.firstAttribute == .width
        }) {
            return constraint.constant
        }

        for subview in view.subviews {
            if let constant = widthConstraintConstant(for: target, in: subview) {
                return constant
            }
        }

        return nil
    }

    private func heightConstraintConstant(for target: NSView, in view: NSView) -> CGFloat? {
        if let constraint = view.constraints.first(where: {
            $0.firstItem === target && $0.firstAttribute == .height
        }) {
            return constraint.constant
        }

        for subview in view.subviews {
            if let constant = heightConstraintConstant(for: target, in: subview) {
                return constant
            }
        }

        return nil
    }

    private func leadingConstraintConstant(for target: NSView, in view: NSView) -> CGFloat? {
        if let constraint = view.constraints.first(where: {
            $0.firstItem === target && $0.firstAttribute == .leading
        }) {
            return constraint.constant
        }

        for subview in view.subviews {
            if let constant = leadingConstraintConstant(for: target, in: subview) {
                return constant
            }
        }

        return nil
    }

    private func trailingConstraintConstant(for target: NSView, in view: NSView) -> CGFloat? {
        if let constraint = view.constraints.first(where: {
            $0.firstItem === target && $0.firstAttribute == .trailing
        }) {
            return constraint.constant
        }

        for subview in view.subviews {
            if let constant = trailingConstraintConstant(for: target, in: subview) {
                return constant
            }
        }

        return nil
    }
}
