import Foundation
import FrameCore

enum SettingsStore {
    static let screenshotShortcutKey = "screenshotShortcut"
    static let appLanguageKey = "appLanguage"
    static let screenshotDirectoryKey = "screenshotDirectory"
    static let ocrRecognitionLanguagesKey = "ocrRecognitionLanguages"
    static let captureHistoryEnabledKey = "captureHistoryEnabled"
    static let captureHistoryRetentionKey = "captureHistoryRetention"
    static let captureHistorySizeLimitKey = "captureHistorySizeLimit"
    static let recordingFormatKey = "recordingFormat"
    static let recordingShowsCursorKey = "recordingShowsCursor"
    static let recordingShowsMouseClickHighlightsKey = "recordingShowsMouseClickHighlights"
    static let recordingShowsKeyboardHintsKey = "recordingShowsKeyboardHints"
    static let recordingAudioSourceKey = "recordingAudioSource"

    static func screenshotShortcut(defaults: UserDefaults = .standard) -> ScreenshotShortcut {
        ScreenshotShortcut.persistedValue(for: defaults.string(forKey: screenshotShortcutKey))
    }

    static func setScreenshotShortcut(
        _ shortcut: ScreenshotShortcut,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(shortcut.rawValue, forKey: screenshotShortcutKey)
    }

    static func appLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: appLanguageKey) ?? "") ?? .system
    }

    static func setAppLanguage(
        _ language: AppLanguage,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(language.rawValue, forKey: appLanguageKey)
    }

    static func ocrRecognitionLanguages(defaults: UserDefaults = .standard) -> [String] {
        guard let identifiers = defaults.array(forKey: ocrRecognitionLanguagesKey) as? [String] else {
            return OCRLanguageOption.defaultIdentifiers
        }

        return OCRLanguageOption.validatedIdentifiers(identifiers)
    }

    @discardableResult
    static func setOCRRecognitionLanguages(
        _ identifiers: [String],
        defaults: UserDefaults = .standard
    ) -> [String] {
        let validatedIdentifiers = OCRLanguageOption.validatedIdentifiers(identifiers)
        defaults.set(validatedIdentifiers, forKey: ocrRecognitionLanguagesKey)
        return validatedIdentifiers
    }

    static func screenshotDirectory(
        defaults: UserDefaults = .standard,
        desktopDirectory: () throws -> URL = { try ScreenshotNaming.desktopDirectory() }
    ) throws -> URL {
        guard let path = defaults.string(forKey: screenshotDirectoryKey),
              !path.isEmpty else {
            return try desktopDirectory()
        }

        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setScreenshotDirectory(
        _ directory: URL,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(directory.path, forKey: screenshotDirectoryKey)
    }

    static func resetScreenshotDirectory(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: screenshotDirectoryKey)
    }

    static func isCaptureHistoryEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: captureHistoryEnabledKey) != nil else {
            return true
        }

        return defaults.bool(forKey: captureHistoryEnabledKey)
    }

    static func setCaptureHistoryEnabled(_ isEnabled: Bool, defaults: UserDefaults = .standard) {
        defaults.set(isEnabled, forKey: captureHistoryEnabledKey)
    }

    static func captureHistoryRetention(defaults: UserDefaults = .standard) -> CaptureHistoryRetention {
        CaptureHistoryRetention(rawValue: defaults.string(forKey: captureHistoryRetentionKey) ?? "")
            ?? .sevenDays
    }

    static func setCaptureHistoryRetention(
        _ retention: CaptureHistoryRetention,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(retention.rawValue, forKey: captureHistoryRetentionKey)
    }

    static func captureHistorySizeLimit(defaults: UserDefaults = .standard) -> CaptureHistorySizeLimit {
        CaptureHistorySizeLimit(rawValue: defaults.string(forKey: captureHistorySizeLimitKey) ?? "")
            ?? .twoGB
    }

    static func setCaptureHistorySizeLimit(
        _ sizeLimit: CaptureHistorySizeLimit,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(sizeLimit.rawValue, forKey: captureHistorySizeLimitKey)
    }

    static func recordingOptions(defaults: UserDefaults = .standard) -> RecordingOptions {
        let defaultOptions = RecordingOptions.defaults
        let format = RecordingFormat(rawValue: defaults.string(forKey: recordingFormatKey) ?? "")
            ?? defaultOptions.format
        let audioSource = RecordingAudioSource(rawValue: defaults.string(forKey: recordingAudioSourceKey) ?? "")
            ?? defaultOptions.audioSource
        let showsCursor = defaults.object(forKey: recordingShowsCursorKey) == nil
            ? defaultOptions.showsCursor
            : defaults.bool(forKey: recordingShowsCursorKey)
        let showsMouseClickHighlights = defaults.object(forKey: recordingShowsMouseClickHighlightsKey) == nil
            ? defaultOptions.showsMouseClickHighlights
            : defaults.bool(forKey: recordingShowsMouseClickHighlightsKey)
        let showsMouseHints = showsCursor || showsMouseClickHighlights
        let showsKeyboardHints = defaults.object(forKey: recordingShowsKeyboardHintsKey) == nil
            ? defaultOptions.showsKeyboardHints
            : defaults.bool(forKey: recordingShowsKeyboardHintsKey)

        return RecordingOptions(
            format: format,
            showsCursor: showsMouseHints,
            showsMouseClickHighlights: showsMouseHints,
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
        defaults.set(options.showsMouseClickHighlights, forKey: recordingShowsMouseClickHighlightsKey)
        defaults.set(options.showsKeyboardHints, forKey: recordingShowsKeyboardHintsKey)
        defaults.set(options.audioSource.rawValue, forKey: recordingAudioSourceKey)
    }
}
