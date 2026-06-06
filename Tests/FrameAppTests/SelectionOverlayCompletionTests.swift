import AppKit
import XCTest
@testable import FrameApp
@testable import FrameCore

final class SelectionOverlayCompletionTests: XCTestCase {
    func testCaptureCompletionExposesSelection() {
        let selection = SelectionCapture(
            rect: CGRect(x: 10, y: 20, width: 120, height: 80),
            kind: .region
        )

        let completion = SelectionOverlayCompletion.capture(selection)

        XCTAssertEqual(completion.selection?.rect, selection.rect)
        XCTAssertEqual(completion.selection?.kind, selection.kind)
    }

    func testRecognizeTextCompletionExposesSelection() {
        let selection = SelectionCapture(
            rect: CGRect(x: 10, y: 20, width: 120, height: 80),
            kind: .region
        )

        let completion = SelectionOverlayCompletion.recognizeText(selection)

        XCTAssertEqual(completion.selection?.rect, selection.rect)
        XCTAssertEqual(completion.selection?.kind, selection.kind)
    }

    func testFullScreenCompletionDoesNotRequireSelection() {
        let completion = SelectionOverlayCompletion.fullScreen

        XCTAssertNil(completion.selection)
    }

    func testStartRecordingCompletionExposesSelectionAndOptions() {
        let selection = SelectionCapture(
            rect: CGRect(x: 1, y: 2, width: 300, height: 200),
            kind: .region
        )
        let options = RecordingOptions(
            format: .gif,
            showsCursor: false,
            showsKeyboardHints: true,
            audioSource: .none
        )

        let completion = SelectionOverlayCompletion.startRecording(selection, options)

        XCTAssertEqual(completion.selection?.rect, selection.rect)
        XCTAssertEqual(completion.recordingOptions, options)
    }

    @MainActor
    func testSelectionHUDExposesFullScreenAndDelayButtons() throws {
        let window = try makeOverlayWindowForTesting()

        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("全屏截图"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("延迟截图"))
    }

    @MainActor
    func testSelectionHUDUsesReadableIcons() throws {
        let window = try makeOverlayWindowForTesting()

        XCTAssertEqual(
            window.hudButtonImageDescriptionsForTesting(),
            ["crop", "display", "timer", "character.textbox", "record.circle"]
        )
    }

