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
}
