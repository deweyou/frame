# Recording Video Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement MP4-only recording editing with trim start/end, fixed speed presets, clipped playback, Save Current choices, direct Download, and GIF editing disabled.

**Architecture:** Keep one user-facing `VideoPreviewWindowController`, but move deterministic edit rules into `FrameCore`, AVFoundation export into a focused `FrameApp` service, and editor controls/playback coordination into small helpers. Quick Access and AppDelegate route product actions without creating a second video workspace window.

**Tech Stack:** Swift, AppKit, AVKit, AVFoundation, XCTest, SwiftPM.

---

## File Structure

- Create: `Sources/FrameCore/VideoEditingState.swift`
  - Owns deterministic MP4 editing rules: speed presets, `0.01s` time quantization, range validation, dirty state, selected duration, output duration.
- Create: `Tests/FrameCoreTests/VideoEditingStateTests.swift`
  - Unit tests for the deterministic model.
- Create: `Sources/FrameApp/VideoEditingExporter.swift`
  - Uses AVFoundation to export edited MP4 files to temporary Frame-owned URLs.
- Create: `Tests/FrameAppTests/VideoEditingExporterTests.swift`
  - Generates tiny MP4 fixtures and verifies trim/speed duration behavior.
- Create: `Sources/FrameApp/VideoEditorBarView.swift`
  - AppKit editor bar with a mini timeline, read-only start/end time labels, speed controls, trim range, and testing API.
- Modify: `Sources/FrameApp/VideoPreviewWindowController.swift`
  - Keeps the single window, adds MP4 editor bar, playback coordination, Save Current menu, dirty close prompt, and test hooks.
- Modify: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`
  - Updates old disabled MP4 edit expectation and covers MP4/GIF UI and action routing.
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
  - Enables Edit for MP4 recording cards, keeps GIF Edit disabled, and routes Edit to the same preview window.
- Modify: `Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift`
  - Covers enabled MP4 Edit, disabled GIF Edit, and Edit invoking the preview/edit route.
- Modify: `Sources/FrameApp/AppDelegate.swift`
  - Wires Video Preview copy/save/download closures to edited recording output; refreshes Quick Access on Replace Current; creates new Quick Access on Save As New.
- Modify: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`
  - Covers recording edit routing through injected fake exporter and preview controllers.
- Modify: `Sources/FrameApp/AppStrings.swift`
  - Adds recording editor labels and disabled GIF edit copy in English and Chinese.
- Modify: `Tests/FrameAppTests/AppStringsTests.swift`
  - Locks new localized copy.
- Modify after feature implementation: `README.md`, `README_ZH.md`, `docs/architecture.md`, `DESIGN.md`
  - Documents shipped user-facing behavior.

## Follow-up: Native Playback Controls And Editing Window Capture

**Files:**
- Modify: `Sources/FrameApp/WindowCandidateProvider.swift`
  - Keep transient Frame panels filtered, but allow Frame-owned editing windows
    such as Image Workspace and Video Preview to be selected by the existing
    double-click window screenshot flow.
- Modify: `Tests/FrameAppTests/WindowCandidateProviderTests.swift`
  - Cover current-process editing windows without a CG window name and MP4 video
    preview windows as eligible while Quick Access remains ineligible.
- Modify: `Sources/FrameApp/VideoPreviewWindowController.swift`
  - Hide native AVPlayer controls, wire play/pause and seek callbacks from the
    editor bar, keep playback clipped to the trim range, and update the custom
    timeline during playback.
- Modify: `Sources/FrameApp/VideoEditorBarView.swift`
  - Replace the segmented speed control with a button/dropdown menu, add a custom
    trim/progress timeline with start/end handles, and expose stable testing APIs
    for play/pause, seek, trim, and speed selection.
- Modify: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`
  - Assert MP4 previews do not expose native AVPlayer controls and that custom
    play/pause/seek routes to the player coordinator.
- Modify: `Tests/FrameAppTests/VideoEditorBarViewTests.swift`
  - Assert the speed dropdown emits preset changes and the timeline emits
    trim/seek changes.

## Task 1: Core Video Editing State

**Files:**
- Create: `Sources/FrameCore/VideoEditingState.swift`
- Create: `Tests/FrameCoreTests/VideoEditingStateTests.swift`

- [ ] **Step 1: Write failing tests for speed presets and default state**

Add `Tests/FrameCoreTests/VideoEditingStateTests.swift`:

```swift
import XCTest
@testable import FrameCore

final class VideoEditingStateTests: XCTestCase {
    func testSpeedPresetsAreFixedAndDisplayable() {
        XCTAssertEqual(VideoPlaybackSpeed.presets.map(\.rate), [0.5, 1, 1.25, 1.5, 2, 4, 8])
        XCTAssertEqual(VideoPlaybackSpeed.presets.map(\.displayName), ["0.5x", "1x", "1.25x", "1.5x", "2x", "4x", "8x"])
    }

