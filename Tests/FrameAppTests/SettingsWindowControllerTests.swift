import AppKit
import Carbon
import SwiftUI
import XCTest
import FrameCore
@testable import FrameApp

@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    func testSettingsWindowUsesSinglePagePreferenceListLayout() {
        XCTAssertEqual(SettingsWindowLayout.defaultSize.width, 620, accuracy: 0.5)
        XCTAssertEqual(SettingsWindowLayout.defaultSize.height, 600, accuracy: 0.5)
        XCTAssertEqual(SettingsWindowLayout.minimumSize.width, 560, accuracy: 0.5)
        XCTAssertEqual(SettingsWindowLayout.minimumSize.height, 460, accuracy: 0.5)
        XCTAssertFalse(SettingsWindowLayout.usesSidebar)
        XCTAssertEqual(SettingsListMetrics.maxContentWidth, 540, accuracy: 0.5)
        XCTAssertEqual(SettingsListMetrics.contentPadding, 30, accuracy: 0.5)
        XCTAssertEqual(SettingsListMetrics.sectionSpacing, 14, accuracy: 0.5)
        XCTAssertFalse(SettingsListMetrics.showsAboutAsSection)
        XCTAssertTrue(SettingsListMetrics.showsAboutFooter)
    }

    func testSettingsSinglePageKeepsSettingsDomainsInProductOrder() {
        XCTAssertEqual(SettingsSection.allCases, [
            .general,
            .screenshot,
            .recording,
            .textRecognition,
            .history,
            .permissions,
        ])

        let strings = AppStrings(language: .zhHans)
        XCTAssertEqual(SettingsSection.allCases.map { $0.title(strings: strings) }, [
            "通用",
            "截图",
            "录屏",
            "文字识别",
            "历史",
            "权限",
        ])
    }

    func testSettingsTypographyUsesSystemFontsAndReadableRows() {
        XCTAssertTrue(SettingsTypographyMetrics.usesSystemFont)
        XCTAssertTrue(SettingsTypographyMetrics.usesQuietSectionTitles)
        XCTAssertTrue(SettingsTypographyMetrics.usesMediumRowLabels)
        XCTAssertEqual(SettingsTypographyMetrics.sectionFontSize, 13, accuracy: 0.5)
        XCTAssertEqual(SettingsTypographyMetrics.rowFontSize, 14, accuracy: 0.5)
        XCTAssertEqual(SettingsTypographyMetrics.secondaryFontSize, 13, accuracy: 0.5)
        XCTAssertEqual(SettingsTypographyMetrics.footerFontSize, 11, accuracy: 0.5)
    }

    func testAboutFooterUsesEnglishPlaceholderText() {
        XCTAssertEqual(
            SettingsAboutFooterText.value(appName: "Frame", version: "0.1.0", build: "1"),
            "Frame · Version 0.1.0 · Build 1"
        )
    }

    func testSettingsRowsUseQuietGroupedListMetrics() {
        XCTAssertTrue(SettingsGroupMetrics.usesVisibleGroupBackground)
        XCTAssertEqual(SettingsGroupMetrics.cornerRadius, 10, accuracy: 0.5)
        XCTAssertEqual(SettingsGroupMetrics.rowMinHeight, 36, accuracy: 0.5)
        XCTAssertEqual(SettingsGroupMetrics.containerPadding, 10, accuracy: 0.5)
        XCTAssertEqual(SettingsGroupMetrics.labelColumnWidth, 120, accuracy: 0.5)
        XCTAssertEqual(SettingsGroupMetrics.horizontalPadding, 12, accuracy: 0.5)
        XCTAssertEqual(SettingsGroupMetrics.controlSpacing, 14, accuracy: 0.5)
        XCTAssertEqual(SettingsGroupMetrics.borderOpacity, 0.38, accuracy: 0.01)
        XCTAssertEqual(SettingsSectionGroupMetrics.titleSpacing, 6, accuracy: 0.5)
    }

    func testScreenshotShortcutSettingsUseInlineRecorder() {
        XCTAssertTrue(SettingsGeneralMetrics.containsScreenshotShortcut)
        XCTAssertTrue(SettingsGeneralMetrics.containsRecordingShortcut)
        XCTAssertFalse(SettingsScreenshotMetrics.containsShortcut)
        XCTAssertTrue(SettingsShortcutRecorderMetrics.usesInlineRecorder)
        XCTAssertEqual(SettingsShortcutRecorderMetrics.width, 118, accuracy: 0.5)
        XCTAssertEqual(SettingsShortcutRecorderMetrics.minHeight, 28, accuracy: 0.5)
        XCTAssertEqual(SettingsShortcutRecorderMetrics.cornerRadius, 7, accuracy: 0.5)
    }

    func testScreenshotStylePickerIncludesOriginalOutputOption() {
        XCTAssertEqual(WindowScreenshotDecorationStyle.allCases, [
            .softBackdrop,
            .canvasGlow,
            .transparentShadow,
            .original,
        ])
    }

    func testSaveLocationSettingsUseCompactSummaryRow() {
        XCTAssertTrue(SettingsGeneralMetrics.containsSaveLocation)
        XCTAssertFalse(SettingsScreenshotMetrics.containsSaveLocation)
        XCTAssertTrue(SettingsSaveLocationMetrics.usesSummaryRow)
        XCTAssertFalse(SettingsSaveLocationMetrics.opensChooserFromSummary)
        XCTAssertFalse(SettingsSaveLocationMetrics.showsFinderAction)
        XCTAssertFalse(SettingsSaveLocationMetrics.showsFolderName)
        XCTAssertTrue(SettingsSaveLocationMetrics.showsResetOnlyForCustomLocation)
        XCTAssertFalse(SettingsSaveLocationMetrics.usesNestedControlBackground)
        XCTAssertFalse(SettingsSaveLocationMetrics.usesSeparateRevealBox)
        XCTAssertEqual(SettingsSaveLocationMetrics.summaryWidth, 180, accuracy: 0.5)
    }

    func testSaveLocationSummaryUsesAbbreviatedPathForDefaultDirectory() {
        let homeURL = URL(fileURLWithPath: "/Users/deweyou", isDirectory: true)
        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)

        let summary = SettingsSaveLocationSummary(
            url: desktopURL,
            desktopURL: desktopURL,
            homeURL: homeURL
        )

        XCTAssertEqual(summary.path, "~/Desktop")
        XCTAssertTrue(summary.isDefaultLocation)
    }

    func testSaveLocationSummaryAbbreviatesCustomDirectoryUnderHome() {
        let homeURL = URL(fileURLWithPath: "/Users/deweyou", isDirectory: true)
        let desktopURL = homeURL.appendingPathComponent("Desktop", isDirectory: true)
        let customURL = homeURL
            .appendingPathComponent("Pictures", isDirectory: true)
            .appendingPathComponent("Frame Captures", isDirectory: true)

        let summary = SettingsSaveLocationSummary(
            url: customURL,
            desktopURL: desktopURL,
            homeURL: homeURL
        )

        XCTAssertEqual(summary.path, "~/Pictures/Frame Captures")
        XCTAssertFalse(summary.isDefaultLocation)
    }

    func testShortcutRecorderSuspendsGlobalHotKeyWhileRecording() {
        let button = ShortcutRecorderButton(frame: .zero)
        var recordingStates: [Bool] = []
        var appliedShortcuts: [ScreenshotShortcut] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { shortcut in
                appliedShortcuts.append(shortcut)
                return true
            },
            onValidationFailure: { _ in },
            onRecordingChange: { isRecording in
                recordingStates.append(isRecording)
            }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "a", modifiers: [.command, .shift], keyCode: kVK_ANSI_A))

        XCTAssertEqual(recordingStates, [true, false])
        XCTAssertEqual(appliedShortcuts, [.default])
    }

    func testShortcutRecorderResumesGlobalHotKeyWhenCancelled() {
        let button = ShortcutRecorderButton(frame: .zero)
        var recordingStates: [Bool] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { isRecording in
                recordingStates.append(isRecording)
            }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "\u{1B}", modifiers: [], keyCode: 53))

        XCTAssertEqual(recordingStates, [true, false])
    }

    func testShortcutRecorderShowsPressedModifiersWhileRecording() {
        let button = ShortcutRecorderButton(frame: .zero)
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.flagsChanged(with: flagsChangedEvent(modifiers: [.command], keyCode: kVK_Command))
        XCTAssertEqual(button.title, "⌘")

        button.flagsChanged(with: flagsChangedEvent(modifiers: [.command, .shift], keyCode: kVK_Shift))
        XCTAssertEqual(button.title, "⌘⇧")

        button.flagsChanged(with: flagsChangedEvent(modifiers: [], keyCode: kVK_Shift))
        XCTAssertEqual(button.title, "Press shortcut")
    }

    func testShortcutRecorderShowsInvalidPressedCombinationWhileRecording() {
        let button = ShortcutRecorderButton(frame: .zero)
        var failures: [ScreenshotShortcutValidationFailure?] = []
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { failure in
                failures.append(failure)
            },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "a", modifiers: [.command], keyCode: kVK_ANSI_A))

        XCTAssertEqual(button.title, "⌘A")
        XCTAssertEqual(failures, [nil, .insufficientModifiers])
    }

    func testShortcutRecorderCanReportDuplicateShortcut() {
        let strings = AppStrings(language: .en)

        XCTAssertEqual(
            strings.settingsShortcutRecorderError(.duplicateShortcut),
            "Already used by another Frame shortcut"
        )
    }

    func testShortcutRecorderKeepsPressedCombinationAfterViewUpdate() {
        let button = ShortcutRecorderButton(frame: .zero)
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        button.startRecording()
        button.keyDown(with: keyEvent(characters: "a", modifiers: [.command], keyCode: kVK_ANSI_A))
        button.update(
            strings: AppStrings(language: .en),
            shortcut: .default,
            onShortcutChange: { _ in true },
            onValidationFailure: { _ in },
            onRecordingChange: { _ in }
        )

        XCTAssertEqual(button.title, "⌘A")
    }

    func testSettingsWindowUsesConfiguredMinimumSize() throws {
        _ = NSApplication.shared
        let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
        let controller = SettingsWindowController()

        controller.show(
            strings: AppStrings(language: .en),
            onShortcutChange: { _ in true },
            onCheckPermission: {},
            onLanguageChange: { _ in },
            onChooseScreenshotDirectory: { nil },
            onResetScreenshotDirectory: {},
            onClearCaptureHistory: {}
        )

        let window = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) })
        defer {
            window.close()
        }

        XCTAssertEqual(window.minSize.width, 560, accuracy: 0.5)
        XCTAssertEqual(window.minSize.height, 460, accuracy: 0.5)
        XCTAssertEqual(window.frame.size.width, 620, accuracy: 0.5)
        XCTAssertEqual(window.frame.size.height, 600, accuracy: 0.5)
        XCTAssertEqual(window.title, "Settings")
        XCTAssertTrue(SettingsWindowLayout.usesCenteredTitlebarLabel)
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.toolbarStyle, .automatic)
        XCTAssertFalse(window.titlebarAppearsTransparent)
        XCTAssertFalse(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.contentViewController is NSHostingController<AnyView>)

        let titleField = try XCTUnwrap(
            descendant(
                in: window.contentView?.superview,
                identifier: SettingsWindowLayout.centeredTitlebarTitleIdentifier
            ) as? NSTextField
        )
        XCTAssertEqual(titleField.stringValue, "Settings")
    }

    func testOCRLanguageSettingsExposeDefaultOptions() {
        XCTAssertEqual(OCRLanguageOption.allCases.map(\.rawValue).count, 25)
        XCTAssertEqual(OCRLanguageOption.defaultIdentifiers.count, 5)
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("zh-Hans"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("zh-Hant"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("en-US"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("ja-JP"))
        XCTAssertTrue(OCRLanguageOption.defaultIdentifiers.contains("ko-KR"))
    }

    func testOCRLanguageSettingsOpenDedicatedChooserFromWholeRow() {
        XCTAssertFalse(SettingsOCRLanguageMetrics.usesDisclosure)
        XCTAssertTrue(SettingsOCRLanguageMetrics.usesSheet)
        XCTAssertTrue(SettingsOCRLanguageMetrics.opensFromWholeRow)
        XCTAssertEqual(SettingsOCRLanguageMetrics.sheetWidth, 420, accuracy: 0.5)
        XCTAssertEqual(SettingsOCRLanguageMetrics.sheetHeight, 460, accuracy: 0.5)
        XCTAssertEqual(SettingsOCRLanguageMetrics.gridMinimumItemWidth, 180, accuracy: 0.5)
        XCTAssertEqual(SettingsOCRLanguageMetrics.gridSpacing, 8, accuracy: 0.5)
    }

    func testRecordingMouseHintColorPresetsExposeDefaultAndCustomChoices() {
        XCTAssertEqual(RecordingMouseHintColorPreset.defaultPreset, .coral)
        XCTAssertEqual(RecordingMouseHintColorPreset.standardPresets.map(\.id), [
            "coral",
            "amber",
            "sky",
            "mint",
            "violet",
        ])
    }

    func testRecordingMouseHintColorPresetsExposeLocalizedAccessibilityLabels() {
        let strings = AppStrings(language: .zhHans)

        XCTAssertEqual(
            RecordingMouseHintColorPreset.standardPresets.map { $0.accessibilityLabel(strings: strings) },
            ["珊瑚色", "琥珀色", "天蓝色", "薄荷色", "紫色"]
        )
    }

    func testRecordingMouseHintColorUsesQuietSwatchPickerMetrics() {
        XCTAssertTrue(SettingsMouseHintColorMetrics.usesSwatchPicker)
        XCTAssertTrue(SettingsMouseHintColorMetrics.usesPresetOnlyPicker)
        XCTAssertTrue(SettingsMouseHintColorMetrics.usesSelectedCheckmark)
        XCTAssertFalse(SettingsMouseHintColorMetrics.showsCustomColorPicker)
        XCTAssertFalse(SettingsMouseHintColorMetrics.showsResetAction)
        XCTAssertEqual(SettingsMouseHintColorMetrics.swatchSize, 24, accuracy: 0.5)
    }

    func testSettingsWindowPlacementCentersInsideActiveVisibleFrame() {
        let visibleFrame = CGRect(x: 1440, y: 80, width: 1200, height: 800)
        let frame = SettingsWindowLayout.centeredFrame(
            windowSize: CGSize(width: 900, height: 540),
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(frame.midX, visibleFrame.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, visibleFrame.midY, accuracy: 0.5)
        XCTAssertEqual(frame.width, 900, accuracy: 0.5)
        XCTAssertEqual(frame.height, 540, accuracy: 0.5)
    }

    private func descendant(in view: NSView?, identifier: NSUserInterfaceItemIdentifier) -> NSView? {
        guard let view else {
            return nil
        }

        if view.identifier == identifier {
            return view
        }

        for subview in view.subviews {
            if let match = descendant(in: subview, identifier: identifier) {
                return match
            }
        }

        return nil
    }

    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags,
        keyCode: Int
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }

    private func flagsChangedEvent(
        modifiers: NSEvent.ModifierFlags,
        keyCode: Int
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: UInt16(keyCode)
        )!
    }
}
