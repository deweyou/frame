# Selection Recording Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first single-display selection recording workflow with recording HUD modes, MP4/GIF output, pause/resume, non-captured Frame overlays, video Quick Access, and playable preview.

**Architecture:** Keep deterministic recording configuration and naming in `FrameCore`, keep ScreenCaptureKit, AVFoundation, ImageIO, AppKit overlays, pasteboard, and file output in `FrameApp`, and let `AppDelegate` coordinate between the overlay, recording service, status item, history, and Quick Access. Implement the UI against protocols and value models first, then wire the real ScreenCaptureKit pipeline behind `RecordingService` so most behavior is testable without live desktop capture.

**Tech Stack:** Swift 6.1/6.2, SwiftPM, XCTest, AppKit, ScreenCaptureKit, AVFoundation, ImageIO, CoreGraphics.

---

## File Structure

- Create `Sources/FrameCore/RecordingOptions.swift`: pure recording format, audio source, cursor, keyboard hint, and elapsed-time state models.
- Create `Sources/FrameCore/RecordingNaming.swift`: deterministic `.mp4` and `.gif` filename generation aligned with screenshot naming.
- Modify `Sources/FrameApp/SettingsStore.swift`: persist recording defaults.
- Create `Sources/FrameApp/RecordingFileWriter.swift`: copy finalized recordings to the configured save directory.
- Modify `Sources/FrameApp/ClipboardWriter.swift`: write recording file URLs to pasteboard.
- Modify `Sources/FrameApp/CaptureHistoryStore.swift`: add file-backed recording records.
- Modify `Sources/FrameApp/SelectionOverlayCompletion.swift`: add a recording-start completion carrying selected region and recording options.
- Modify `Sources/FrameApp/SelectionOverlayWindow.swift`: add recording setup and active recording HUD states.
- Create `Sources/FrameApp/RecordingService.swift`: protocol, session state, fake-friendly service boundary, and real ScreenCaptureKit implementation.
- Create `Sources/FrameApp/RecordingFrameEncoder.swift`: MP4 writer and GIF writer helpers.
- Modify `Sources/FrameApp/StatusItemController.swift`: expose recording status item state and stop action.
- Create `Sources/FrameApp/VideoQuickAccessPanelController.swift`: bottom-left recording result card aligned with screenshot Quick Access.
- Create `Sources/FrameApp/VideoPreviewWindowController.swift`: playable preview window with disabled edit controls.
- Modify `Sources/FrameApp/AppDelegate.swift`: coordinate recording lifecycle.
- Modify `Sources/FrameApp/AppStrings.swift`: add localized recording labels and errors.
- Modify `Package.swift`: link any framework dependencies required by the new recording sources if SwiftPM does not infer them.
- Add or update tests under `Tests/FrameCoreTests/` and `Tests/FrameAppTests/`.

## Task 1: Recording Core Models And Naming

**Files:**
- Create: `Sources/FrameCore/RecordingOptions.swift`
- Create: `Sources/FrameCore/RecordingNaming.swift`
- Test: `Tests/FrameCoreTests/RecordingOptionsTests.swift`
- Test: `Tests/FrameCoreTests/RecordingNamingTests.swift`

- [ ] **Step 1: Write failing tests for recording options**

Create `Tests/FrameCoreTests/RecordingOptionsTests.swift`:

```swift
import XCTest
@testable import FrameCore

final class RecordingOptionsTests: XCTestCase {
    func testDefaultOptionsAreMP4WithCursorAndKeyboardHintsAndNoAudio() {
        let options = RecordingOptions.defaults

        XCTAssertEqual(options.format, .mp4)
        XCTAssertTrue(options.showsCursor)
        XCTAssertTrue(options.showsKeyboardHints)
        XCTAssertEqual(options.audioSource, .none)
    }

    func testPausedElapsedTimeExcludesPausedDuration() {
        var clock = RecordingElapsedClock(startedAt: Date(timeIntervalSince1970: 10))
        clock.pause(at: Date(timeIntervalSince1970: 20))
        clock.resume(at: Date(timeIntervalSince1970: 50))

        XCTAssertEqual(clock.elapsed(at: Date(timeIntervalSince1970: 65)), 25, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Write failing tests for recording naming**

Create `Tests/FrameCoreTests/RecordingNamingTests.swift`:

```swift
import XCTest
@testable import FrameCore

final class RecordingNamingTests: XCTestCase {
    func testFilenameUsesFrameTimestampAndSelectedExtension() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let naming = RecordingNaming(calendar: calendar, timeZone: calendar.timeZone)
        let date = Date(timeIntervalSince1970: 1_717_419_730)

        XCTAssertEqual(naming.filename(for: date, format: .mp4), "Frame 2024-06-03 12.22.10.mp4")
        XCTAssertEqual(naming.filename(for: date, format: .gif), "Frame 2024-06-03 12.22.10.gif")
    }
}
```

- [ ] **Step 3: Run tests and confirm they fail**

Run:

```bash
swift test --filter 'RecordingOptionsTests|RecordingNamingTests'
```

Expected: compile failure because `RecordingOptions`, `RecordingElapsedClock`, and `RecordingNaming` do not exist.

- [ ] **Step 4: Implement core models**

Create `Sources/FrameCore/RecordingOptions.swift`:

```swift
import Foundation

public enum RecordingFormat: String, CaseIterable, Sendable {
    case mp4
    case gif

    public var fileExtension: String { rawValue }
}

public enum RecordingAudioSource: String, CaseIterable, Sendable {
    case none
    case microphone
    case system
}