    func testDefaultStateUsesFullDurationAtNormalSpeed() throws {
        let state = try VideoEditingState(sourceDuration: 24)

        XCTAssertEqual(state.startTime, 0, accuracy: 0.0001)
        XCTAssertEqual(state.endTime, 24, accuracy: 0.0001)
        XCTAssertEqual(state.speed, .one)
        XCTAssertEqual(state.selectedDuration, 24, accuracy: 0.0001)
        XCTAssertEqual(state.outputDuration, 24, accuracy: 0.0001)
        XCTAssertFalse(state.isDirty)
    }
}
```

- [ ] **Step 2: Run tests and verify they fail because types are missing**

Run:

```sh
swift test --filter VideoEditingStateTests
```

Expected: compile failure for missing `VideoPlaybackSpeed` and `VideoEditingState`.

- [ ] **Step 3: Implement speed presets and default state**

Create `Sources/FrameCore/VideoEditingState.swift`:

```swift
import Foundation

public enum VideoEditingStateError: Equatable, Error {
    case invalidSourceDuration
    case invalidTrimRange
}

public struct VideoPlaybackSpeed: Equatable, Sendable {
    public let rate: Double
    public let displayName: String

    public init(rate: Double, displayName: String) {
        self.rate = rate
        self.displayName = displayName
    }

    public static let half = VideoPlaybackSpeed(rate: 0.5, displayName: "0.5x")
    public static let one = VideoPlaybackSpeed(rate: 1, displayName: "1x")
    public static let oneAndQuarter = VideoPlaybackSpeed(rate: 1.25, displayName: "1.25x")
    public static let oneAndHalf = VideoPlaybackSpeed(rate: 1.5, displayName: "1.5x")
    public static let double = VideoPlaybackSpeed(rate: 2, displayName: "2x")
    public static let quadruple = VideoPlaybackSpeed(rate: 4, displayName: "4x")
    public static let octuple = VideoPlaybackSpeed(rate: 8, displayName: "8x")

    public static let presets: [VideoPlaybackSpeed] = [
        .half, .one, .oneAndQuarter, .oneAndHalf, .double, .quadruple, .octuple,
    ]
}

public struct VideoEditingState: Equatable, Sendable {
    public static let precision: TimeInterval = 0.01
    public static let minimumSelectedDuration: TimeInterval = 0.05

    public let sourceDuration: TimeInterval
    public private(set) var startTime: TimeInterval
    public private(set) var endTime: TimeInterval
    public private(set) var speed: VideoPlaybackSpeed

    public init(sourceDuration: TimeInterval) throws {
        guard sourceDuration.isFinite, sourceDuration > Self.minimumSelectedDuration else {
            throw VideoEditingStateError.invalidSourceDuration
        }

        self.sourceDuration = Self.quantized(sourceDuration)
        self.startTime = 0
        self.endTime = Self.quantized(sourceDuration)
        self.speed = .one
    }

    public var selectedDuration: TimeInterval {
        max(0, endTime - startTime)
    }

    public var outputDuration: TimeInterval {
        selectedDuration / speed.rate
    }

    public var isDirty: Bool {
        abs(startTime) > 0.0001
            || abs(endTime - sourceDuration) > 0.0001
            || speed != .one
    }

    public static func quantized(_ value: TimeInterval) -> TimeInterval {
        guard value.isFinite else {
            return 0
        }
        return (value / precision).rounded() * precision
    }
}
```

- [ ] **Step 4: Run tests and verify they pass**

Run:

```sh
swift test --filter VideoEditingStateTests
```

Expected: PASS.

- [ ] **Step 5: Add failing tests for quantization, validation, and dirty state**

Append to `VideoEditingStateTests`:

```swift
func testUpdatingRangeQuantizesToHundredthSecondAndMarksDirty() throws {
    var state = try VideoEditingState(sourceDuration: 24)

    try state.setTrimRange(start: 3.274, end: 18.636)

    XCTAssertEqual(state.startTime, 3.27, accuracy: 0.0001)
    XCTAssertEqual(state.endTime, 18.64, accuracy: 0.0001)
    XCTAssertEqual(state.selectedDuration, 15.37, accuracy: 0.0001)
    XCTAssertTrue(state.isDirty)
}

func testRejectsInvalidRangesAfterQuantization() throws {
    var state = try VideoEditingState(sourceDuration: 24)

    XCTAssertThrowsError(try state.setTrimRange(start: 10, end: 10.03)) { error in
        XCTAssertEqual(error as? VideoEditingStateError, .invalidTrimRange)
    }
    XCTAssertThrowsError(try state.setTrimRange(start: -0.01, end: 5)) { error in
        XCTAssertEqual(error as? VideoEditingStateError, .invalidTrimRange)
    }
    XCTAssertThrowsError(try state.setTrimRange(start: 0, end: 24.01)) { error in
        XCTAssertEqual(error as? VideoEditingStateError, .invalidTrimRange)
    }
}

