import AVFoundation
import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class AppDelegateRecordingTests: XCTestCase {
    func testRestoringHistoryRecordingShowsQuickAccessPreview() async throws {
        let store = CaptureHistoryStore(rootDirectory: makeTemporaryDirectory())
        let delegate = AppDelegate(captureHistoryStore: store)
        let sourceURL = try makeTemporaryTestMP4File(duration: 1.2)
        let recordingData = try Data(contentsOf: sourceURL)
        let record = try XCTUnwrap(try store.addRecording(
            data: recordingData,
            filenameExtension: RecordingFormat.mp4.fileExtension,
            pixelSize: CGSize(width: 320, height: 240),
            rect: CGRect(x: 10, y: 20, width: 320, height: 240),
            configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
        ))

        await delegate.restoreHistoryRecordForTesting(record)

        XCTAssertEqual(delegate.quickAccessRecordingCountForTesting(), 1)
        let restoredRecording = try XCTUnwrap(delegate.quickAccessRecordingForTesting(id: record.id))
        XCTAssertEqual(restoredRecording.fileURL, store.fileURL(for: record))
        XCTAssertEqual(restoredRecording.format, .mp4)
        XCTAssertEqual(restoredRecording.rect, record.rect)
        XCTAssertEqual(restoredRecording.pixelSize, CGSize(width: 320, height: 240))
        XCTAssertEqual(restoredRecording.byteSize, recordingData.count)
        XCTAssertEqual(restoredRecording.duration, 1.2, accuracy: 0.25)
    }

    func testSavingEditedRecordingAsNewShowsNewQuickAccessRecording() async throws {
        let exporter = FakeVideoEditingExporter(resultURL: try makeTemporaryMP4File())
        let delegate = AppDelegate(
            captureHistoryStore: CaptureHistoryStore(rootDirectory: makeTemporaryDirectory()),
            videoEditingExporter: exporter
        )
        let recording = makeRecording(id: UUID(), fileURL: try makeTemporaryMP4File())
        delegate.showVideoQuickAccessForTesting(recording)
        var state = try VideoEditingState(sourceDuration: 10)
        try state.setTrimRange(start: 1, end: 5)

        let didSave = await delegate.saveEditedRecordingForTesting(recording, editingState: state, choice: .saveAsNew)
        XCTAssertTrue(didSave)

        XCTAssertEqual(exporter.requests.count, 1)
        XCTAssertEqual(delegate.quickAccessRecordingCountForTesting(), 2)
    }

    func testReplacingEditedRecordingUpdatesQuickAccessPreview() async throws {
        let exporter = FakeVideoEditingExporter(resultURL: try makeTemporaryMP4File())
        let delegate = AppDelegate(
            captureHistoryStore: CaptureHistoryStore(rootDirectory: makeTemporaryDirectory()),
            videoEditingExporter: exporter
        )
        let recordingID = UUID()
        let recording = makeRecording(id: recordingID, fileURL: try makeTemporaryMP4File())
        delegate.showVideoQuickAccessForTesting(recording)
        var state = try VideoEditingState(sourceDuration: 10)
        try state.setTrimRange(start: 1, end: 5)

        let didReplace = await delegate.saveEditedRecordingForTesting(recording, editingState: state, choice: .replaceCurrent)
        XCTAssertTrue(didReplace)

        XCTAssertEqual(exporter.requests.count, 1)
        XCTAssertEqual(delegate.quickAccessRecordingCountForTesting(), 1)
        XCTAssertEqual(delegate.quickAccessRecordingForTesting(id: recordingID)?.duration, 4)
    }

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
            recordingService.sessions.count == 1 && delegate.hasActiveRecordingForTesting()
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
            recordingService.sessions.count == 1 && delegate.hasActiveRecordingForTesting()
        }
        let session = try XCTUnwrap(recordingService.sessions.first)

        XCTAssertFalse(delegate.startCaptureFlowForTesting())

        XCTAssertEqual(session.recordedKeyboardHints, ["⌘⇧A"])
    }

    func testRecordingShortcutStartsSelectionInRecordingSetupMode() {
        _ = NSApplication.shared
        let selectionOverlay = SpySelectionOverlayController()
        let delegate = AppDelegate(
            selectionOverlayController: selectionOverlay,
            hasScreenRecordingAccess: { true },
            showMissingScreenRecordingPermission: {},
            playInvalidActionFeedback: {}
        )

        XCTAssertTrue(delegate.startRecordingCaptureFlowForTesting())

        XCTAssertEqual(selectionOverlay.startSelectionCallCount, 1)
        XCTAssertEqual(selectionOverlay.lastInitialMode, .recordingSetup)
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
            recordingService.recordedRequests.count == 1 && delegate.hasActiveRecordingForTesting()
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
            recordingService.sessions.count == 1 && delegate.hasActiveRecordingForTesting()
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
            recordingService.sessions.count == 1 && delegate.hasActiveRecordingForTesting()
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

private final class FakeVideoEditingExporter: VideoEditingExporting, @unchecked Sendable {
    struct Request: Equatable {
        let sourceURL: URL
        let format: RecordingFormat
        let editingState: VideoEditingState
    }

    private let lock = NSLock()
    let resultURL: URL
    private var recordedRequests: [Request] = []

    var requests: [Request] {
        lock.withLock {
            recordedRequests
        }
    }

    init(resultURL: URL) {
        self.resultURL = resultURL
    }

    func export(sourceURL: URL, format: RecordingFormat, editingState: VideoEditingState) async throws -> URL {
        lock.withLock {
            recordedRequests.append(Request(sourceURL: sourceURL, format: format, editingState: editingState))
        }
        return resultURL
    }
}

private func makeRecording(id: UUID, fileURL: URL, duration: TimeInterval = 10) -> CapturedRecording {
    CapturedRecording(
        id: id,
        fileURL: fileURL,
        format: .mp4,
        rect: CGRect(x: 0, y: 0, width: 320, height: 240),
        pixelSize: CGSize(width: 320, height: 240),
        byteSize: 3,
        duration: duration
    )
}

private func makeTemporaryTestMP4File(duration: TimeInterval) throws -> URL {
    let directory = makeTemporaryDirectory()
    let url = directory.appendingPathComponent("recording-\(UUID().uuidString).mp4")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let size = CGSize(width: 16, height: 16)
    let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ]
    )
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ]
    )
    writer.add(input)

    guard writer.startWriting() else {
        throw NSError(domain: "AppDelegateRecordingTests", code: 1)
    }
    writer.startSession(atSourceTime: .zero)

    for frameIndex in 0..<Int(duration * 10) {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard let buffer else {
            throw NSError(domain: "AppDelegateRecordingTests", code: 2)
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            memset(baseAddress, Int32(frameIndex % 255), CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        while !input.isReadyForMoreMediaData {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        guard adaptor.append(
            buffer,
            withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 10)
        ) else {
            throw NSError(domain: "AppDelegateRecordingTests", code: 3)
        }
    }

    input.markAsFinished()
    let expectation = XCTestExpectation(description: "finish writing test MP4")
    writer.finishWriting {
        expectation.fulfill()
    }
    XCTWaiter().wait(for: [expectation], timeout: 5)
    guard writer.status == .completed else {
        throw writer.error ?? NSError(domain: "AppDelegateRecordingTests", code: 4)
    }

    return url
}

private func makeTemporaryMP4File() throws -> URL {
    let directory = makeTemporaryDirectory()
    let url = directory.appendingPathComponent("recording-\(UUID().uuidString).mp4")
    try Data([1, 2, 3]).write(to: url)
    return url
}

private func makeTemporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FrameAppDelegateRecordingTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private final class SpySelectionOverlayController: SelectionOverlayControlling {
    private(set) var startSelectionCallCount = 0
    private(set) var lastInitialMode: SelectionOverlayInitialMode?
    private var activeCompletion: ((SelectionOverlayCompletion?) -> Void)?

    var isSelecting: Bool {
        activeCompletion != nil
    }

    func startSelection(
        strings: AppStrings,
        initialMode: SelectionOverlayInitialMode,
        onStartRecording: @escaping (SelectionOverlayWindow, SelectionCapture, RecordingOptions) -> Void,
        completion: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        startSelectionCallCount += 1
        lastInitialMode = initialMode
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