    @MainActor
    func testRecordingButtonSwitchesHUDIntoRecordingSetupMode() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: CGRect(
                x: screen.frame.minX + 20,
                y: screen.frame.minY + 20,
                width: 240,
                height: 160
            )
        )

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "录屏"))

        XCTAssertEqual(window.recordingHUDModeForTesting(), "setup")
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("开始录制"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("MP4"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("显示鼠标指针"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("显示键盘提示"))
    }

    @MainActor
    func testStartRecordingButtonInvokesRecordingCallbackWithoutCompletingOverlay() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        var startedSelection: SelectionCapture?
        var startedOptions: RecordingOptions?
        var completion: SelectionOverlayCompletion?
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: CGRect(
                x: screen.frame.minX + 20,
                y: screen.frame.minY + 20,
                width: 240,
                height: 160
            ),
            onComplete: { completion = $0 },
            onStartRecording: { selection, options in
                startedSelection = selection
                startedOptions = options
            }
        )

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "录屏"))
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "开始录制"))

        XCTAssertEqual(startedSelection?.rect, window.activeSelectionForTesting()?.rect)
        XCTAssertEqual(startedOptions, RecordingOptions.defaults)
        XCTAssertNil(completion)
    }

    @MainActor
    func testActiveRecordingHandlersAreInvokedFromHUD() throws {
        let window = try makeOverlayWindowForTesting()
        var didPause = false
        var didResume = false
        var didStop = false

        window.setActiveRecordingHandlers(
            pause: { didPause = true },
            resume: { didResume = true },
            stop: { didStop = true }
        )
        window.enterActiveRecordingModeForTesting(elapsed: 3, isPaused: false)

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "暂停"))
        XCTAssertTrue(didPause)
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "继续"))
        XCTAssertTrue(didResume)
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "停止录制"))
        XCTAssertTrue(didStop)
    }

    @MainActor
    func testActiveRecordingHUDAllowsDesktopInteractionOutsideHUD() throws {
        let window = try makeOverlayWindowForTesting()

        window.enterActiveRecordingModeForTesting(elapsed: 3, isPaused: false)

        let hudFrame = window.recordingHUDFrameForTesting()
        XCTAssertTrue(window.hitTestIsPassthroughForTesting(localPoint: CGPoint(x: 4, y: 4)))
        XCTAssertFalse(window.hitTestIsPassthroughForTesting(localPoint: hudFrame.center))
    }

    @MainActor
    func testRecordingHUDShowsElapsedTimePauseAndStopWhileActive() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: CGRect(
                x: screen.frame.minX + 20,
                y: screen.frame.minY + 20,
                width: 240,
                height: 160
            )
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

    @MainActor
    func testHUDTooltipTextHasSymmetricHorizontalPadding() throws {
        let window = try makeOverlayWindowForTesting()
        let tooltipLayout = window.tooltipLayoutForTesting(text: "全屏截图")

        let leftPadding = tooltipLayout.textFrame.minX
        let rightPadding = tooltipLayout.size.width - tooltipLayout.textFrame.maxX

        XCTAssertEqual(leftPadding, rightPadding, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(leftPadding, 9)
    }

    @MainActor
    func testFullScreenHUDButtonCompletesWithoutSelection() throws {
        let completionBox = CompletionBox()
        let window = try makeOverlayWindowForTesting(initialGlobalRect: nil) { completion in
            completionBox.completion = completion
        }

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "全屏截图"))

        guard case .fullScreen = completionBox.completion else {
            return XCTFail("Expected full-screen completion")
        }
    }

    @MainActor
    func testDelayCaptureCompletesWithInitialSelectionAfterCountdown() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let selectionRect = CGRect(
            x: screen.frame.minX + 24,
            y: screen.frame.minY + 32,
            width: 120,
            height: 90
        )
        let completionBox = CompletionBox()
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: selectionRect,
            delayCountdownNanoseconds: 0
        ) { completion in
            completionBox.completion = completion
        }

        XCTAssertEqual(window.activeSelectionForTesting()?.rect, selectionRect)
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "延迟截图"))
        XCTAssertFalse(window.isDelayCountdownActiveForTesting())

        guard case let .capture(selection) = completionBox.completion else {
            return XCTFail("Expected delayed capture completion")
        }
        XCTAssertEqual(selection.rect, selectionRect)
        XCTAssertEqual(selection.kind, .region)
    }

    @MainActor
    func testDelayCountdownAppearsCenteredAndProminentInsideSelection() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let selectionRect = CGRect(
            x: screen.frame.minX + 80,
            y: screen.frame.minY + 90,
            width: 240,
            height: 180
        )
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: selectionRect,
            delayCountdownNanoseconds: 1_000_000_000
        )

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "延迟截图"))

        let countdownFrame = try XCTUnwrap(window.countdownFrameForTesting())
        let activeSelection = try XCTUnwrap(window.activeSelectionForTesting())
        XCTAssertEqual(countdownFrame.midX, activeSelection.rect.midX, accuracy: 1)
        XCTAssertEqual(countdownFrame.midY, activeSelection.rect.midY, accuracy: 1)
        XCTAssertGreaterThanOrEqual(countdownFrame.width, 72)
        XCTAssertGreaterThanOrEqual(countdownFrame.height, 58)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(window.countdownFontSizeForTesting()), 34)

        let textFrame = try XCTUnwrap(window.countdownTextFrameForTesting())
        XCTAssertEqual(textFrame.midX, countdownFrame.width / 2, accuracy: 0.5)
        XCTAssertEqual(textFrame.midY, countdownFrame.height / 2, accuracy: 0.5)
    }

    @MainActor
    func testCancelSelectionRestoresCursor() {
        _ = NSApplication.shared
        var didResetCursor = false
        let controller = SelectionOverlayController(resetCursor: {
            didResetCursor = true
        })

        controller.startSelection { _ in }
        controller.cancelSelection()

        XCTAssertTrue(didResetCursor)
    }

    @MainActor
    private func makeOverlayWindowForTesting(
        initialGlobalRect: CGRect? = nil,
        delayCountdownNanoseconds: UInt64 = 5_000_000_000,
        onComplete: @escaping (SelectionOverlayCompletion?) -> Void = { _ in },
        onStartRecording: @escaping (SelectionCapture, RecordingOptions) -> Void = { _, _ in }
    ) throws -> SelectionOverlayWindow {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        return SelectionOverlayWindow(
            screen: screen,
            initialGlobalRect: initialGlobalRect,
            showsCenteredHUDWhenEmpty: true,
            placeholderText: "Drag to select an area",
            ocrActionText: "Recognize Text",
            delayCountdownNanoseconds: delayCountdownNanoseconds,
            onInteraction: {},
            onWindowSelectionRequested: { _, _ in nil },
            onStartRecording: onStartRecording,
            onComplete: onComplete
        )
    }
}

@MainActor
private final class CompletionBox {
    var completion: SelectionOverlayCompletion?
}