func testSpeedChangesOutputDurationAndDirtyState() throws {
    var state = try VideoEditingState(sourceDuration: 20)

    try state.setSpeed(.double)

    XCTAssertEqual(state.selectedDuration, 20, accuracy: 0.0001)
    XCTAssertEqual(state.outputDuration, 10, accuracy: 0.0001)
    XCTAssertTrue(state.isDirty)
}
```

- [ ] **Step 6: Run tests and verify they fail because mutators are missing**

Run:

```sh
swift test --filter VideoEditingStateTests
```

Expected: compile failure for missing `setTrimRange` and `setSpeed`.

- [ ] **Step 7: Implement trim and speed mutation**

Add to `VideoEditingState`:

```swift
public mutating func setTrimRange(start: TimeInterval, end: TimeInterval) throws {
    let quantizedStart = Self.quantized(start)
    let quantizedEnd = Self.quantized(end)
    guard quantizedStart >= 0,
          quantizedEnd <= sourceDuration,
          quantizedEnd - quantizedStart >= Self.minimumSelectedDuration else {
        throw VideoEditingStateError.invalidTrimRange
    }

    startTime = quantizedStart
    endTime = quantizedEnd
}

public mutating func setSpeed(_ speed: VideoPlaybackSpeed) throws {
    guard Self.presetsContain(speed) else {
        throw VideoEditingStateError.invalidTrimRange
    }
    self.speed = speed
}

private static func presetsContain(_ speed: VideoPlaybackSpeed) -> Bool {
    VideoPlaybackSpeed.presets.contains(speed)
}
```

- [ ] **Step 8: Run tests and commit**

Run:

```sh
swift test --filter VideoEditingStateTests
```

Expected: PASS.

Commit:

```sh
git add Sources/FrameCore/VideoEditingState.swift Tests/FrameCoreTests/VideoEditingStateTests.swift
git commit -m "feat: add video editing state model"
```

## Task 2: MP4 Export Service

**Files:**
- Create: `Sources/FrameApp/VideoEditingExporter.swift`
- Create: `Tests/FrameAppTests/VideoEditingExporterTests.swift`

- [ ] **Step 1: Write failing exporter tests**

Create `Tests/FrameAppTests/VideoEditingExporterTests.swift`:

```swift
import AVFoundation
import XCTest
@testable import FrameApp
@testable import FrameCore

final class VideoEditingExporterTests: XCTestCase {
    func testExporterRejectsGIFInput() async throws {
        let exporter = VideoEditingExporter()
        let gifURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.gif")
        try Data([1, 2, 3]).write(to: gifURL)
        defer { try? FileManager.default.removeItem(at: gifURL) }
        var state = try VideoEditingState(sourceDuration: 2)
        try state.setTrimRange(start: 0, end: 1)

        do {
            _ = try await exporter.export(sourceURL: gifURL, format: .gif, editingState: state)
            XCTFail("Expected GIF export to fail")
        } catch let error as VideoEditingExportError {
            XCTAssertEqual(error, .unsupportedFormat)
        }
    }

    func testExporterTrimsAndScalesMP4Duration() async throws {
        let sourceURL = try Self.makeTestMP4(duration: 2)
        defer { try? FileManager.default.removeItem(at: sourceURL.deletingLastPathComponent()) }
        var state = try VideoEditingState(sourceDuration: 2)
        try state.setTrimRange(start: 0.5, end: 1.5)
        try state.setSpeed(.double)

        let exported = try await VideoEditingExporter().export(
            sourceURL: sourceURL,
            format: .mp4,
            editingState: state
        )
        defer { try? FileManager.default.removeItem(at: exported) }

        let asset = AVURLAsset(url: exported)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 0.5, accuracy: 0.18)
    }

    private static func makeTestMP4(duration: TimeInterval) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameVideoEditingExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("source.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let size = CGSize(width: 16, height: 16)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frameIndex in 0..<Int(duration * 10) {
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, Int(size.width), Int(size.height), kCVPixelFormatType_32BGRA, nil, &buffer)
            guard let buffer else { throw NSError(domain: "VideoEditingExporterTests", code: 1) }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let base = CVPixelBufferGetBaseAddress(buffer) {
                memset(base, frameIndex % 255, CVPixelBufferGetDataSize(buffer))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            while !input.isReadyForMoreMediaData {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frameIndex), timescale: 10)))
        }
        input.markAsFinished()
        let expectation = XCTestExpectation(description: "finish writing")
        writer.finishWriting { expectation.fulfill() }
        XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(writer.status, .completed)
        return url
    }
}
```

- [ ] **Step 2: Run tests and verify they fail because exporter is missing**

Run:

```sh
swift test --filter VideoEditingExporterTests
```

Expected: compile failure for missing `VideoEditingExporter` and `VideoEditingExportError`.

- [ ] **Step 3: Implement exporter**

Create `Sources/FrameApp/VideoEditingExporter.swift`:

```swift
import AVFoundation
import Foundation
import FrameCore

enum VideoEditingExportError: Equatable, Error {
    case unsupportedFormat
    case invalidRange
    case exportFailed(String)
}

final class VideoEditingExporter {
    private let fileManager: FileManager
    private let temporaryDirectory: () -> URL

    init(
        fileManager: FileManager = .default,
        temporaryDirectory: @escaping () -> URL = {
            FileManager.default.temporaryDirectory
                .appendingPathComponent("FrameVideoEdits", isDirectory: true)
        }
    ) {
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
    }