public struct RecordingOptions: Equatable, Sendable {
    public let format: RecordingFormat
    public let showsCursor: Bool
    public let showsKeyboardHints: Bool
    public let audioSource: RecordingAudioSource

    public init(
        format: RecordingFormat,
        showsCursor: Bool,
        showsKeyboardHints: Bool,
        audioSource: RecordingAudioSource
    ) {
        self.format = format
        self.showsCursor = showsCursor
        self.showsKeyboardHints = showsKeyboardHints
        self.audioSource = audioSource
    }

    public static let defaults = RecordingOptions(
        format: .mp4,
        showsCursor: true,
        showsKeyboardHints: true,
        audioSource: .none
    )
}

public struct RecordingElapsedClock: Equatable, Sendable {
    private let startedAt: Date
    private var pausedAt: Date?
    private var accumulatedPausedDuration: TimeInterval = 0

    public init(startedAt: Date) {
        self.startedAt = startedAt
    }

    public mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = date
    }

    public mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        accumulatedPausedDuration += date.timeIntervalSince(pausedAt)
        self.pausedAt = nil
    }

    public func elapsed(at date: Date) -> TimeInterval {
        let effectiveNow = pausedAt ?? date
        return max(0, effectiveNow.timeIntervalSince(startedAt) - accumulatedPausedDuration)
    }
}
```

- [ ] **Step 5: Implement recording naming**

Create `Sources/FrameCore/RecordingNaming.swift`:

```swift
import Foundation

public struct RecordingNaming: Sendable {
    private let calendar: Calendar
    private let timeZone: TimeZone

    public init(calendar: Calendar = .current, timeZone: TimeZone = .current) {
        var calendar = calendar
        calendar.timeZone = timeZone
        self.calendar = calendar
        self.timeZone = timeZone
    }

    public func filename(for date: Date = Date(), format: RecordingFormat) -> String {
        let components = calendar.dateComponents(in: timeZone, from: date)
        return String(
            format: "Frame %04d-%02d-%02d %02d.%02d.%02d.%@",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0,
            format.fileExtension
        )
    }
}
```

- [ ] **Step 6: Run targeted tests**

Run:

```bash
swift test --filter 'RecordingOptionsTests|RecordingNamingTests'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/FrameCore/RecordingOptions.swift Sources/FrameCore/RecordingNaming.swift Tests/FrameCoreTests/RecordingOptionsTests.swift Tests/FrameCoreTests/RecordingNamingTests.swift
git commit -m "feat: add recording core models"
```

## Task 2: Recording Settings Persistence

**Files:**
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing settings tests**

Append to `SettingsStoreTests`:

```swift
func testRecordingOptionsDefaultToCoreDefaults() {
    XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), RecordingOptions.defaults)
}

func testRecordingOptionsPersistSelectedValues() {
    let options = RecordingOptions(
        format: .gif,
        showsCursor: false,
        showsKeyboardHints: false,
        audioSource: .none
    )

    SettingsStore.setRecordingOptions(options, defaults: defaults)

    XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), options)
}

func testRecordingOptionsFallbackWhenPersistedFormatIsInvalid() {
    defaults.set("bad-format", forKey: SettingsStore.recordingFormatKey)
    defaults.set("bad-audio", forKey: SettingsStore.recordingAudioSourceKey)

    XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), RecordingOptions.defaults)
}
```

Add this import to the top of `Tests/FrameAppTests/SettingsStoreTests.swift`:

```swift
import FrameCore
```

- [ ] **Step 2: Run test and confirm it fails**

Run:

```bash
swift test --filter SettingsStoreTests/testRecordingOptions
```

Expected: compile failure because recording settings APIs do not exist.

- [ ] **Step 3: Implement settings keys and APIs**

Add to `SettingsStore`:

```swift
static let recordingFormatKey = "recordingFormat"
static let recordingShowsCursorKey = "recordingShowsCursor"
static let recordingShowsKeyboardHintsKey = "recordingShowsKeyboardHints"
static let recordingAudioSourceKey = "recordingAudioSource"

static func recordingOptions(defaults: UserDefaults = .standard) -> RecordingOptions {
    let defaultsOptions = RecordingOptions.defaults
    let format = RecordingFormat(rawValue: defaults.string(forKey: recordingFormatKey) ?? "")
        ?? defaultsOptions.format
    let audioSource = RecordingAudioSource(rawValue: defaults.string(forKey: recordingAudioSourceKey) ?? "")
        ?? defaultsOptions.audioSource
    let showsCursor = defaults.object(forKey: recordingShowsCursorKey) == nil
        ? defaultsOptions.showsCursor
        : defaults.bool(forKey: recordingShowsCursorKey)
    let showsKeyboardHints = defaults.object(forKey: recordingShowsKeyboardHintsKey) == nil
        ? defaultsOptions.showsKeyboardHints
        : defaults.bool(forKey: recordingShowsKeyboardHintsKey)

    return RecordingOptions(
        format: format,
        showsCursor: showsCursor,
        showsKeyboardHints: showsKeyboardHints,
        audioSource: audioSource
    )
}

static func setRecordingOptions(
    _ options: RecordingOptions,
    defaults: UserDefaults = .standard
) {
    defaults.set(options.format.rawValue, forKey: recordingFormatKey)
    defaults.set(options.showsCursor, forKey: recordingShowsCursorKey)
    defaults.set(options.showsKeyboardHints, forKey: recordingShowsKeyboardHintsKey)
    defaults.set(options.audioSource.rawValue, forKey: recordingAudioSourceKey)
}
```

- [ ] **Step 4: Run targeted tests**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FrameApp/SettingsStore.swift Tests/FrameAppTests/SettingsStoreTests.swift
git commit -m "feat: persist recording settings"
```

