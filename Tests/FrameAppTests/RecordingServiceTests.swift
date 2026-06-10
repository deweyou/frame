import XCTest
@testable import FrameApp
@testable import FrameCore

final class RecordingServiceTests: XCTestCase {
    @MainActor
    func testDisplayResolverRejectsSelectionThatIntersectsMultipleDisplays() {
        let first = CGRect(x: 0, y: 0, width: 100, height: 100)
        let second = CGRect(x: 100, y: 0, width: 100, height: 100)
        let selection = CGRect(x: 90, y: 10, width: 20, height: 20)

        XCTAssertThrowsError(try RecordingDisplayResolver.resolve(selection: selection, screenFrames: [first, second]))
    }

    @MainActor
    func testDisplayResolverAcceptsSelectionInsideOneDisplay() throws {
        let screen = CGRect(x: 0, y: 0, width: 200, height: 100)
        let selection = CGRect(x: 20, y: 10, width: 80, height: 50)

        let resolved = try RecordingDisplayResolver.resolve(selection: selection, screenFrames: [screen])

        XCTAssertEqual(resolved.screenFrame, screen)
        XCTAssertEqual(resolved.selectionRect, selection)
    }

    func testSessionStateTransitionsFromRecordingToPausedToRecordingToFinished() async throws {
        let service = FakeRecordingService()
        let request = RecordingRequest(
            selection: SelectionCapture(
                rect: CGRect(x: 0, y: 0, width: 320, height: 240),
                kind: .region
            ),
            options: .defaults
        )

        let session = try await service.startRecording(request)
        XCTAssertEqual(session.state, .recording)

        try await session.pause()
        XCTAssertEqual(session.state, .paused)

        try await session.resume()
        XCTAssertEqual(session.state, .recording)

        let recording = try await session.stop()
        XCTAssertEqual(session.state, .finished)
        XCTAssertEqual(recording.format, .mp4)
    }

    func testRecordingPixelDimensionsNormalizeOddVideoSizesToEvenValues() {
        let normalized = RecordingPixelDimensions.normalizedForVideo(
            CGSize(width: 301, height: 199)
        )

        XCTAssertEqual(normalized, CGSize(width: 300, height: 198))
    }

    func testRecordingPixelDimensionsKeepMinimumEvenVideoSize() {
        let normalized = RecordingPixelDimensions.normalizedForVideo(
            CGSize(width: 1, height: 1)
        )

        XCTAssertEqual(normalized, CGSize(width: 2, height: 2))
    }

    func testOverlayConfigurationFollowsRecordingOptions() {
        XCTAssertTrue(RecordingOverlayConfiguration(options: .defaults).recordsMouseClicks)
        XCTAssertTrue(RecordingOverlayConfiguration(options: .defaults).recordsKeyboardHints)

        let clickHighlightsWithoutCursor = RecordingOverlayConfiguration(
            options: RecordingOptions(
                format: .mp4,
                showsCursor: false,
                showsMouseClickHighlights: true,
                showsKeyboardHints: false,
                audioSource: .none
            )
        )
        XCTAssertTrue(clickHighlightsWithoutCursor.isEnabled)
        XCTAssertTrue(clickHighlightsWithoutCursor.recordsMouseClicks)
        XCTAssertFalse(clickHighlightsWithoutCursor.recordsKeyboardHints)

        let disabled = RecordingOverlayConfiguration(
            options: RecordingOptions(
                format: .mp4,
                showsCursor: false,
                showsMouseClickHighlights: false,
                showsKeyboardHints: false,
                audioSource: .none
            )
        )
        XCTAssertFalse(disabled.isEnabled)
        XCTAssertFalse(disabled.recordsMouseClicks)
        XCTAssertFalse(disabled.recordsKeyboardHints)
    }

    @MainActor
    func testDisplayResolverCarriesExternalDisplayIDWhenAppKitAndCaptureFramesDiffer() throws {
        let builtInScreen = RecordingScreen(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1243)
        )
        let externalScreen = RecordingScreen(
            displayID: 3,
            frame: CGRect(x: -2055, y: 1243, width: 3008, height: 1692)
        )
        let selection = CGRect(x: -1200, y: 1800, width: 800, height: 500)

        let resolved = try RecordingDisplayResolver.resolve(
            selection: selection,
            screens: [builtInScreen, externalScreen]
        )

        XCTAssertEqual(resolved.displayID, 3)
        XCTAssertEqual(resolved.screenFrame, externalScreen.frame)
    }
}

private final class FakeRecordingService: RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling {
        FakeRecordingSession(request: request)
    }
}

private final class FakeRecordingSession: RecordingSessionControlling, @unchecked Sendable {
    private let request: RecordingRequest
    private(set) var state: RecordingSessionState = .recording

    init(request: RecordingRequest) {
        self.request = request
    }

    func pause() async throws {
        state = .paused
    }

    func resume() async throws {
        state = .recording
    }

    func cancel() async {
        state = .finished
    }

    func recordKeyboardHint(_ label: String) {}

    func stop() async throws -> CapturedRecording {
        state = .finished
        return CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/frame-test.\(request.options.format.fileExtension)"),
            format: request.options.format,
            rect: request.selection.rect,
            pixelSize: request.selection.rect.size,
            byteSize: 0,
            duration: 1
        )
    }
}