    func export(
        sourceURL: URL,
        format: RecordingFormat,
        editingState: VideoEditingState
    ) async throws -> URL {
        guard format == .mp4 else {
            throw VideoEditingExportError.unsupportedFormat
        }
        guard editingState.selectedDuration >= VideoEditingState.minimumSelectedDuration else {
            throw VideoEditingExportError.invalidRange
        }

        let directory = temporaryDirectory()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let outputURL = directory.appendingPathComponent("Frame Edited-\(UUID().uuidString).mp4")
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw VideoEditingExportError.exportFailed("MP4 没有可编辑的视频轨道。")
        }

        let sourceRange = CMTimeRange(
            start: CMTime(seconds: editingState.startTime, preferredTimescale: 600),
            duration: CMTime(seconds: editingState.selectedDuration, preferredTimescale: 600)
        )
        try compositionVideoTrack.insertTimeRange(sourceRange, of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let scaledDuration = CMTime(seconds: editingState.outputDuration, preferredTimescale: 600)
        compositionVideoTrack.scaleTimeRange(
            CMTimeRange(start: .zero, duration: sourceRange.duration),
            toDuration: scaledDuration
        )

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoEditingExportError.exportFailed("无法创建 MP4 导出会话。")
        }
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        await exportSession.export()

        guard exportSession.status == .completed else {
            throw VideoEditingExportError.exportFailed(exportSession.error?.localizedDescription ?? "MP4 导出失败。")
        }
        return outputURL
    }
}
```

- [ ] **Step 4: Run exporter tests and fix only compile/runtime issues**

Run:

```sh
swift test --filter VideoEditingExporterTests
```

Expected: PASS. If the local SDK does not support `await exportSession.export()`, use the callback-based `exportAsynchronously` wrapper shown below without changing the public exporter API:

```swift
private func runExport(_ exportSession: AVAssetExportSession) async {
    await withCheckedContinuation { continuation in
        exportSession.exportAsynchronously {
            continuation.resume()
        }
    }
}
```

- [ ] **Step 5: Commit**

```sh
git add Sources/FrameApp/VideoEditingExporter.swift Tests/FrameAppTests/VideoEditingExporterTests.swift
git commit -m "feat: add video editing exporter"
```

## Task 3: Quick Access MP4 Edit Entry

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Modify: `Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift`

- [ ] **Step 1: Replace old MP4 disabled-edit test with MP4 enabled / GIF disabled tests**

In `RecordingQuickAccessPanelControllerTests`, replace `testRecordingQuickAccessExposesDownloadCopyPreviewAndDisabledEdit` with:

```swift
func testMP4RecordingQuickAccessExposesEnabledEdit() throws {
    _ = NSApplication.shared
    let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
    let recording = CapturedRecording(
        id: UUID(),
        fileURL: URL(fileURLWithPath: "/tmp/test.mp4"),
        format: .mp4,
        rect: CGRect(x: 0, y: 0, width: 1282, height: 504),
        pixelSize: CGSize(width: 1282, height: 504),
        byteSize: 10,
        duration: 24
    )
    let controller = QuickAccessPanelController()
    retainedPreviewControllers.append(controller)
    var editCallCount = 0

    controller.show(
        for: recording,
        preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
        strings: AppStrings(language: .en),
        download: { true },
        copy: { true },
        preview: { true },
        edit: {
            editCallCount += 1
            return true
        },
        close: {}
    )

    let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
    defer { panel.close() }
    let contentView = try XCTUnwrap(panel.contentView)
    contentView.layoutSubtreeIfNeeded()
    let editButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Edit"))
    XCTAssertTrue(editButton.isEnabled)
    editButton.performClick(nil)
    XCTAssertEqual(editCallCount, 1)
}