## Task 3: Recording History, File Writer, And Pasteboard

**Files:**
- Modify: `Sources/FrameApp/CaptureHistoryStore.swift`
- Create: `Sources/FrameApp/RecordingFileWriter.swift`
- Modify: `Sources/FrameApp/ClipboardWriter.swift`
- Test: `Tests/FrameAppTests/CaptureHistoryStoreTests.swift`
- Test: `Tests/FrameAppTests/RecordingFileWriterTests.swift`
- Test: `Tests/FrameAppTests/ClipboardWriterTests.swift`

- [ ] **Step 1: Write failing capture history test**

Append to `CaptureHistoryStoreTests`:

```swift
func testAddRecordingStoresMovieMetadataAndData() throws {
    let record = try XCTUnwrap(try store.addRecording(
        data: Data([9, 8, 7]),
        filenameExtension: "mp4",
        pixelSize: CGSize(width: 1280, height: 720),
        rect: CGRect(x: 10, y: 20, width: 1280, height: 720),
        date: Date(timeIntervalSince1970: 100),
        configuration: .init(isEnabled: true, retention: .sevenDays, sizeLimit: .twoGB)
    ))

    XCTAssertEqual(record.kind, .recording)
    XCTAssertTrue(record.filename.hasSuffix(".mp4"))
    XCTAssertEqual(record.pixelWidth, 1280)
    XCTAssertEqual(record.pixelHeight, 720)
    XCTAssertEqual(try store.data(for: record), Data([9, 8, 7]))
}
```

- [ ] **Step 2: Write failing recording file writer tests**

Create `Tests/FrameAppTests/RecordingFileWriterTests.swift`:

```swift
import XCTest
@testable import FrameApp
@testable import FrameCore

final class RecordingFileWriterTests: XCTestCase {
    func testCopyRecordingWritesToConfiguredDirectoryWithRecordingName() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameRecordingWriterTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.mp4")
        let destination = root.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let writer = RecordingFileWriter(
            naming: RecordingNaming(calendar: calendar, timeZone: calendar.timeZone),
            saveDirectory: { destination }
        )

        let written = try writer.copyRecording(
            from: source,
            format: .mp4,
            date: Date(timeIntervalSince1970: 1_717_419_730)
        )

        XCTAssertEqual(written.lastPathComponent, "Frame 2024-06-03 12.22.10.mp4")
        XCTAssertEqual(try Data(contentsOf: written), Data([1, 2, 3]))
    }
}
```

- [ ] **Step 3: Write failing file pasteboard test**

Append to `ClipboardWriterTests`:

```swift
func testWriteFileURLPlacesFileOnPasteboard() throws {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("FrameTests.\(UUID().uuidString)"))
    let writer = ClipboardWriter(pasteboard: pasteboard)
    let url = URL(fileURLWithPath: "/tmp/FrameTestRecording.mp4")

    try writer.write(fileURL: url)

    let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]
    XCTAssertEqual(objects, [url])
}
```

- [ ] **Step 4: Run tests and confirm failures**

Run:

```bash
swift test --filter 'CaptureHistoryStoreTests/testAddRecordingStoresMovieMetadataAndData|RecordingFileWriterTests|ClipboardWriterTests/testWriteFileURLPlacesFileOnPasteboard'
```

Expected: compile failures for missing APIs.

- [ ] **Step 5: Implement recording history storage**

In `CaptureHistoryStore`, add:

```swift
func addRecording(
    data: Data,
    filenameExtension: String,
    pixelSize: CGSize,
    rect: CGRect,
    date: Date = Date(),
    configuration: CaptureHistoryConfiguration = .current()
) throws -> CaptureHistoryRecord? {
    try addCapture(
        kind: .recording,
        data: data,
        filenameExtension: filenameExtension,
        imageSize: pixelSize,
        rect: rect,
        date: date,
        configuration: configuration
    )
}
```

Change `addCapture` to accept `filenameExtension: String? = nil` and choose:

```swift
let fileExtension = filenameExtension ?? kind.fileExtension
let filename = "\(id.uuidString).\(fileExtension)"
```

- [ ] **Step 6: Implement recording file writer**

Create `Sources/FrameApp/RecordingFileWriter.swift`:

```swift
import Foundation
import FrameCore

final class RecordingFileWriter {
    private let fileManager: FileManager
    private let naming: RecordingNaming
    private let saveDirectory: () throws -> URL

    init(
        fileManager: FileManager = .default,
        naming: RecordingNaming = RecordingNaming(),
        saveDirectory: @escaping () throws -> URL = { try SettingsStore.screenshotDirectory() }
    ) {
        self.fileManager = fileManager
        self.naming = naming
        self.saveDirectory = saveDirectory
    }

    func copyRecording(from sourceURL: URL, format: RecordingFormat, date: Date = Date()) throws -> URL {
        let directory = try saveDirectory()
        let destination = directory.appendingPathComponent(
            naming.filename(for: date, format: format),
            isDirectory: false
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: sourceURL, to: destination)
        return destination
    }
}
```

- [ ] **Step 7: Implement file URL pasteboard writing**

Add to `ClipboardWriter`:

```swift
func write(fileURL: URL) throws {
    pasteboard.clearContents()
    guard pasteboard.writeObjects([fileURL as NSURL]) else {
        throw ClipboardWriterError.writeFailed
    }
}
```

- [ ] **Step 8: Run targeted tests**

Run:

```bash
swift test --filter 'CaptureHistoryStoreTests|RecordingFileWriterTests|ClipboardWriterTests'
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add Sources/FrameApp/CaptureHistoryStore.swift Sources/FrameApp/RecordingFileWriter.swift Sources/FrameApp/ClipboardWriter.swift Tests/FrameAppTests/CaptureHistoryStoreTests.swift Tests/FrameAppTests/RecordingFileWriterTests.swift Tests/FrameAppTests/ClipboardWriterTests.swift
git commit -m "feat: add recording file outputs"
```

## Task 4: Recording Completion And HUD State Model

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayCompletion.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [ ] **Step 1: Write failing completion test**

Append to `SelectionOverlayCompletionTests`:

```swift
func testStartRecordingCompletionExposesSelectionAndOptions() {
    let selection = SelectionCapture(rect: CGRect(x: 1, y: 2, width: 300, height: 200), kind: .region)
    let options = RecordingOptions(format: .gif, showsCursor: false, showsKeyboardHints: true, audioSource: .none)

    let completion = SelectionOverlayCompletion.startRecording(selection, options)

    XCTAssertEqual(completion.selection?.rect, selection.rect)
    XCTAssertEqual(completion.recordingOptions, options)
}
```

- [ ] **Step 2: Write failing HUD state tests**

Append to `SelectionOverlayCompletionTests`:

```swift
@MainActor
func testRecordingButtonSwitchesHUDIntoRecordingSetupMode() throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let window = try makeOverlayWindowForTesting(
        initialGlobalRect: CGRect(x: screen.frame.minX + 20, y: screen.frame.minY + 20, width: 240, height: 160)
    )

    XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "录屏"))

    XCTAssertEqual(window.recordingHUDModeForTesting(), "setup")
    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("开始录制"))
    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("MP4"))
    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("显示鼠标指针"))
    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("显示键盘提示"))
}
```

- [ ] **Step 3: Run tests and confirm failures**

Run:

```bash
swift test --filter 'SelectionOverlayCompletionTests/testStartRecordingCompletionExposesSelectionAndOptions|SelectionOverlayCompletionTests/testRecordingButtonSwitchesHUDIntoRecordingSetupMode'
```

Expected: compile failures for recording completion and HUD testing API.

- [ ] **Step 4: Implement completion model**

Add to `SelectionOverlayCompletion`:

```swift
case startRecording(SelectionCapture, RecordingOptions)

var recordingOptions: RecordingOptions? {
    switch self {
    case let .startRecording(_, options):
        options
    case .capture, .recognizeText, .fullScreen:
        nil
    }
}
```

Update `selection` to include `.startRecording`.

- [ ] **Step 5: Add recording strings**

Add properties to `AppStrings` for both languages:

```swift
var recording: String
var recordingStart: String
var recordingStop: String
var recordingPause: String
var recordingResume: String
var recordingFormatMP4: String
var recordingFormatGIF: String
var recordingShowCursor: String
var recordingShowKeyboardHints: String
var recordingFailedTitle: String
```

Use Chinese labels such as `录屏`, `开始录制`, `停止录制`, `暂停`, `继续`, `MP4`, `GIF`, `显示鼠标指针`, and `显示键盘提示`.

- [ ] **Step 6: Implement setup-mode HUD**

In `SelectionOverlayWindow`, add a private HUD mode enum:

```swift
private enum RecordingHUDMode: Equatable {
    case screenshot
    case setup
    case active(isPaused: Bool)
}
```

Add a recording button to screenshot mode. Its action should set `recordingHUDMode = .setup`, refresh mode controls, and leave the selection editable.

Add setup controls for start, format, cursor, and keyboard hints. Start emits:

```swift
completeSelection(with: .startRecording(activeSelection, currentRecordingOptions))
```

Format toggles between `.mp4` and `.gif`. Cursor and keyboard controls toggle booleans in `currentRecordingOptions` and persist through `SettingsStore.setRecordingOptions`.

- [ ] **Step 7: Run targeted tests**

Run:

```bash
swift test --filter SelectionOverlayCompletionTests
```

Expected: PASS or only pre-existing local AppKit instability; investigate any assertion failure before continuing.

- [ ] **Step 8: Commit**

```bash
git add Sources/FrameApp/SelectionOverlayCompletion.swift Sources/FrameApp/SelectionOverlayWindow.swift Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/SelectionOverlayCompletionTests.swift
git commit -m "feat: add recording setup HUD"
```

## Task 5: Recording Service State And Fake-Friendly Boundary

**Files:**
- Create: `Sources/FrameApp/RecordingService.swift`
- Test: `Tests/FrameAppTests/RecordingServiceTests.swift`

- [ ] **Step 1: Write failing state tests**

Create `Tests/FrameAppTests/RecordingServiceTests.swift`:

```swift
import XCTest
@testable import FrameApp
@testable import FrameCore

final class RecordingServiceTests: XCTestCase {
    func testSessionStateTransitionsFromRecordingToPausedToRecordingToFinished() async throws {
        let service = FakeRecordingService()
        let request = RecordingRequest(
            selection: SelectionCapture(rect: CGRect(x: 0, y: 0, width: 320, height: 240), kind: .region),
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
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
swift test --filter RecordingServiceTests
```

Expected: compile failure for missing recording service types.

- [ ] **Step 3: Implement request, result, and protocol types**

Create `Sources/FrameApp/RecordingService.swift` with:

```swift
import AppKit
import FrameCore

struct CapturedRecording: Equatable, Identifiable {
    let id: UUID
    let fileURL: URL
    let format: RecordingFormat
    let rect: CGRect
    let pixelSize: CGSize
    let byteSize: Int
    let duration: TimeInterval
}

struct RecordingRequest: Equatable {
    let selection: SelectionCapture
    let options: RecordingOptions
}

enum RecordingSessionState: Equatable {
    case recording
    case paused
    case finishing
    case finished
    case failed(String)
}

protocol RecordingSessionControlling: AnyObject {
    var state: RecordingSessionState { get }
    func pause() async throws
    func resume() async throws
    func stop() async throws -> CapturedRecording
    func cancel() async
}

protocol RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling
}
```

- [ ] **Step 4: Implement fake service for tests**

In the test file, add:

```swift
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

    func pause() async throws { state = .paused }
    func resume() async throws { state = .recording }
    func cancel() async { state = .finished }

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
```

- [ ] **Step 5: Run targeted tests**

Run:

```bash
swift test --filter RecordingServiceTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FrameApp/RecordingService.swift Tests/FrameAppTests/RecordingServiceTests.swift
git commit -m "feat: add recording service boundary"
```

## Task 6: ScreenCaptureKit Recording Implementation

**Files:**
- Modify: `Sources/FrameApp/RecordingService.swift`
- Create: `Sources/FrameApp/RecordingFrameEncoder.swift`
- Test: `Tests/FrameAppTests/RecordingServiceTests.swift`

- [ ] **Step 1: Write failing display validation tests**

Append to `RecordingServiceTests`:

```swift
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
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
swift test --filter RecordingServiceTests/testDisplayResolver
```

Expected: compile failure for missing resolver.

- [ ] **Step 3: Implement display resolver**

Add to `RecordingService.swift`:

```swift
struct RecordingDisplaySelection: Equatable {
    let screenFrame: CGRect
    let selectionRect: CGRect
}

enum RecordingServiceError: LocalizedError {
    case invalidSelectionRect(CGRect)
    case selectionSpansMultipleDisplays
    case displayNotFound
    case outputFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSelectionRect(rect):
            "录屏区域无效：\(rect.debugDescription)"
        case .selectionSpansMultipleDisplays:
            "录屏区域只能位于一个显示器内。请重新选择一个屏幕上的区域。"
        case .displayNotFound:
            "无法找到要录制的显示器。"
        case let .outputFailed(message):
            message
        }
    }
}

enum RecordingDisplayResolver {
    static func resolve(selection: CGRect, screenFrames: [CGRect]) throws -> RecordingDisplaySelection {
        guard !selection.isNull, !selection.isEmpty, selection.width > 0, selection.height > 0 else {
            throw RecordingServiceError.invalidSelectionRect(selection)
        }

        let intersectingScreens = screenFrames.filter { !$0.intersection(selection).isNull && !$0.intersection(selection).isEmpty }
        guard intersectingScreens.count == 1, let screen = intersectingScreens.first else {
            throw intersectingScreens.isEmpty ? RecordingServiceError.displayNotFound : RecordingServiceError.selectionSpansMultipleDisplays
        }
        guard screen.contains(selection) else {
            throw RecordingServiceError.selectionSpansMultipleDisplays
        }

        return RecordingDisplaySelection(screenFrame: screen, selectionRect: selection)
    }
}
```

- [ ] **Step 4: Implement encoder helpers**

Create `Sources/FrameApp/RecordingFrameEncoder.swift` with two focused types:

```swift
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import MobileCoreServices
import UniformTypeIdentifiers

protocol RecordingFrameEncoding {
    func append(_ sampleBuffer: CMSampleBuffer) throws
    func finish() async throws -> URL
}
```

Implement `MP4RecordingFrameEncoder` using `AVAssetWriter`, `AVAssetWriterInput`, and `AVAssetWriterInputPixelBufferAdaptor`. Implement `GIFRecordingFrameEncoder` by converting captured `CGImage` frames through `CGImageDestination` with `kUTTypeGIF` or `UTType.gif.identifier`. Keep both encoders initialized with `outputURL`, `pixelSize`, and `durationSource`.

- [ ] **Step 5: Implement real recording service**

Extend `RecordingService.swift` with a concrete `ScreenCaptureRecordingService: RecordingServicing`:

```swift
@MainActor
final class ScreenCaptureRecordingService: RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling {
        let resolved = try RecordingDisplayResolver.resolve(
            selection: request.selection.rect,
            screenFrames: NSScreen.screens.map(\.frame)
        )
        let session = try await ScreenCaptureRecordingSession(request: request, resolvedSelection: resolved)
        try await session.start()
        return session
    }
}
```

`ScreenCaptureRecordingSession` should:

- resolve `SCDisplay` through `SCShareableContent`
- create an `SCContentFilter(display:excludingWindows:)` display filter, adjusting only for the exact initializer spelling available in the local macOS SDK
- configure width, height, source rect, queue depth, and `showsCursor`
- consume screen sample buffers from `SCStreamOutput`
- skip appending buffers while paused
- write MP4 via `MP4RecordingFrameEncoder`
- write GIF via `GIFRecordingFrameEncoder`
- stop stream and finalize in `stop()`

- [ ] **Step 6: Add compile verification**

Run:

```bash
swift build
```

Expected: PASS. If SDK API names differ, adjust only inside `RecordingService.swift` and `RecordingFrameEncoder.swift` while preserving the protocol boundary and tests.

- [ ] **Step 7: Run targeted tests**

Run:

```bash
swift test --filter RecordingServiceTests
```

Expected: PASS for resolver and fake session tests; no live ScreenCaptureKit capture should run in tests.

- [ ] **Step 8: Commit**

