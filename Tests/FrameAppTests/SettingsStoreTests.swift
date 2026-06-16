import FrameCore
import XCTest
@testable import FrameApp

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "FrameTests.SettingsStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testLanguageDefaultsToSystem() {
        XCTAssertEqual(SettingsStore.appLanguage(defaults: defaults), .system)
    }

    func testLanguagePersistsExplicitChoice() {
        SettingsStore.setAppLanguage(.en, defaults: defaults)

        XCTAssertEqual(SettingsStore.appLanguage(defaults: defaults), .en)
    }

    func testScreenshotShortcutPersistsCustomStorageValue() {
        let shortcut = ScreenshotShortcut(key: .number("7"), modifiers: [.command, .option])

        SettingsStore.setScreenshotShortcut(shortcut, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: SettingsStore.screenshotShortcutKey), "cmd+option+7")
        XCTAssertEqual(SettingsStore.screenshotShortcut(defaults: defaults), shortcut)
    }

    func testScreenshotShortcutPersistsPresetAsCustomStorageValue() {
        SettingsStore.setScreenshotShortcut(.commandShiftS, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: SettingsStore.screenshotShortcutKey), "cmd+shift+s")
        XCTAssertEqual(
            SettingsStore.screenshotShortcut(defaults: defaults),
            ScreenshotShortcut(key: .letter("S"), modifiers: [.command, .shift])
        )
    }

    func testScreenshotShortcutReadsLegacyPresetValue() {
        defaults.set("commandShiftS", forKey: SettingsStore.screenshotShortcutKey)

        XCTAssertEqual(
            SettingsStore.screenshotShortcut(defaults: defaults),
            ScreenshotShortcut(key: .letter("S"), modifiers: [.command, .shift])
        )
    }

    func testRecordingShortcutDefaultsToCommandShiftR() {
        XCTAssertEqual(SettingsStore.recordingShortcut(defaults: defaults), .defaultRecording)
    }

    func testRecordingShortcutPersistsCustomStorageValue() {
        let shortcut = ScreenshotShortcut(key: .number("8"), modifiers: [.command, .control])

        SettingsStore.setRecordingShortcut(shortcut, defaults: defaults)

        XCTAssertEqual(defaults.string(forKey: SettingsStore.recordingShortcutKey), "cmd+control+8")
        XCTAssertEqual(SettingsStore.recordingShortcut(defaults: defaults), shortcut)
    }

    func testWindowScreenshotDecorationStyleDefaultsToSoftBackdrop() {
        XCTAssertEqual(SettingsStore.windowScreenshotDecorationStyle(defaults: defaults), .softBackdrop)
    }

    func testWindowScreenshotDecorationStylePersistsExplicitChoice() {
        SettingsStore.setWindowScreenshotDecorationStyle(.canvasGlow, defaults: defaults)

        XCTAssertEqual(SettingsStore.windowScreenshotDecorationStyle(defaults: defaults), .canvasGlow)
    }

    func testWindowScreenshotDecorationStyleFallsBackWhenPersistedValueIsInvalid() {
        defaults.set("bad-style", forKey: SettingsStore.windowScreenshotDecorationStyleKey)

        XCTAssertEqual(SettingsStore.windowScreenshotDecorationStyle(defaults: defaults), .softBackdrop)
    }

    func testOCRLanguagesDefaultToChineseEnglishJapaneseAndKorean() {
        XCTAssertEqual(
            SettingsStore.ocrRecognitionLanguages(defaults: defaults),
            ["zh-Hans", "zh-Hant", "en-US", "ja-JP", "ko-KR"]
        )
    }

    func testOCRLanguagesPersistSelectedIdentifiers() {
        SettingsStore.setOCRRecognitionLanguages(["en-US", "fr-FR"], defaults: defaults)

        XCTAssertEqual(SettingsStore.ocrRecognitionLanguages(defaults: defaults), ["en-US", "fr-FR"])
    }

    func testOCRLanguagesFilterInvalidIdentifiers() {
        defaults.set(["en-US", "bad-language", "zh-Hans"], forKey: SettingsStore.ocrRecognitionLanguagesKey)

        XCTAssertEqual(SettingsStore.ocrRecognitionLanguages(defaults: defaults), ["en-US", "zh-Hans"])
    }

    func testOCRLanguagesFallBackToDefaultsWhenPersistedListIsEmptyOrInvalid() {
        SettingsStore.setOCRRecognitionLanguages([], defaults: defaults)

        XCTAssertEqual(
            SettingsStore.ocrRecognitionLanguages(defaults: defaults),
            OCRLanguageOption.defaultIdentifiers
        )

        defaults.set(["bad-language"], forKey: SettingsStore.ocrRecognitionLanguagesKey)

        XCTAssertEqual(
            SettingsStore.ocrRecognitionLanguages(defaults: defaults),
            OCRLanguageOption.defaultIdentifiers
        )
    }

    func testScreenshotDirectoryDefaultsToDesktop() throws {
        let desktop = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)
        let directory = try SettingsStore.screenshotDirectory(
            defaults: defaults,
            desktopDirectory: { desktop }
        )

        XCTAssertEqual(directory, desktop)
    }

    func testScreenshotDirectoryPersistsCustomFolder() throws {
        let custom = URL(fileURLWithPath: "/Users/test/Pictures/Captures", isDirectory: true)
        SettingsStore.setScreenshotDirectory(custom, defaults: defaults)

        let directory = try SettingsStore.screenshotDirectory(
            defaults: defaults,
            desktopDirectory: { URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true) }
        )

        XCTAssertEqual(directory, custom)
    }

    func testResetScreenshotDirectoryReturnsToDesktop() throws {
        SettingsStore.setScreenshotDirectory(
            URL(fileURLWithPath: "/Users/test/Pictures/Captures", isDirectory: true),
            defaults: defaults
        )
        SettingsStore.resetScreenshotDirectory(defaults: defaults)

        let desktop = URL(fileURLWithPath: "/Users/test/Desktop", isDirectory: true)
        let directory = try SettingsStore.screenshotDirectory(
            defaults: defaults,
            desktopDirectory: { desktop }
        )

        XCTAssertEqual(directory, desktop)
    }

    func testCaptureHistoryDefaultsToEnabledSevenDaysAndTwoGB() {
        XCTAssertTrue(SettingsStore.isCaptureHistoryEnabled(defaults: defaults))
        XCTAssertEqual(SettingsStore.captureHistoryRetention(defaults: defaults), .sevenDays)
        XCTAssertEqual(SettingsStore.captureHistorySizeLimit(defaults: defaults), .twoGB)
    }

    func testCaptureHistoryPersistsSettings() {
        SettingsStore.setCaptureHistoryEnabled(false, defaults: defaults)
        SettingsStore.setCaptureHistoryRetention(.thirtyDays, defaults: defaults)
        SettingsStore.setCaptureHistorySizeLimit(.fiveGB, defaults: defaults)

        XCTAssertFalse(SettingsStore.isCaptureHistoryEnabled(defaults: defaults))
        XCTAssertEqual(SettingsStore.captureHistoryRetention(defaults: defaults), .thirtyDays)
        XCTAssertEqual(SettingsStore.captureHistorySizeLimit(defaults: defaults), .fiveGB)
    }

    func testCaptureHistoryInvalidPersistedValuesFallBackToDefaults() {
        defaults.set("bad-retention", forKey: SettingsStore.captureHistoryRetentionKey)
        defaults.set("bad-size", forKey: SettingsStore.captureHistorySizeLimitKey)

        XCTAssertEqual(SettingsStore.captureHistoryRetention(defaults: defaults), .sevenDays)
        XCTAssertEqual(SettingsStore.captureHistorySizeLimit(defaults: defaults), .twoGB)
    }

    func testRecordingOptionsDefaultToCoreDefaults() {
        XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), RecordingOptions.defaults)
    }

    func testRecordingOptionsPersistMouseHintColor() {
        let options = RecordingOptions(
            format: .mp4,
            showsCursor: true,
            showsMouseClickHighlights: true,
            showsKeyboardHints: true,
            audioSource: .none,
            mouseHintColor: RecordingMouseHintColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1)
        )

        SettingsStore.setRecordingOptions(options, defaults: defaults)

        XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), options)
    }

    func testRecordingOptionsFallBackToDefaultMouseHintColorWhenPersistedColorIsInvalid() {
        defaults.set("not-a-color", forKey: SettingsStore.recordingMouseHintColorKey)

        XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), RecordingOptions.defaults)
    }

    func testRecordingOptionsPersistSelectedValues() {
        let options = RecordingOptions(
            format: .gif,
            showsCursor: false,
            showsMouseClickHighlights: false,
            showsKeyboardHints: false,
            audioSource: .none
        )

        SettingsStore.setRecordingOptions(options, defaults: defaults)

        XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), options)
    }

    func testRecordingOptionsMergePersistedCursorAndClickHighlightValues() {
        let options = RecordingOptions(
            format: .mp4,
            showsCursor: false,
            showsMouseClickHighlights: true,
            showsKeyboardHints: false,
            audioSource: .none
        )

        SettingsStore.setRecordingOptions(options, defaults: defaults)

        XCTAssertEqual(
            SettingsStore.recordingOptions(defaults: defaults),
            RecordingOptions(
                format: .mp4,
                showsCursor: true,
                showsMouseClickHighlights: true,
                showsKeyboardHints: false,
                audioSource: .none
            )
        )
    }

    func testRecordingOptionsFallbackWhenPersistedFormatIsInvalid() {
        defaults.set("bad-format", forKey: SettingsStore.recordingFormatKey)
        defaults.set("bad-audio", forKey: SettingsStore.recordingAudioSourceKey)

        XCTAssertEqual(SettingsStore.recordingOptions(defaults: defaults), RecordingOptions.defaults)
    }

    func testImageAnnotationEditingOptionsDefaultToCoreDefaults() {
        XCTAssertEqual(
            SettingsStore.imageAnnotationEditingOptions(defaults: defaults),
            ImageAnnotationEditingOptions()
        )
    }

    func testImageAnnotationEditingOptionsPersistSelectedValues() {
        var options = ImageAnnotationEditingOptions()
        options.shapeKind = .arrow
        options.mosaicMode = .brush
        options.style.strokeColor = .blue
        options.style.lineWidth = 24
        options.style.fontSize = 28

        SettingsStore.setImageAnnotationEditingOptions(options, defaults: defaults)

        XCTAssertEqual(SettingsStore.imageAnnotationEditingOptions(defaults: defaults), options)
    }

    func testImageAnnotationEditingOptionsFallbackWhenPersistedValuesAreInvalid() {
        defaults.set("bad-shape", forKey: SettingsStore.imageAnnotationShapeKindKey)
        defaults.set("bad-mosaic", forKey: SettingsStore.imageAnnotationMosaicModeKey)
        defaults.set("bad-color", forKey: SettingsStore.imageAnnotationStrokeColorKey)
        defaults.set(99, forKey: SettingsStore.imageAnnotationLineWidthKey)
        defaults.set(99, forKey: SettingsStore.imageAnnotationFontSizeKey)

        XCTAssertEqual(
            SettingsStore.imageAnnotationEditingOptions(defaults: defaults),
            ImageAnnotationEditingOptions()
        )
    }
}
