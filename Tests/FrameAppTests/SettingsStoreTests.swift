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