```bash
git add Sources/FrameApp/RecordingService.swift Sources/FrameApp/RecordingFrameEncoder.swift Tests/FrameAppTests/RecordingServiceTests.swift
git commit -m "feat: implement recording service"
```

## Task 7: Active Recording HUD, Pause/Resume, And Keyboard Hints

**Files:**
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Create: `Sources/FrameApp/KeyboardHintOverlayController.swift`
- Test: `Tests/FrameAppTests/SelectionOverlayCompletionTests.swift`

- [ ] **Step 1: Write failing HUD active-state tests**

Append to `SelectionOverlayCompletionTests`:

```swift
@MainActor
func testRecordingHUDShowsElapsedTimePauseAndStopWhileActive() throws {
    let screen = try XCTUnwrap(NSScreen.screens.first)
    let window = try makeOverlayWindowForTesting(
        initialGlobalRect: CGRect(x: screen.frame.minX + 20, y: screen.frame.minY + 20, width: 240, height: 160)
    )

    window.enterActiveRecordingModeForTesting(elapsed: 24, isPaused: false)

    XCTAssertEqual(window.recordingHUDModeForTesting(), "active")
    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("暂停"))
    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("停止录制"))
    XCTAssertEqual(window.recordingElapsedTextForTesting(), "00:24")
}

@MainActor
func testPausedRecordingHUDShowsResume() throws {
    let window = try makeOverlayWindowForTesting()

    window.enterActiveRecordingModeForTesting(elapsed: 24, isPaused: true)

    XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("继续"))
}
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
swift test --filter SelectionOverlayCompletionTests/testRecordingHUD
```

Expected: compile failure for testing APIs and active mode.

- [ ] **Step 3: Implement active HUD mode**

In `SelectionOverlayWindow`:

- add callbacks `onRecordingPause`, `onRecordingResume`, and `onRecordingStop`
- add `enterActiveRecordingMode(elapsed:isPaused:)`
- freeze selection interactions in active and paused modes
- show elapsed text as `mm:ss`
- show Pause or Resume depending on state
- show Stop in all active/paused recording states
- route Stop through callback instead of keyboard shortcut

- [ ] **Step 4: Implement keyboard hint overlay controller**

Create `Sources/FrameApp/KeyboardHintOverlayController.swift` with an
`NSVisualEffectView` HUD container so the first version already matches the
recording HUD chrome:

```swift
import AppKit

@MainActor
final class KeyboardHintOverlayController {
    private var panel: NSPanel?

    func show(text: String, near rect: CGRect) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .labelColor

        let content = NSVisualEffectView()
        content.material = .hudWindow
        content.blendingMode = .withinWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.cornerCurve = .continuous
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])

        panel.contentView = content
        panel.setFrameOrigin(CGPoint(x: rect.midX, y: rect.minY - 48))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 180, height: 36), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.sharingType = .none
        return panel
    }
}
```

- [ ] **Step 5: Run targeted AppKit tests**

Run:

```bash
swift test --filter SelectionOverlayCompletionTests
```

Expected: PASS or documented local AppKit runner instability.

- [ ] **Step 6: Commit**

```bash
git add Sources/FrameApp/SelectionOverlayWindow.swift Sources/FrameApp/KeyboardHintOverlayController.swift Tests/FrameAppTests/SelectionOverlayCompletionTests.swift
git commit -m "feat: add active recording HUD"
```

## Task 8: Status Item Recording State

**Files:**
- Modify: `Sources/FrameApp/StatusItemController.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/StatusItemControllerTests.swift`

- [ ] **Step 1: Write failing status item tests**

Append to `StatusItemControllerTests`:

```swift
func testRecordingStateShowsStopRecordingItemBeforeCapture() {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    defer { NSStatusBar.system.removeStatusItem(statusItem) }
    var didStop = false

    let controller = StatusItemController(
        statusItem: statusItem,
        strings: AppStrings(language: .en),
        onCapture: {},
        onHistory: {},
        onSettings: {},
        onStopRecording: { didStop = true }
    )
    controller.setRecordingState(.recording)

    let titles = statusItem.menu?.items.map(\.title) ?? []
    XCTAssertEqual(titles.first, "Stop Recording")

    statusItem.menu?.items.first?.performAction()
    XCTAssertTrue(didStop)
}
```

- [ ] **Step 2: Run test and confirm failure**

Run:

```bash
swift test --filter StatusItemControllerTests/testRecordingStateShowsStopRecordingItemBeforeCapture
```

Expected: compile failure for new initializer and state API.

- [ ] **Step 3: Implement status item recording state**

Add:

```swift
enum StatusItemRecordingState {
    case idle
    case recording
    case paused
}
```

Update `StatusItemController` initializer to accept `onStopRecording`. Add `setRecordingState(_:)`, rebuild the menu, and use a red recording image or template fallback while `.recording` or `.paused`. The first menu item should be Stop Recording while active.

- [ ] **Step 4: Run targeted tests**

Run:

```bash
swift test --filter StatusItemControllerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/FrameApp/StatusItemController.swift Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/StatusItemControllerTests.swift
git commit -m "feat: show recording status item state"
```

## Task 9: Video Quick Access And Preview