func testGIFRecordingQuickAccessKeepsEditDisabled() throws {
    _ = NSApplication.shared
    let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
    let recording = CapturedRecording(
        id: UUID(),
        fileURL: URL(fileURLWithPath: "/tmp/test.gif"),
        format: .gif,
        rect: CGRect(x: 0, y: 0, width: 320, height: 240),
        pixelSize: CGSize(width: 320, height: 240),
        byteSize: 10,
        duration: 2
    )
    let controller = QuickAccessPanelController()
    retainedPreviewControllers.append(controller)
    var editCallCount = 0

    controller.show(
        for: recording,
        preferredAnchor: CGRect(x: 0, y: 0, width: 100, height: 100),
        strings: AppStrings(language: .en),
        download: { true },
        copy: { true },
        preview: { true },
        edit: {
            editCallCount += 1
            return true
        },
        close: {}
    )

    let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
    defer { panel.close() }
    let contentView = try XCTUnwrap(panel.contentView)
    contentView.layoutSubtreeIfNeeded()
    let editButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Edit"))
    XCTAssertFalse(editButton.isEnabled)
    editButton.performClick(nil)
    XCTAssertEqual(editCallCount, 0)
}
```

- [ ] **Step 2: Run tests and verify signature/edit failures**

Run:

```sh
swift test --filter RecordingQuickAccessPanelControllerTests/testMP4RecordingQuickAccessExposesEnabledEdit
```

Expected: compile failure because `show(... edit:)` is missing.

- [ ] **Step 3: Add edit closure to Quick Access recording items**

Update `QuickAccessPanelController.show(for recording:)` signature to include:

```swift
edit: @escaping () -> Bool,
```

Store it in `QuickAccessPreviewItem`:

```swift
let editRecording: (() -> Bool)?
```

Pass `editRecording: edit` for recording items and `editRecording: nil` for screenshot items.

- [ ] **Step 4: Enable MP4 edit button and keep GIF disabled**

In `makeRecordingContentView`, replace the disabled edit action with:

```swift
let editButton = makeIconButton(
    title: strings.videoQuickAccessEdit,
    symbolName: "slider.horizontal.3",
    action: #selector(editRecordingButtonClicked),
    style: .toolbar
)
if recording.format != .mp4 {
    editButton.isEnabled = false
    editButton.contentTintColor = .disabledControlTextColor
    editButton.toolTip = strings.videoEditingMP4Only
}
stackView.addArrangedSubview(editButton)
```

Replace `disabledRecordingEditButtonClicked` with:

```swift
@objc private func editRecordingButtonClicked(_ sender: NSButton) {
    guard let item = previewItem(for: sender.window) else {
        return
    }

    _ = item.editRecording?()
}
```

- [ ] **Step 5: Add localized disabled-copy string**

Add to `AppStrings`:

```swift
var videoEditingMP4Only: String {
    switch resolvedLanguage {
    case .simplifiedChinese: "此版本仅支持编辑 MP4"
    case .en: "MP4 editing only in this version"
    }
}
```

Add assertions in `AppStringsTests`.

- [ ] **Step 6: Run Quick Access and AppStrings tests**

Run:

```sh
swift test --filter 'RecordingQuickAccessPanelControllerTests/testMP4RecordingQuickAccessExposesEnabledEdit|RecordingQuickAccessPanelControllerTests/testGIFRecordingQuickAccessKeepsEditDisabled|AppStringsTests'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```sh
git add Sources/FrameApp/QuickAccessPanelController.swift Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/AppStringsTests.swift
git commit -m "feat: enable mp4 recording edit entry"
```

## Task 4: Video Preview Editor Bar And State

**Files:**
- Create: `Sources/FrameApp/VideoEditorBarView.swift`
- Modify: `Sources/FrameApp/VideoPreviewWindowController.swift`
- Modify: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`

- [ ] **Step 1: Update preview tests for MP4 enabled and GIF disabled editing**

Replace `testPreviewWindowKeepsEditControlsDisabled` with:

```swift
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
        saveCurrent: { _, _ in true }
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
        saveCurrent: { _, _ in true }
    )

    XCTAssertFalse(controller.isEditingEnabledForTesting(recordingID: recording.id))
    let window = try XCTUnwrap(controller.windowForTesting(recordingID: recording.id))
    let contentView = try XCTUnwrap(window.contentView)
    XCTAssertNil(findSubview(of: VideoEditorBarView.self, in: contentView))
}
```

- [ ] **Step 2: Run tests and verify compile failures for new API/view**

Run:

```sh
swift test --filter VideoPreviewWindowControllerTests/testMP4PreviewWindowShowsEditorBarByDefault
```

Expected: compile failures for `saveCurrent`, `editingStateForTesting`, and `VideoEditorBarView`.

- [ ] **Step 3: Create minimal VideoEditorBarView**

Create `Sources/FrameApp/VideoEditorBarView.swift`:

```swift
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
        endField.isEditable = false
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
```

- [ ] **Step 4: Wire editor bar into VideoPreviewWindowController**

Update `show` signature:

```swift
func show(
    recording: CapturedRecording,
    strings: AppStrings,
    copy: @escaping () -> Bool,
    download: @escaping () -> Bool,
    saveCurrent: @escaping (CapturedRecording, VideoEditingState) -> Bool,
    focusEditor: Bool = false
)
```

For MP4:

```swift
let editingState = recording.format == .mp4 ? try? VideoEditingState(sourceDuration: recording.duration) : nil
let editorBar = editingState.map(VideoEditorBarView.init(state:))
```

Add `editorBar` below `mediaView` and store `editingState` in `VideoPreviewItem`.

Expose:

```swift
func editingStateForTesting(recordingID: UUID) -> VideoEditingState? {
    items[recordingID]?.editingState
}
```

- [ ] **Step 5: Run preview tests**

Run:

```sh
swift test --filter VideoPreviewWindowControllerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```sh
git add Sources/FrameApp/VideoEditorBarView.swift Sources/FrameApp/VideoPreviewWindowController.swift Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift
git commit -m "feat: show mp4 video editor controls"
```

## Task 5: Playback Range Coordination

