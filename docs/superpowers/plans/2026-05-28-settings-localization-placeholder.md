# Settings Localization Placeholder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add locally persisted screenshot save location and language settings, centralize current user-facing copy for Chinese/English, and replace the first capture's empty `0 x 0` HUD with a centered placeholder hint.

**Architecture:** Keep deterministic settings and localization logic in small `FrameApp` boundaries (`SettingsStore`, `AppStrings`). Keep file output inside `ScreenshotFileWriter`, settings UI inside `SettingsWindowController`, and overlay placeholder rendering inside `SelectionOverlayWindow`. Existing menu, alert, Quick Access, and overlay surfaces receive strings from `AppStrings` at creation time.

**Tech Stack:** Swift 6.1/6.2, AppKit, SwiftUI settings views, Swift Testing/XCTest, `UserDefaults`, `FileManager`, SwiftPM.

---

## File Structure

- Modify `Sources/FrameApp/SettingsStore.swift`: add language and screenshot directory persistence helpers.
- Create `Sources/FrameApp/AppStrings.swift`: add `AppLanguage`, `ResolvedAppLanguage`, and typed string table.
- Modify `Sources/FrameApp/ScreenshotFileWriter.swift`: accept a save-directory provider and localized strings for write errors.
- Modify `Sources/FrameApp/SettingsWindowController.swift`: add save location and language controls, refresh labels when language changes.
- Modify `Sources/FrameApp/StatusItemController.swift`: build menu titles from `AppStrings` and expose `reloadMenu()`.
- Modify `Sources/FrameApp/AppDelegate.swift`: own current strings, wire language changes, pass strings to alerts, Quick Access, file writer, settings, and overlay.
- Modify `Sources/FrameApp/QuickAccessPanelController.swift`: accept localized action labels.
- Modify `Sources/FrameApp/SelectionOverlayController.swift`: pass the capture placeholder string to overlay windows.
- Modify `Sources/FrameApp/SelectionOverlayWindow.swift`: render a text placeholder when there is no active selection instead of showing the size control at `0 x 0`.
- Create `Tests/FrameAppTests/SettingsStoreTests.swift`: cover settings persistence defaults and custom values.
- Create `Tests/FrameAppTests/AppStringsTests.swift`: cover language resolution and key strings.
- Create `Tests/FrameAppTests/ScreenshotFileWriterTests.swift`: cover custom save directory output.
- Update `docs/architecture.md` and `docs/development.md`: document local settings, language behavior, and configurable save location smoke checks.

## Task 1: Settings Persistence

**Files:**
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing settings persistence tests**

Create `Tests/FrameAppTests/SettingsStoreTests.swift`:

```swift
import XCTest
@testable import FrameApp

final class SettingsStoreTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "FrameTests.SettingsStore.\(UUID().uuidString)")!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        defaults = nil
        super.tearDown()
    }

    private var defaultsSuiteName: String {
        defaults.dictionaryRepresentation()["NSArgumentDomain"] as? String ?? ""
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
```

- [ ] **Step 2: Run tests and verify red**

Run: `swift test --filter SettingsStoreTests`

Expected: compile failures for missing `AppLanguage`, `appLanguage`, `setAppLanguage`, `screenshotDirectory`, `setScreenshotDirectory`, and `resetScreenshotDirectory`.

- [ ] **Step 3: Implement settings persistence**

Update `Sources/FrameApp/SettingsStore.swift` to add:

```swift
enum SettingsStore {
    static let screenshotShortcutKey = "screenshotShortcut"
    static let appLanguageKey = "appLanguage"
    static let screenshotDirectoryKey = "screenshotDirectory"

    static func screenshotShortcut(defaults: UserDefaults = .standard) -> ScreenshotShortcut { ... }
    static func setScreenshotShortcut(_ shortcut: ScreenshotShortcut, defaults: UserDefaults = .standard) { ... }

    static func appLanguage(defaults: UserDefaults = .standard) -> AppLanguage {
        AppLanguage(rawValue: defaults.string(forKey: appLanguageKey) ?? "") ?? .system
    }

    static func setAppLanguage(_ language: AppLanguage, defaults: UserDefaults = .standard) {
        defaults.set(language.rawValue, forKey: appLanguageKey)
    }

    static func screenshotDirectory(
        defaults: UserDefaults = .standard,
        desktopDirectory: () throws -> URL = { try ScreenshotNaming.desktopDirectory() }
    ) throws -> URL {
        guard let path = defaults.string(forKey: screenshotDirectoryKey), !path.isEmpty else {
            return try desktopDirectory()
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func setScreenshotDirectory(_ directory: URL, defaults: UserDefaults = .standard) {
        defaults.set(directory.path, forKey: screenshotDirectoryKey)
    }

    static func resetScreenshotDirectory(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: screenshotDirectoryKey)
    }
}
```

- [ ] **Step 4: Run tests and verify green**

Run: `swift test --filter SettingsStoreTests`

Expected: `SettingsStoreTests` passes.

## Task 2: AppStrings Localization Boundary

**Files:**
- Create: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/AppStringsTests.swift`

- [ ] **Step 1: Write failing localization tests**

Create `Tests/FrameAppTests/AppStringsTests.swift`:

```swift
import XCTest
@testable import FrameApp

final class AppStringsTests: XCTestCase {
    func testExplicitEnglishStrings() {
        let strings = AppStrings(language: .en)

        XCTAssertEqual(strings.menuCapture, "Capture")
        XCTAssertEqual(strings.settingsTitle, "Settings")
        XCTAssertEqual(strings.capturePlaceholder, "Drag to select an area")
        XCTAssertEqual(strings.quickAccessSave, "Save")
    }

    func testExplicitChineseStrings() {
        let strings = AppStrings(language: .zhHans)

        XCTAssertEqual(strings.menuCapture, "截图")
        XCTAssertEqual(strings.settingsTitle, "设置")
        XCTAssertEqual(strings.capturePlaceholder, "拖拽以选择截图区域")
        XCTAssertEqual(strings.quickAccessSave, "保存")
    }

    func testSystemChineseResolvesToSimplifiedChinese() {
        XCTAssertEqual(
            AppStrings.resolvedLanguage(for: .system, preferredLanguages: ["zh-Hans-CN"]),
            .zhHans
        )
    }

    func testSystemNonChineseResolvesToEnglish() {
        XCTAssertEqual(
            AppStrings.resolvedLanguage(for: .system, preferredLanguages: ["fr-FR", "en-US"]),
            .en
        )
    }
}
```

- [ ] **Step 2: Run tests and verify red**

Run: `swift test --filter AppStringsTests`

Expected: compile failures for missing `AppStrings` and `AppLanguage`.

- [ ] **Step 3: Implement `AppStrings`**

Create `Sources/FrameApp/AppStrings.swift` with `AppLanguage: String, CaseIterable, Identifiable`, `ResolvedAppLanguage`, and typed string properties for menu, settings, permission, Quick Access, alerts, HUD, and logs.

- [ ] **Step 4: Run tests and verify green**

Run: `swift test --filter AppStringsTests`

Expected: `AppStringsTests` passes.

## Task 3: Configurable Screenshot Output

**Files:**
- Modify: `Sources/FrameApp/ScreenshotFileWriter.swift`
- Test: `Tests/FrameAppTests/ScreenshotFileWriterTests.swift`

- [ ] **Step 1: Write failing file writer tests**

Create `Tests/FrameAppTests/ScreenshotFileWriterTests.swift`:

```swift
import XCTest
@testable import FrameApp

final class ScreenshotFileWriterTests: XCTestCase {
    func testWriteUsesConfiguredDirectory() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FrameWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let writer = ScreenshotFileWriter(
            fileManager: .default,
            saveDirectory: { temporaryDirectory },
            strings: AppStrings(language: .en)
        )

