import XCTest
import AVKit
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoPreviewWindowControllerTests: XCTestCase {
    func testMP4PreviewWindowShowsEditorBarByDefault() throws {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: .zero,
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoPreviewWindowController()

        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )

        XCTAssertTrue(controller.isEditingEnabledForTesting(recordingID: recording.id))
        XCTAssertEqual(controller.editingStateForTesting(recordingID: recording.id)?.endTime, 24)
        let window = try XCTUnwrap(controller.windowForTesting(recordingID: recording.id))
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertNotNil(findSubview(of: VideoEditorBarView.self, in: contentView))
    }

    func testGIFPreviewWindowDoesNotShowEditorBar() throws {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.gif"),
            format: .gif,
            rect: .zero,
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoPreviewWindowController()

        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )

        XCTAssertFalse(controller.isEditingEnabledForTesting(recordingID: recording.id))
        let window = try XCTUnwrap(controller.windowForTesting(recordingID: recording.id))
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertNil(findSubview(of: VideoEditorBarView.self, in: contentView))
    }

    func testGIFPreviewUsesAnimatedImageViewInsteadOfVideoPlayer() throws {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.gif"),
            format: .gif,
            rect: .zero,
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoPreviewWindowController()

        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )

        let window = try XCTUnwrap(controller.windowForTesting(recordingID: recording.id))
        let contentView = try XCTUnwrap(window.contentView)
        XCTAssertNil(findSubview(of: AVPlayerView.self, in: contentView))
        let imageView = try XCTUnwrap(findSubview(of: NSImageView.self, in: contentView))
        XCTAssertTrue(imageView.animates)
    }

    func testUpdatingMP4TrimStateMarksWindowDirty() throws {
        let recording = makeMP4Recording(duration: 24)
        let controller = VideoPreviewWindowController()
        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )

        try controller.setTrimRangeForTesting(recordingID: recording.id, start: 3.274, end: 18.636)

        let state = try XCTUnwrap(controller.editingStateForTesting(recordingID: recording.id))
        XCTAssertEqual(state.startTime, 3.27, accuracy: 0.0001)
        XCTAssertEqual(state.endTime, 18.64, accuracy: 0.0001)
        XCTAssertTrue(controller.hasUnsavedEditsForTesting(recordingID: recording.id))
    }

    func testPlaybackRangeUsesTrimStartAndEnd() throws {
        let recording = makeMP4Recording(duration: 24)
        let controller = VideoPreviewWindowController()
        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )

        try controller.setTrimRangeForTesting(recordingID: recording.id, start: 3, end: 8)

        let range = try XCTUnwrap(controller.playbackRangeForTesting(recordingID: recording.id))
        XCTAssertEqual(range.start.seconds, 3, accuracy: 0.001)
        XCTAssertEqual(range.end.seconds, 8, accuracy: 0.001)
    }

    func testUpdatingMP4SpeedStateMarksWindowDirty() throws {
        let recording = makeMP4Recording(duration: 24)
        let controller = VideoPreviewWindowController()
        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )

        try controller.setSpeedForTesting(recordingID: recording.id, speed: .octuple)

        let state = try XCTUnwrap(controller.editingStateForTesting(recordingID: recording.id))
        XCTAssertEqual(state.speed, .octuple)
        XCTAssertEqual(state.outputDuration, 3, accuracy: 0.0001)
        XCTAssertTrue(controller.hasUnsavedEditsForTesting(recordingID: recording.id))
    }

    func testSaveCurrentMenuRoutesReplaceAndSaveAsNew() throws {
        let recording = makeMP4Recording(duration: 24)
        let controller = VideoPreviewWindowController()
        var calls: [(CapturedRecording, VideoEditingState, VideoPreviewSaveChoice)] = []
        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: {
                calls.append(($0, $1, $2))
                return true
            }
        )
        try controller.setTrimRangeForTesting(recordingID: recording.id, start: 1, end: 2)

        XCTAssertTrue(controller.performSaveCurrentForTesting(recordingID: recording.id, choice: .replaceCurrent))
        XCTAssertTrue(controller.performSaveCurrentForTesting(recordingID: recording.id, choice: .saveAsNew))
        XCTAssertEqual(calls.map(\.2), [.replaceCurrent, .saveAsNew])
    }

    func testClosingDirtyMP4CanCancel() throws {
        let recording = makeMP4Recording(duration: 24)
        let controller = VideoPreviewWindowController(closeChoiceProvider: { _, _, _ in .cancel })
        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, _ in true }
        )
        try controller.setTrimRangeForTesting(recordingID: recording.id, start: 1, end: 2)

        XCTAssertFalse(controller.windowShouldCloseForTesting(recordingID: recording.id))
    }

    func testClosingDirtyMP4RoutesReplaceChoice() throws {
        let recording = makeMP4Recording(duration: 24)
        let controller = VideoPreviewWindowController(closeChoiceProvider: { _, _, _ in .replaceCurrent })
        var calls: [VideoPreviewSaveChoice] = []
        controller.show(
            recording: recording,
            strings: AppStrings(language: .en),
            copy: { true },
            download: { true },
            saveCurrent: { _, _, choice in
                calls.append(choice)
                return true
            }
        )
        try controller.setTrimRangeForTesting(recordingID: recording.id, start: 1, end: 2)

        XCTAssertTrue(controller.windowShouldCloseForTesting(recordingID: recording.id))
        XCTAssertEqual(calls, [.replaceCurrent])
    }

    private func findSubview<T: NSView>(of type: T.Type, in view: NSView) -> T? {
        if let matchingView = view as? T {
            return matchingView
        }

        for subview in view.subviews {
            if let matchingView = findSubview(of: type, in: subview) {
                return matchingView
            }
        }

        return nil
    }

    private func makeMP4Recording(duration: TimeInterval = 24) -> CapturedRecording {
        CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: .zero,
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: duration
        )
    }
}