**Files:**
- Modify: `Sources/FrameApp/VideoPreviewWindowController.swift`
- Modify: `Sources/FrameApp/VideoEditorBarView.swift`
- Modify: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`

- [ ] **Step 1: Add failing tests for state updates and clipped playback state**

Add tests:

```swift
func testUpdatingMP4TrimStateMarksWindowDirty() throws {
    let recording = makeMP4Recording(duration: 24)
    let controller = VideoPreviewWindowController()
    controller.show(recording: recording, strings: AppStrings(language: .en), copy: { true }, download: { true }, saveCurrent: { _, _ in true })

    try controller.setTrimRangeForTesting(recordingID: recording.id, start: 3.274, end: 18.636)

    let state = try XCTUnwrap(controller.editingStateForTesting(recordingID: recording.id))
    XCTAssertEqual(state.startTime, 3.27, accuracy: 0.0001)
    XCTAssertEqual(state.endTime, 18.64, accuracy: 0.0001)
    XCTAssertTrue(controller.hasUnsavedEditsForTesting(recordingID: recording.id))
}

func testPlaybackRangeUsesTrimStartAndEnd() throws {
    let recording = makeMP4Recording(duration: 24)
    let controller = VideoPreviewWindowController()
    controller.show(recording: recording, strings: AppStrings(language: .en), copy: { true }, download: { true }, saveCurrent: { _, _ in true })
    try controller.setTrimRangeForTesting(recordingID: recording.id, start: 3, end: 8)

    let range = try XCTUnwrap(controller.playbackRangeForTesting(recordingID: recording.id))
    XCTAssertEqual(range.start.seconds, 3, accuracy: 0.001)
    XCTAssertEqual(range.end.seconds, 8, accuracy: 0.001)
}
```

Add helper:

```swift
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
```

- [ ] **Step 2: Run tests and verify test hooks fail**

Run:

```sh
swift test --filter VideoPreviewWindowControllerTests/testUpdatingMP4TrimStateMarksWindowDirty
```

Expected: compile failure for missing test hooks.

- [ ] **Step 3: Implement state update hooks and playback range model**

Store `editingState` as mutable in `VideoPreviewItem`. Add:

```swift
func setTrimRangeForTesting(recordingID: UUID, start: TimeInterval, end: TimeInterval) throws {
    guard let item = items[recordingID], var state = item.editingState else {
        return
    }
    try state.setTrimRange(start: start, end: end)
    item.editingState = state
    item.editorBar?.updateState(state)
}

func hasUnsavedEditsForTesting(recordingID: UUID) -> Bool {
    items[recordingID]?.editingState?.isDirty ?? false
}

