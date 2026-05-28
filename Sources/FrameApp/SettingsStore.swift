import Foundation
import FrameCore

enum SettingsStore {
    static let screenshotShortcutKey = "screenshotShortcut"
    static let appLanguageKey = "appLanguage"
    static let screenshotDirectoryKey = "screenshotDirectory"

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
