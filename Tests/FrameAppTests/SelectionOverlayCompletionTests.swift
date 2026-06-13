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
    func testSelectionHUDHoverBackgroundsAreCompact() throws {
        let window = try makeOverlayWindowForTesting()
        let metrics = window.hudButtonLayoutMetricsForTesting()

        XCTAssertEqual(metrics.buttonWidth, 36)
        XCTAssertEqual(metrics.hoverDiameter, metrics.buttonWidth)
        XCTAssertEqual(metrics.screenshotModeWidth, 180)
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
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("显示鼠标提示"))
        XCTAssertFalse(window.hudButtonAccessibilityLabelsForTesting().contains("显示鼠标指针"))
        XCTAssertFalse(window.hudButtonAccessibilityLabelsForTesting().contains("显示点击提示"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("显示键盘提示"))
    }

    @MainActor
    func testRecordingKeyboardHintButtonKeepsVisibleIconWhenDisabled() throws {
        SettingsStore.setRecordingOptions(.defaults)
        defer {
            SettingsStore.setRecordingOptions(.defaults)
        }

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
        XCTAssertTrue(window.hudButtonImageDescriptionsForTesting().contains("keyboard.badge.eye"))
        XCTAssertEqual(window.hudButtonSlashStatesForTesting()["显示键盘提示"], false)
        XCTAssertEqual(window.hudButtonIconPointSizesForTesting()["显示键盘提示"], 14.5)
        XCTAssertEqual(window.hudButtonIconPointSizesForTesting()["显示鼠标提示"], 17)

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "显示键盘提示"))

        XCTAssertTrue(window.hudButtonImageDescriptionsForTesting().contains("keyboard.badge.eye"))
        XCTAssertEqual(window.hudButtonSlashStatesForTesting()["显示键盘提示"], true)
    }

    @MainActor
    func testRecordingSetupHUDIsCenteredInSelectionWithPrimaryStartAction() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let selectionRect = CGRect(
            x: screen.frame.minX + 80,
            y: screen.frame.minY + 120,
            width: 420,
            height: 260
        )
        let window = try makeOverlayWindowForTesting(initialGlobalRect: selectionRect)

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "录屏"))

        let hudFrame = window.recordingHUDFrameForTesting()
        XCTAssertEqual(hudFrame.midX, selectionRect.midX, accuracy: 1)
        XCTAssertEqual(hudFrame.midY, selectionRect.midY, accuracy: 1)
        XCTAssertTrue(window.startRecordingButtonIsPrimaryForTesting())
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
    func testRecordingSetupMouseHintButtonTogglesCursorAndClickHighlightOptionsTogether() throws {
        SettingsStore.setRecordingOptions(.defaults)
        defer {
            SettingsStore.setRecordingOptions(.defaults)
        }

        let screen = try XCTUnwrap(NSScreen.screens.first)
        var startedOptions: RecordingOptions?
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: CGRect(
                x: screen.frame.minX + 20,
                y: screen.frame.minY + 20,
                width: 240,
                height: 160
            ),
            onStartRecording: { _, options in
                startedOptions = options
            }
        )

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "录屏"))
        XCTAssertFalse(window.performHUDActionForTesting(accessibilityLabel: "显示鼠标指针"))
        XCTAssertFalse(window.performHUDActionForTesting(accessibilityLabel: "显示点击提示"))
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "显示鼠标提示"))
        XCTAssertEqual(window.hudButtonSlashStatesForTesting()["显示鼠标提示"], true)
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "开始录制"))

        XCTAssertEqual(startedOptions?.showsCursor, false)
        XCTAssertEqual(startedOptions?.showsMouseClickHighlights, false)
    }

    @MainActor
    func testRecordingFormatToggleShowsSelectedFormatAsVisibleText() throws {
        SettingsStore.setRecordingOptions(.defaults)
        defer {
            SettingsStore.setRecordingOptions(.defaults)
        }

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
        XCTAssertTrue(window.hudButtonVisibleTitlesForTesting().contains("MP4"))
        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "MP4"))

        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("GIF"))
        XCTAssertTrue(window.hudButtonVisibleTitlesForTesting().contains("GIF"))
    }

    @MainActor
    func testActiveRecordingHandlersAreInvokedFromHUD() throws {
        let window = try makeOverlayWindowForTesting()
        var didStop = false

        window.setActiveRecordingHandlers(
            pause: {},
            resume: {},
            stop: { didStop = true }
        )
        window.enterActiveRecordingModeForTesting(elapsed: 3, isPaused: false)

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
    func testRecordingHUDShowsElapsedTimeAndRecoveryActionsWhileActive() throws {
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
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("停止录制"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("重新开始"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("删除录制"))
        XCTAssertFalse(window.hudButtonAccessibilityLabelsForTesting().contains("暂停"))
        XCTAssertFalse(window.hudButtonAccessibilityLabelsForTesting().contains("继续"))
        XCTAssertEqual(window.recordingElapsedTextForTesting(), "00:24")
        XCTAssertLessThanOrEqual(window.recordingHUDFrameForTesting().width, 168)
    }

    @MainActor
    func testPausedRecordingHUDKeepsRecoveryActions() throws {
        let window = try makeOverlayWindowForTesting()

        window.enterActiveRecordingModeForTesting(elapsed: 24, isPaused: true)

        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("停止录制"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("重新开始"))
        XCTAssertTrue(window.hudButtonAccessibilityLabelsForTesting().contains("删除录制"))
        XCTAssertFalse(window.hudButtonAccessibilityLabelsForTesting().contains("继续"))
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
    func testHUDTooltipUsesContrastingTextForThemeBackground() throws {
        let window = try makeOverlayWindowForTesting()

        window.setTooltipThemeForTesting("lightContent")
        let darkTooltip = window.tooltipColorsForTesting()
        XCTAssertLessThan(darkTooltip.background.relativeLuminanceForTesting, 0.2)
        XCTAssertGreaterThan(darkTooltip.foreground.relativeLuminanceForTesting, 0.8)

        window.setTooltipThemeForTesting("darkContent")
        let lightTooltip = window.tooltipColorsForTesting()
        XCTAssertGreaterThan(lightTooltip.background.relativeLuminanceForTesting, 0.8)
        XCTAssertLessThan(lightTooltip.foreground.relativeLuminanceForTesting, 0.2)
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
    func testDelayCountdownAppearsBottomCenterAndProminentDuringPassiveCountdown() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let selectionRect = CGRect(
            x: screen.frame.maxX - 320,
            y: screen.frame.maxY - 300,
            width: 240,
            height: 180
        )
        let window = try makeOverlayWindowForTesting(
            initialGlobalRect: selectionRect,
            delayCountdownNanoseconds: 1_000_000_000
        )

        XCTAssertTrue(window.performHUDActionForTesting(accessibilityLabel: "延迟截图"))

        let countdownFrame = try XCTUnwrap(window.countdownFrameForTesting())
        let localScreenBounds = CGRect(origin: .zero, size: screen.frame.size)
        let desiredCountdownCenterY = localScreenBounds.minY + localScreenBounds.height * 0.04
        let expectedCountdownCenterY = min(
            max(desiredCountdownCenterY, localScreenBounds.minY + 8 + countdownFrame.height / 2),
            localScreenBounds.maxY - 8 - countdownFrame.height / 2
        )
        XCTAssertEqual(countdownFrame.midX, localScreenBounds.midX, accuracy: 1)
        XCTAssertEqual(countdownFrame.midY, expectedCountdownCenterY, accuracy: 1)
        XCTAssertLessThan(countdownFrame.midY, localScreenBounds.midY)
        XCTAssertGreaterThanOrEqual(countdownFrame.width, 72)
        XCTAssertGreaterThanOrEqual(countdownFrame.height, 58)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(window.countdownFontSizeForTesting()), 34)
        XCTAssertEqual(window.ignoresMouseEventsForTesting(), true)

        let colors = try XCTUnwrap(window.countdownColorsForTesting())
        XCTAssertGreaterThan(colors.background.relativeRedForTesting, 0.55)
        XCTAssertLessThan(colors.background.relativeRedForTesting, 0.75)
        XCTAssertLessThan(colors.background.relativeGreenForTesting, 0.12)
        XCTAssertLessThan(colors.background.relativeBlueForTesting, 0.12)
        XCTAssertLessThanOrEqual(colors.background.relativeAlphaForTesting, 0.62)
        XCTAssertEqual(window.countdownBorderAlphaForTesting(), 0, accuracy: 0.01)

        let textFrame = try XCTUnwrap(window.countdownTextFrameForTesting())
        XCTAssertEqual(textFrame.midX, countdownFrame.width / 2, accuracy: 0.5)
        XCTAssertEqual(textFrame.midY, countdownFrame.height / 2, accuracy: 0.5)
    }

    @MainActor
    func testRecordingSetupWithoutSelectionHidesZeroSizeHUD() throws {
        let window = try makeOverlayWindowForTesting(initialMode: .recordingSetup)

        XCTAssertFalse(window.hasSelection)
        XCTAssertTrue(window.placeholderIsVisibleForTesting())
        XCTAssertTrue(window.sizeHUDIsHiddenForTesting())
        XCTAssertEqual(window.sizeHUDTextForTesting(), nil)
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
        initialMode: SelectionOverlayInitialMode = .screenshot,
        delayCountdownNanoseconds: UInt64 = 5_000_000_000,
        onComplete: @escaping (SelectionOverlayCompletion?) -> Void = { _ in },
        onStartRecording: @escaping (SelectionCapture, RecordingOptions) -> Void = { _, _ in }
    ) throws -> SelectionOverlayWindow {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.screens.first)
        return SelectionOverlayWindow(
            screen: screen,
            initialGlobalRect: initialGlobalRect,
            initialMode: initialMode,
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

private extension NSColor {
    var relativeLuminanceForTesting: CGFloat {
        let color = usingColorSpace(.deviceRGB) ?? self
        return 0.2126 * color.redComponent
            + 0.7152 * color.greenComponent
            + 0.0722 * color.blueComponent
    }

    var relativeRedForTesting: CGFloat {
        (usingColorSpace(.deviceRGB) ?? self).redComponent
    }

    var relativeGreenForTesting: CGFloat {
        (usingColorSpace(.deviceRGB) ?? self).greenComponent
    }

    var relativeBlueForTesting: CGFloat {
        (usingColorSpace(.deviceRGB) ?? self).blueComponent
    }

    var relativeAlphaForTesting: CGFloat {
        (usingColorSpace(.deviceRGB) ?? self).alphaComponent
    }
}