func playbackRangeForTesting(recordingID: UUID) -> CMTimeRange? {
    guard let state = items[recordingID]?.editingState else {
        return nil
    }
    return CMTimeRange(
        start: CMTime(seconds: state.startTime, preferredTimescale: 600),
        end: CMTime(seconds: state.endTime, preferredTimescale: 600)
    )
}
```

- [ ] **Step 4: Add real player end observer**

In the MP4 path, keep `AVPlayer` in the item and add a periodic time observer:

```swift
let observer = player.addPeriodicTimeObserver(
    forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
    queue: .main
) { [weak self, weak player] time in
    guard let self, let player else { return }
    self.stopPlaybackIfNeeded(player: player, recordingID: recording.id, time: time)
}
```

Implement:

```swift
private func stopPlaybackIfNeeded(player: AVPlayer, recordingID: UUID, time: CMTime) {
    guard let state = items[recordingID]?.editingState,
          time.seconds >= state.endTime else {
        return
    }
    player.pause()
    player.seek(to: CMTime(seconds: state.endTime, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
}
```

When play is requested after reaching end, seek to start before playing. If controlling `AVPlayerView`'s built-in play button is too brittle for this iteration, keep the observer and testable range state; document manual smoke for built-in control behavior.

- [ ] **Step 5: Run preview tests and commit**

Run:

```sh
swift test --filter VideoPreviewWindowControllerTests
```

Expected: PASS.

Commit:

```sh
git add Sources/FrameApp/VideoPreviewWindowController.swift Sources/FrameApp/VideoEditorBarView.swift Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift
git commit -m "feat: constrain mp4 preview playback"
```

## Task 6: Save, Copy, Download, And Dirty Close Routing

**Files:**
- Modify: `Sources/FrameApp/VideoPreviewWindowController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift`
- Modify: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`

- [ ] **Step 1: Add preview controller tests for Save Current menu and close choices**

Add:

```swift
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
```

- [ ] **Step 2: Run and verify missing save choice API**

Run:

```sh
swift test --filter VideoPreviewWindowControllerTests/testSaveCurrentMenuRoutesReplaceAndSaveAsNew
```

Expected: compile failure for `VideoPreviewSaveChoice` and test hooks.

- [ ] **Step 3: Implement save choice API in preview controller**

Add:

```swift
enum VideoPreviewSaveChoice: Equatable {
    case replaceCurrent
    case saveAsNew
}
```

Change `saveCurrent` closure to:

```swift
(CapturedRecording, VideoEditingState, VideoPreviewSaveChoice) -> Bool
```

Add a Save Current button with menu items `strings.workspaceReplaceCurrent` and `strings.workspaceSaveAsNew`. Call the closure with the selected choice only when `editingState.isDirty`.

- [ ] **Step 4: Wire AppDelegate product actions**

Add `edit` closure to `showVideoQuickAccess`:

```swift
edit: { [weak self] in
    self?.openVideoPreview(recording, focusEditor: true) ?? false
},
```

Update `openVideoPreview`:

```swift
private func openVideoPreview(_ recording: CapturedRecording, focusEditor: Bool = false) -> Bool {
    videoPreviewWindowController.show(
        recording: recording,
        strings: strings,
        copy: { [weak self] in self?.copyRecordingToClipboard(recording) ?? false },
        download: { [weak self] in self?.downloadRecording(recording) ?? false },
        saveCurrent: { [weak self] recording, state, choice in
            self?.saveEditedRecording(recording, editingState: state, choice: choice) ?? false
        },
        focusEditor: focusEditor
    )
    return true
}
```

Add this temporary implementation that compiles before exporter integration:

```swift
private func saveEditedRecording(
    _ recording: CapturedRecording,
    editingState: VideoEditingState,
    choice: VideoPreviewSaveChoice
) -> Bool {
    showQuickAccessFailedAlert(
        title: strings.saveFailedTitle,
        error: VideoEditingExportError.exportFailed("录屏编辑导出尚未连接。")
    )
    return false
}
```

Task 7 replaces this temporary implementation with real exporter routing.

- [ ] **Step 5: Run focused tests**

Run:

```sh
swift test --filter 'VideoPreviewWindowControllerTests/testSaveCurrentMenuRoutesReplaceAndSaveAsNew|RecordingQuickAccessPanelControllerTests/testMP4RecordingQuickAccessExposesEnabledEdit'
```

Expected: PASS.

- [ ] **Step 6: Commit**

```sh
git add Sources/FrameApp/VideoPreviewWindowController.swift Sources/FrameApp/AppDelegate.swift Tests/FrameAppTests/VideoPreviewWindowControllerTests.swift Tests/FrameAppTests/AppDelegateRecordingTests.swift
git commit -m "feat: route mp4 edit save actions"
```

## Task 7: Export Integration And Quick Access Refresh

**Files:**
- Modify: `Sources/FrameApp/AppDelegate.swift`
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Modify: `Tests/FrameAppTests/AppDelegateRecordingTests.swift`
- Modify: `Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift`

- [ ] **Step 1: Add a protocol for exporter injection**

In `VideoEditingExporter.swift`, add:

```swift
protocol VideoEditingExporting {
    func export(sourceURL: URL, format: RecordingFormat, editingState: VideoEditingState) async throws -> URL
}

extension VideoEditingExporter: VideoEditingExporting {}
```

- [ ] **Step 2: Add AppDelegate tests with fake exporter**

Extend AppDelegate test setup with concrete fake exporter state:

```swift
func testSavingEditedRecordingAsNewShowsNewQuickAccessRecording() async throws {
    let appDelegate = AppDelegate.makeForTesting()
    let exportedURL = try makeTemporaryMP4File()
    let exporter = FakeVideoEditingExporter(resultURL: exportedURL)
    appDelegate.setVideoEditingExporterForTesting(exporter)
    let recording = makeRecording(id: UUID(), fileURL: try makeTemporaryMP4File())
    appDelegate.showVideoQuickAccessForTesting(recording)
    let state = try VideoEditingState(sourceDuration: 10)

    XCTAssertTrue(await appDelegate.saveEditedRecordingForTesting(recording, editingState: state, choice: .saveAsNew))

    XCTAssertEqual(exporter.requests.count, 1)
    XCTAssertEqual(appDelegate.quickAccessRecordingCountForTesting(), 2)
}

func testReplacingEditedRecordingUpdatesQuickAccessPreview() async throws {
    let appDelegate = AppDelegate.makeForTesting()
    let exportedURL = try makeTemporaryMP4File()
    let exporter = FakeVideoEditingExporter(resultURL: exportedURL)
    appDelegate.setVideoEditingExporterForTesting(exporter)
    let recordingID = UUID()
    let recording = makeRecording(id: recordingID, fileURL: try makeTemporaryMP4File())
    appDelegate.showVideoQuickAccessForTesting(recording)
    var state = try VideoEditingState(sourceDuration: 10)
    try state.setTrimRange(start: 1, end: 5)

    XCTAssertTrue(await appDelegate.saveEditedRecordingForTesting(recording, editingState: state, choice: .replaceCurrent))

    XCTAssertEqual(exporter.requests.count, 1)
    XCTAssertEqual(appDelegate.quickAccessRecordingCountForTesting(), 1)
    XCTAssertEqual(appDelegate.quickAccessRecordingForTesting(id: recordingID)?.duration, 4)
}
```

Add this fake in `AppDelegateRecordingTests`:

```swift
private final class FakeVideoEditingExporter: VideoEditingExporting {
    struct Request: Equatable {
        let sourceURL: URL
        let format: RecordingFormat
        let editingState: VideoEditingState
    }

    let resultURL: URL
    private(set) var requests: [Request] = []

    init(resultURL: URL) {
        self.resultURL = resultURL
    }

    func export(sourceURL: URL, format: RecordingFormat, editingState: VideoEditingState) async throws -> URL {
        requests.append(Request(sourceURL: sourceURL, format: format, editingState: editingState))
        return resultURL
    }
}
```

If `AppDelegate.makeForTesting()` does not exist with these dependencies yet, add an initializer or testing factory that accepts `VideoEditingExporting`, `QuickAccessPanelController`, `VideoPreviewWindowController`, `CaptureHistoryStore`, `RecordingFileWriter`, and `ClipboardWriter` fakes. Do not use global singletons in these tests.

- [ ] **Step 3: Run tests and verify failure**

Run:

```sh
swift test --filter AppDelegateRecordingTests/testSavingEditedRecordingAsNewShowsNewQuickAccessRecording
```

Expected: failure for missing injection/test hooks.

- [ ] **Step 4: Implement AppDelegate export routing**

Add AppDelegate dependency:

```swift
private let videoEditingExporter: VideoEditingExporting
```

In `saveEditedRecording`, start a `Task { @MainActor }`, export edited MP4, create a `CapturedRecording` with updated byte size and duration `editingState.outputDuration`, then:

- `.replaceCurrent`: update active preview for same recording id and update video preview controller item.
- `.saveAsNew`: store in capture history, show a new Quick Access card.
- `Download`: call exporter then `recordingFileWriter.copyRecording`.
- `Copy`: call exporter then `clipboardWriter.write(fileURL:)`.

Keep source files unchanged until export succeeds.

- [ ] **Step 5: Run AppDelegate focused tests**

Run:

```sh
swift test --filter AppDelegateRecordingTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```sh
git add Sources/FrameApp/AppDelegate.swift Sources/FrameApp/QuickAccessPanelController.swift Tests/FrameAppTests/AppDelegateRecordingTests.swift Tests/FrameAppTests/RecordingQuickAccessPanelControllerTests.swift Sources/FrameApp/VideoEditingExporter.swift
git commit -m "feat: integrate edited recording outputs"
```

## Task 8: Product Documentation

**Files:**
- Modify: `README.md`
- Modify: `README_ZH.md`
- Modify: `docs/architecture.md`
- Modify: `DESIGN.md`

- [ ] **Step 1: Update README English recording output copy**

Change recording output wording from "Edit is visible but pending" to:

```markdown
- Recording output: copy the recorded file, download it to the configured save
  folder, or open the video preview. MP4 recordings can be trimmed to custom
  start/end times and exported at preset speeds up to 8x from the same preview
  window. GIF recordings remain preview/copy/download only.
```

- [ ] **Step 2: Update README Chinese copy**

Use equivalent Chinese:

```markdown
- 录屏输出：复制录屏文件，下载到当前保存目录，或打开视频预览。MP4
  录屏可以在同一个预览窗口中自定义开始/结束时间，并用最高 8x 的预设倍速导出；GIF
  录屏仍只支持预览、复制和下载。
```

- [ ] **Step 3: Update architecture and design docs**

In `docs/architecture.md`, update VideoPreview and Quick Access bullets to state MP4 editing is enabled and GIF editing disabled.

In `DESIGN.md`, update Quick Access / video preview guidance:

```markdown
- Recording cards use the centered play affordance for Preview and expose
  Download, Copy, Edit, and Close as hover actions. Edit is enabled for MP4 and
  disabled for GIF. Preview and Edit open the same video preview window; MP4
  windows hide native AVPlayer playback controls and show Frame's grouped bottom
  control bar with a mini timeline for progress/seek, trim handles, and read-only
  start/end time labels, plus a minimal bottom row for play/pause, time summary,
  and speed dropdown.
```

- [ ] **Step 4: Run docs grep sanity**

Run:

```sh
rg -n "Edit is visible but pending|disabled Edit|editing controls remain disabled" README.md README_ZH.md docs/architecture.md DESIGN.md
```

Expected: no stale pending-edit wording for MP4.

- [ ] **Step 5: Commit**

```sh
git add README.md README_ZH.md docs/architecture.md DESIGN.md
git commit -m "docs: document recording video editing"
```

## Task 9: Full Verification

**Files:**
- No source edits unless verification exposes defects.

- [ ] **Step 1: Run full tests**

```sh
swift test
```

Expected: PASS.

- [ ] **Step 2: Run build**

```sh
swift build
```

Expected: PASS.

- [ ] **Step 3: Run packaging**

```sh
scripts/package-app.sh
```

Expected: PASS and `.build/app/Frame.app` created.

- [ ] **Step 4: Manual GUI handoff note**

Because this changes user-facing GUI behavior, final handoff must ask whether to replace the local test app unless replacement has already been completed in the same turn. If replacing, use the stable signing flow from `AGENTS.md`.

## Self-Review Notes

- Spec coverage: MP4-only editing, GIF disabled editing, single preview window, persistent MP4 editor bar, `0.01s` trim, fixed speed presets, clipped playback, stop at end, Save Current choices, direct Download, Copy materialization, dirty close, exporter, docs, and verification are all mapped to tasks.
- Ambiguity scan: no task leaves unresolved behavior as an implementation substitute. Task 7 now names concrete fake exporter state and required test hooks.
- Type consistency: `VideoEditingState`, `VideoPlaybackSpeed`, `VideoEditingExporter`, `VideoEditingExporting`, `VideoPreviewSaveChoice`, and `VideoEditorBarView` names are used consistently across tasks.
