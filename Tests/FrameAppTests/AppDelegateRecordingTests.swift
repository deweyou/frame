import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class AppDelegateRecordingTests: XCTestCase {
    func testCaptureFlowIgnoresRepeatedShortcutWhileSelectionIsActive() {
        _ = NSApplication.shared
        let selectionOverlay = SpySelectionOverlayController()
        var beepCount = 0
        let delegate = AppDelegate(
            selectionOverlayController: selectionOverlay,
            hasScreenRecordingAccess: { true },
            showMissingScreenRecordingPermission: {},
            playInvalidActionFeedback: { beepCount += 1 }
        )

        XCTAssertTrue(delegate.startCaptureFlowForTesting())
        XCTAssertEqual(selectionOverlay.startSelectionCallCount, 1)

        XCTAssertFalse(delegate.startCaptureFlowForTesting())

        XCTAssertEqual(selectionOverlay.startSelectionCallCount, 1)
        XCTAssertEqual(beepCount, 1)
    }

    func testCaptureFlowIgnoresShortcutWhileRecordingIsActive() async throws {
        _ = NSApplication.shared
        let recordingService = SpyRecordingService()
        let selectionOverlay = SpySelectionOverlayController()
        var beepCount = 0
        let delegate = AppDelegate(
            selectionOverlayController: selectionOverlay,
            recordingService: recordingService,
            hasScreenRecordingAccess: { true },
            showMissingScreenRecordingPermission: {},
            playInvalidActionFeedback: { beepCount += 1 }
        )
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

        XCTAssertFalse(delegate.startCaptureFlowForTesting())

        XCTAssertEqual(selectionOverlay.startSelectionCallCount, 0)
        XCTAssertEqual(beepCount, 1)
    }

    func testCaptureFlowRecordsShortcutHintWhileRecordingIsActive() async throws {
        _ = NSApplication.shared
        let recordingService = SpyRecordingService()
        let delegate = AppDelegate(
            recordingService: recordingService,
            hasScreenRecordingAccess: { true },
            showMissingScreenRecordingPermission: {},
            playInvalidActionFeedback: {}
        )
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

        XCTAssertFalse(delegate.startCaptureFlowForTesting())

        XCTAssertEqual(session.recordedKeyboardHints, ["⌘⇧A"])
    }

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
            recordingService.sessions.count == 1 && delegate.hasActiveRecordingForTesting()
        }
        let firstSession = try XCTUnwrap(recordingService.sessions.first)

        delegate.restartActiveRecordingForTesting()
        try await waitUntil {
            recordingService.recordedRequests.count == 2
        }

        XCTAssertEqual(firstSession.cancelCallCount, 1)
        XCTAssertEqual(recordingService.recordedRequests.count, 2)
        let restartedRequest = try XCTUnwrap(recordingService.recordedRequests.dropFirst().first)
        XCTAssertEqual(restartedRequest.selection, selection)
        XCTAssertEqual(restartedRequest.options, options)
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

@MainActor
private final class SpySelectionOverlayController: SelectionOverlayControlling {
    private(set) var startSelectionCallCount = 0
    private var activeCompletion: ((SelectionOverlayCompletion?) -> Void)?

    var isSelecting: Bool {
        activeCompletion != nil
    }

    func startSelection(
        strings: AppStrings,
        onStartRecording: @escaping (SelectionOverlayWindow, SelectionCapture, RecordingOptions) -> Void,
        completion: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        startSelectionCallCount += 1
        activeCompletion = completion
    }

    func dismissSelectionForRecording() {
        activeCompletion = nil
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
    private var keyboardHints: [String] = []

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

    var recordedKeyboardHints: [String] {
        lock.withLock {
            keyboardHints
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

    func recordKeyboardHint(_ label: String) {
        lock.withLock {
            keyboardHints.append(label)
        }
    }
}
