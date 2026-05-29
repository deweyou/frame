import Foundation
import FrameCore

enum SettingsStore {
    static let screenshotShortcutKey = "screenshotShortcut"
    static let appLanguageKey = "appLanguage"
    static let screenshotDirectoryKey = "screenshotDirectory"
    static let ocrRecognitionLanguagesKey = "ocrRecognitionLanguages"

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
}
