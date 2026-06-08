import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class AppDelegateRecordingTests: XCTestCase {
    func testRecordingStartDoesNotShowStaticKeyboardHintOverlay() async throws {
        _ = NSApplication.shared
        let recordingService = SpyRecordingService()
        let keyboardHints = SpyKeyboardHintOverlayController()
        let delegate = AppDelegate(
            recordingService: recordingService,
            keyboardHintOverlayController: keyboardHints
        )
        defer {
            delegate.finishActiveRecordingForTesting()
        }

        delegate.startRecordingForTesting(
            selection: SelectionCapture(
                rect: CGRect(x: 40, y: 60, width: 320, height: 180),
                kind: .region
            ),
            options: RecordingOptions(
                format: .mp4,
                showsCursor: true,
                showsKeyboardHints: true,
                audioSource: .none
            )
        )

        try await waitUntil {
            recordingService.recordedRequests.count == 1
        }

        XCTAssertEqual(recordingService.recordedRequests.count, 1)
        XCTAssertTrue(keyboardHints.showCalls.isEmpty)
    }

    func testRestartRecordingCancelsCurrentSessionAndStartsSameSelectionAgain() async throws {
        _ = NSApplication.shared
        let recordingService = SpyRecordingService()
        let delegate = AppDelegate(recordingService: recordingService)
        let selection = SelectionCapture(
            rect: CGRect(x: 40, y: 60, width: 320, height: 180),
            kind: .region
        )
        let options = RecordingOptions(
            format: .gif,
            showsCursor: false,
            showsKeyboardHints: false,
            audioSource: .none
        )
        defer {
            delegate.finishActiveRecordingForTesting()
        }

        delegate.startRecordingForTesting(selection: selection, options: options)
        try await waitUntil {
            recordingService.sessions.count == 1
        }
        let firstSession = try XCTUnwrap(recordingService.sessions.first)

        delegate.restartActiveRecordingForTesting()
        try await waitUntil {
            recordingService.recordedRequests.count == 2
        }

        XCTAssertEqual(firstSession.cancelCallCount, 1)
        XCTAssertEqual(recordingService.recordedRequests.count, 2)
        XCTAssertEqual(recordingService.recordedRequests[1].selection, selection)
        XCTAssertEqual(recordingService.recordedRequests[1].options, options)
    }

    func testDeleteRecordingCancelsCurrentSessionWithoutRestarting() async throws {
        _ = NSApplication.shared
        let recordingService = SpyRecordingService()
        let delegate = AppDelegate(recordingService: recordingService)
        defer {
            delegate.finishActiveRecordingForTesting()
        }

        delegate.startRecordingForTesting(
            selection: SelectionCapture(
                rect: CGRect(x: 40, y: 60, width: 320, height: 180),
                kind: .region
            ),
            options: .defaults
        )
        try await waitUntil {
            recordingService.sessions.count == 1
        }
        let session = try XCTUnwrap(recordingService.sessions.first)

        delegate.deleteActiveRecordingForTesting()
        try await waitUntil {
            session.cancelCallCount == 1
        }

        XCTAssertEqual(session.cancelCallCount, 1)
        XCTAssertEqual(recordingService.recordedRequests.count, 1)
    }

    func testStoppingRecordingFreezesElapsedHUDWhileSaving() async throws {
        _ = NSApplication.shared
        let recordingService = SpyRecordingService()
        let delegate = AppDelegate(recordingService: recordingService)
        defer {
            delegate.finishActiveRecordingForTesting()
        }

        delegate.startRecordingForTesting(
            selection: SelectionCapture(
                rect: CGRect(x: 40, y: 60, width: 320, height: 180),
                kind: .region
            ),
            options: .defaults
        )
        try await waitUntil {
            recordingService.sessions.count == 1
        }
        XCTAssertTrue(delegate.activeRecordingElapsedTimerIsValidForTesting())

        delegate.stopActiveRecordingForTesting()

        XCTAssertFalse(delegate.activeRecordingElapsedTimerIsValidForTesting())
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        XCTFail("Timed out waiting for recording test condition")
    }
}

private final class SpyKeyboardHintOverlayController: KeyboardHintOverlayControlling {
    private(set) var showCalls: [(text: String, rect: CGRect)] = []
    private(set) var hideCallCount = 0

    func show(text: String, near rect: CGRect) {
        showCalls.append((text, rect))
    }

    func hide() {
        hideCallCount += 1
    }
}

private final class SpyRecordingService: RecordingServicing, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [RecordingRequest] = []
    private var createdSessions: [SpyRecordingSession] = []

    var recordedRequests: [RecordingRequest] {
        lock.withLock {
            requests
        }
    }

    var sessions: [SpyRecordingSession] {
        lock.withLock {
            createdSessions
        }
    }

    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling {
        let session = SpyRecordingSession()
        lock.withLock {
            requests.append(request)
            createdSessions.append(session)
        }
        return session
    }
}

private final class SpyRecordingSession: RecordingSessionControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var currentState: RecordingSessionState = .recording
    private var cancelCalls = 0

    var state: RecordingSessionState {
        lock.withLock {
            currentState
        }
    }

    var cancelCallCount: Int {
        lock.withLock {
            cancelCalls
        }
    }

    func pause() async throws {
        lock.withLock {
            currentState = .paused
        }
    }

    func resume() async throws {
        lock.withLock {
            currentState = .recording
        }
    }

    func stop() async throws -> CapturedRecording {
        lock.withLock {
            currentState = .finished
        }
        return CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/frame-test-recording.mp4"),
            format: .mp4,
            rect: .zero,
            pixelSize: .zero,
            byteSize: 0,
            duration: 0
        )
    }

    func cancel() async {
        lock.withLock {
            cancelCalls += 1
            currentState = .finished
        }
    }
}