**Files:**
- Create: `Sources/FrameApp/VideoQuickAccessPanelController.swift`
- Create: `Sources/FrameApp/VideoPreviewWindowController.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/VideoQuickAccessPanelControllerTests.swift`
- Test: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`

- [ ] **Step 1: Write failing Quick Access tests**

Create `Tests/FrameAppTests/VideoQuickAccessPanelControllerTests.swift`:

```swift
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoQuickAccessPanelControllerTests: XCTestCase {
    func testVideoQuickAccessExposesDownloadCopyPreviewAndDisabledEdit() {
        let recording = CapturedRecording(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
            format: .mp4,
            rect: CGRect(x: 0, y: 0, width: 320, height: 240),
            pixelSize: CGSize(width: 320, height: 240),
            byteSize: 10,
            duration: 24
        )
        let controller = VideoQuickAccessPanelController()

        controller.show(for: recording, preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100), strings: AppStrings(language: .en), download: { true }, copy: { true }, preview: { true }, close: {})

        XCTAssertEqual(controller.actionLabelsForTesting(recordingID: recording.id), ["Download", "Copy", "Preview", "Edit", "Close"])
        XCTAssertFalse(controller.isEditEnabledForTesting(recordingID: recording.id))
    }
}
```

- [ ] **Step 2: Write failing preview tests**

Create `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`:

```swift
import XCTest
@testable import FrameApp
@testable import FrameCore

@MainActor
final class VideoPreviewWindowControllerTests: XCTestCase {
    func testPreviewWindowKeepsEditControlsDisabled() {
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

        controller.show(recording: recording, strings: AppStrings(language: .en), copy: { true }, download: { true })

        XCTAssertFalse(controller.isEditingEnabledForTesting(recordingID: recording.id))
    }
}
```

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
swift test --filter 'VideoQuickAccessPanelControllerTests|VideoPreviewWindowControllerTests'
```

Expected: compile failure for missing controllers.

- [ ] **Step 4: Implement video Quick Access**

Create a controller that mirrors `QuickAccessPanelController` placement and stack behavior but accepts `CapturedRecording`. Actions:

- Download uses `tray.and.arrow.down`
- Copy uses `doc.on.doc`
- Preview uses `play.rectangle`
- Edit uses `slider.horizontal.3` or matching edit icon, disabled
- Close uses existing close styling

Expose testing helpers:

```swift
func actionLabelsForTesting(recordingID: UUID) -> [String]
func isEditEnabledForTesting(recordingID: UUID) -> Bool
```

- [ ] **Step 5: Implement playable preview window**

Create `VideoPreviewWindowController` using `AVPlayerView` for playback. Keep toolbar actions aligned with `ImageWorkspacePanelController`; Copy and Download are enabled, editing controls are disabled. Expose:

```swift
func isEditingEnabledForTesting(recordingID: UUID) -> Bool
```

- [ ] **Step 6: Run targeted tests**

Run:

```bash
swift test --filter 'VideoQuickAccessPanelControllerTests|VideoPreviewWindowControllerTests'
```

Expected: PASS or documented AppKit local-only instability.

- [ ] **Step 7: Commit**

```bash
git add Sources/FrameApp/VideoQuickAccessPanelController.swift Sources/FrameApp/VideoPreviewWindowController.swift Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/VideoQuickAccessPanelControllerTests.swift Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift
git commit -m "feat: add video quick access preview"
```

## Task 10: AppDelegate Recording Integration

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Sources/FrameApp/CaptureHistoryWindowController.swift`
- Test: no new AppDelegate unit test in this task; rely on controller/service tests plus the manual smoke checklist because this integration depends on live app coordination and ScreenCaptureKit permission.

- [ ] **Step 1: Add AppDelegate recording dependencies**

Add properties:

```swift
private let recordingService: RecordingServicing = ScreenCaptureRecordingService()
private let videoQuickAccessPanelController = VideoQuickAccessPanelController()
private let videoPreviewWindowController = VideoPreviewWindowController()
private let recordingFileWriter = RecordingFileWriter()
private var activeRecordingSession: RecordingSessionControlling?
private var activeRecordingOptions = RecordingOptions.defaults
```

- [ ] **Step 2: Wire status item stop callback**

Update `StatusItemController` creation:

```swift
statusItemController = StatusItemController(
    strings: strings,
    onCapture: { [weak self] in self?.onCapture() },
    onHistory: { [weak self] in self?.onHistory() },
    onSettings: { [weak self] in self?.onSettings() },
    onStopRecording: { [weak self] in self?.stopActiveRecording() }
)
```

- [ ] **Step 3: Route recording completion**

In `startCaptureFlow()` switch:

```swift
case let .startRecording(selection, options):
    await self.startRecording(selection: selection, options: options, anchor: quickAccessAnchor)
```

- [ ] **Step 4: Implement recording lifecycle methods**

Add methods:

```swift
private func startRecording(selection: SelectionCapture, options: RecordingOptions, anchor: CGRect?) async {
    do {
        let session = try await recordingService.startRecording(RecordingRequest(selection: selection, options: options))
        activeRecordingSession = session
        statusItemController?.setRecordingState(.recording)
        selectionOverlayController.enterActiveRecordingMode()
    } catch {
        quickAccessPanelController.restoreTemporarilyHiddenPreviews()
        showQuickAccessFailedAlert(title: strings.recordingFailedTitle, error: error)
    }
}

