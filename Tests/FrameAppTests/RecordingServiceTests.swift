import XCTest
@testable import FrameApp
@testable import FrameCore

final class RecordingServiceTests: XCTestCase {
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
}

private final class FakeRecordingService: RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling {
        FakeRecordingSession(request: request)
    }
}

private final class FakeRecordingSession: RecordingSessionControlling {
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