        let url = try writer.write(pngData: Data([1, 2, 3]), date: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(url.deletingLastPathComponent(), temporaryDirectory)
        XCTAssertEqual(try Data(contentsOf: url), Data([1, 2, 3]))
    }
}
```

- [ ] **Step 2: Run tests and verify red**

Run: `swift test --filter ScreenshotFileWriterTests`

Expected: compile failure for missing initializer parameters.

- [ ] **Step 3: Implement configurable writer**

Update `ScreenshotFileWriter` to take `saveDirectory: () throws -> URL` and `strings: AppStrings`, defaulting to `SettingsStore.screenshotDirectory` and `AppStrings.current()`. Use the configured directory when composing `saveURL`; use localized write failure text.

- [ ] **Step 4: Run tests and verify green**

Run: `swift test --filter ScreenshotFileWriterTests`

Expected: `ScreenshotFileWriterTests` passes.

## Task 4: Settings UI and Runtime Language Refresh

**Files:**
- Modify: `Sources/FrameApp/SettingsWindowController.swift`
- Modify: `Sources/FrameApp/StatusItemController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [ ] **Step 1: Add settings UI wiring**

Update `SettingsWindowController.show` to accept `strings`, `onLanguageChange`, `onChooseScreenshotDirectory`, and `onResetScreenshotDirectory`. Add SwiftUI rows for save location and language picker. Use `NSOpenPanel` from the controller or delegate layer for directory choice.

- [ ] **Step 2: Localize menu and alerts**

Update `StatusItemController` to accept `AppStrings` and rebuild menu titles through `reloadMenu(strings:)`. Update `AppDelegate` to keep `private var strings = AppStrings.current()` and call `statusItemController?.reloadMenu(strings:)` after language changes.

- [ ] **Step 3: Run targeted build**

Run: `swift build`

Expected: build passes.

## Task 5: Quick Access and Placeholder Copy

**Files:**
- Modify: `Sources/FrameApp/QuickAccessPanelController.swift`
- Modify: `Sources/FrameApp/SelectionOverlayController.swift`
- Modify: `Sources/FrameApp/SelectionOverlayWindow.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [ ] **Step 1: Localize Quick Access actions**

Pass `AppStrings` into `QuickAccessPanelController.show` and use it for Save, Copy, Open, Pin, and Close labels/tooltips.

- [ ] **Step 2: Replace empty HUD with placeholder**

Pass `strings.capturePlaceholder` from `SelectionOverlayController.startSelection` into each `SelectionOverlayWindow`. In `SelectionOverlayView`, add a centered glass text view shown only when `displayedLocalRect == nil && showsCenteredHUDWhenEmpty`. Hide `sizeView` in this state so `0 x 0` is not visible.

- [ ] **Step 3: Run targeted tests and build**

Run:

```sh
swift test --filter AppStringsTests
swift test --filter SettingsStoreTests
swift test --filter ScreenshotFileWriterTests
swift build
```

Expected: all commands pass.

## Task 6: Docs and Full Verification

**Files:**
- Modify: `docs/architecture.md`
- Modify: `docs/development.md`

- [ ] **Step 1: Update docs**

Document `SettingsStore`, `AppStrings`, configurable save location, language behavior, and manual smoke checks for choosing a save folder and switching languages.

- [ ] **Step 2: Run required verification**

Run:

```sh
swift test
swift build
scripts/package-app.sh
```

Expected: all commands pass and `.build/app/Frame.app` is created.

## Self-Review

- Spec coverage: save location persistence is covered in Tasks 1, 3, 4, and 6; language settings and centralized copy are covered in Tasks 1, 2, 4, 5, and 6; placeholder HUD is covered in Task 5.
- Placeholder scan: no `TBD`, `TODO`, or incomplete implementation placeholders remain.
- Type consistency: `AppLanguage`, `AppStrings`, `SettingsStore`, and `ScreenshotFileWriter` names are consistent across tasks.