private func stopActiveRecording() {
    guard let session = activeRecordingSession else { return }
    Task { @MainActor [weak self] in
        guard let self else { return }
        do {
            self.statusItemController?.setRecordingState(.idle)
            let recording = try await session.stop()
            self.activeRecordingSession = nil
            self.storeInCaptureHistory(recording)
            self.showVideoQuickAccess(for: recording, anchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor())
        } catch {
            self.statusItemController?.setRecordingState(.idle)
            self.activeRecordingSession = nil
            self.showQuickAccessFailedAlert(title: self.strings.recordingFailedTitle, error: error)
        }
    }
}
```

If the earlier overlay/session API names differ, rename this snippet's call sites
to the earlier names before compiling. Do not change the behavior: successful
start sets recording state, failed start restores Quick Access previews, and
stop finalizes the active session exactly once.

- [ ] **Step 5: Implement video output actions**

Add:

```swift
private func showVideoQuickAccess(for recording: CapturedRecording, anchor: CGRect?) {
    videoQuickAccessPanelController.show(
        for: recording,
        preferredAnchor: anchor,
        strings: strings,
        download: { [weak self] in self?.downloadRecording(recording) ?? false },
        copy: { [weak self] in self?.copyRecording(recording) ?? false },
        preview: { [weak self] in self?.openVideoPreview(recording) ?? false },
        close: {}
    )
}
```

Implement `downloadRecording`, `copyRecording`, and `openVideoPreview` using `RecordingFileWriter`, `ClipboardWriter.write(fileURL:)`, and `VideoPreviewWindowController`.

- [ ] **Step 6: Store recordings in history**

Add:

```swift
private func storeInCaptureHistory(_ recording: CapturedRecording) {
    do {
        let data = try Data(contentsOf: recording.fileURL)
        _ = try captureHistoryStore.addRecording(
            data: data,
            filenameExtension: recording.format.fileExtension,
            pixelSize: recording.pixelSize,
            rect: recording.rect
        )
    } catch {
        NSLog("Frame 写入录屏历史失败: \(error.localizedDescription)")
    }
}
```

- [ ] **Step 7: Run build and stable tests**

Run:

```bash
swift build
swift test --skip HUDSizeControlTests --skip ImageWorkspacePanelControllerTests --skip ScreenshotDragItemProviderTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add Sources/FrameApp/AppDelegate.swift Sources/FrameApp/CaptureHistoryWindowController.swift
git commit -m "feat: integrate selection recording flow"
```

## Task 11: Docs, README Alignment, And Manual Smoke Checklist

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/development.md`
- Modify: `docs/testing.md`
- Modify: `docs/permissions.md`
- Modify: `DESIGN.md`
- Inspect: `README.md`
- Inspect: `README_ZH.md`

- [ ] **Step 1: Update architecture documentation**

Add recording to the architecture diagram and runtime flow. Include:

```markdown
Recording uses the existing selection overlay as its entry point. The overlay
switches into recording setup and active recording HUD modes, while
RecordingService owns ScreenCaptureKit capture and output finalization.
```

- [ ] **Step 2: Update design documentation**

In `DESIGN.md`, add a short `Recording HUD` subsection under HUD guidance:

```markdown
Recording HUD states inherit screenshot HUD chrome. Setup controls stay
icon-only; active recording shows elapsed time, pause/resume, and stop. Recording
HUD and keyboard hints must be visible to the user but excluded from recorded
pixels.
```

- [ ] **Step 3: Update manual smoke checklist**

Add to `docs/development.md`:

```markdown
Use the screenshot shortcut, draw a region, switch to recording, record MP4 and
GIF, pause/resume, stop from the HUD, stop from the red status item, confirm the
HUD is absent from full-screen output, copy the recording file, download it, and
open the playable preview.
```

- [ ] **Step 4: Update permission/testing docs**

Document that automated tests do not run live recording and manual stable-signed
testing must verify ScreenCaptureKit recording and HUD exclusion.

- [ ] **Step 5: Check README alignment**

Read `README.md` and `README_ZH.md`. If either README lists current
user-facing features, update both files with matching recording wording. If both
README files intentionally describe only the already-shipped screenshot loop,
leave both unchanged and record that decision in the task handoff.

- [ ] **Step 6: Commit**

```bash
git add docs/architecture.md docs/development.md docs/testing.md docs/permissions.md DESIGN.md README.md README_ZH.md
git commit -m "docs: document selection recording workflow"
```

If README files are unchanged, omit them from `git add`.

## Task 12: Full Verification And Local GUI Build

**Files:**
- Generated: `.build/app/Frame.app`

- [ ] **Step 1: Run stable automated verification**

Run:

```bash
swift test
swift build
scripts/package-app.sh
```

Expected: PASS. If known local AppKit suites are toolchain-fragile, run the documented skip command and record the exact skipped suites and reason.

- [ ] **Step 2: Run stable local signing package**

Run:

```bash
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
```

Expected: `.build/app/Frame.app` is produced and signed.

- [ ] **Step 3: Ask before replacing local test app**

Because this includes user-facing GUI behavior, ask:

```text
要我现在用稳定签名版本替换 ~/Applications/Frame.app 并打开给你测试吗？
```

- [ ] **Step 4: If approved, replace and verify signature**

Run:

```bash
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
codesign -dv --verbose=2 ~/Applications/Frame.app 2>&1 | grep "Authority=Frame Local Dev CLI"
```

Expected: output contains `Authority=Frame Local Dev CLI`.

- [ ] **Step 5: Manual smoke checklist**

Verify manually:

- region MP4 recording
- region GIF recording
- full-screen selection recording
- recording HUD is absent from output
- keyboard hint overlay is absent from output
- cursor toggle changes output behavior
- keyboard hint toggle changes visible overlay behavior
- pause/resume excludes paused time from output
- HUD stop works
- red status item stop works
- video Quick Access appears bottom-left
- copy writes a file URL pasteboard item
- download writes to configured save directory
- preview plays
- edit is disabled
- recording history shows and opens recordings

- [ ] **Step 6: Final commit if verification fixes changed files**

If verification required fixes, commit them:

```bash
git add <changed-files>
git commit -m "fix: stabilize selection recording"
```

Then rerun the affected verification command.
