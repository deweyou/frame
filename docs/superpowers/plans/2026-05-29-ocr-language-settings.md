# OCR Language Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add configurable OCR recognition languages with a Chinese/English/Japanese/Korean default set.

**Architecture:** Keep language metadata and persistence in `FrameApp` using project-owned types. `SettingsStore` validates persisted identifiers, `OCRService` receives configured language identifiers, and `SettingsWindowController` exposes native checkboxes in General settings.

**Tech Stack:** Swift 6.1, AppKit, SwiftUI settings pane, Vision, XCTest, Swift Testing.

---

## File Structure

- Create `Sources/FrameApp/OCRLanguageOption.swift` for supported OCR language identifiers, default flags, and display-name routing.
- Modify `Sources/FrameApp/SettingsStore.swift` to persist and validate selected OCR language identifiers.
- Modify `Sources/FrameApp/OCRService.swift` to configure Vision requests from `SettingsStore`.
- Modify `Sources/FrameApp/AppStrings.swift` to localize the OCR language section and language names.
- Modify `Sources/FrameApp/SettingsWindowController.swift` to show OCR language checkboxes.
- Modify `Tests/FrameAppTests/SettingsStoreTests.swift` for persistence and validation.
- Modify `Tests/FrameAppTests/OCRServiceTests.swift` for request configuration.
- Modify `Tests/FrameAppTests/AppStringsTests.swift` for localized labels.
- Modify `Tests/FrameAppTests/SettingsWindowControllerTests.swift` for settings UI presence.

## Task 1: OCR Language Model And Settings Persistence

**Files:**
- Create: `Sources/FrameApp/OCRLanguageOption.swift`
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Test: `Tests/FrameAppTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write failing SettingsStore tests**

Add tests to `SettingsStoreTests`:

```swift
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
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: compile failure for missing `OCRLanguageOption`, `ocrRecognitionLanguagesKey`, `ocrRecognitionLanguages`, and `setOCRRecognitionLanguages`.

- [ ] **Step 3: Add OCR language option model**

Create `Sources/FrameApp/OCRLanguageOption.swift`:

```swift
import Foundation

enum OCRLanguageOption: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en-US"
    case japanese = "ja-JP"
    case korean = "ko-KR"
    case french = "fr-FR"
    case italian = "it-IT"
    case german = "de-DE"
    case spanish = "es-ES"
    case portugueseBrazil = "pt-BR"
    case russian = "ru-RU"
    case ukrainian = "uk-UA"
    case thai = "th-TH"
    case vietnamese = "vi-VT"
    case arabic = "ar-SA"
    case turkish = "tr-TR"
    case indonesian = "id-ID"
    case czech = "cs-CZ"
    case danish = "da-DK"
    case dutch = "nl-NL"
    case norwegian = "no-NO"
    case malay = "ms-MY"
    case polish = "pl-PL"
    case romanian = "ro-RO"
    case swedish = "sv-SE"

    var id: String { rawValue }

    static let defaultIdentifiers = [
        simplifiedChinese.rawValue,
        traditionalChinese.rawValue,
        english.rawValue,
        japanese.rawValue,
        korean.rawValue,
    ]

    static func validatedIdentifiers(_ identifiers: [String]) -> [String] {
        let supported = Set(allCases.map(\.rawValue))
        let filtered = identifiers.filter { supported.contains($0) }
        return filtered.isEmpty ? defaultIdentifiers : filtered
    }
}
```

- [ ] **Step 4: Add SettingsStore persistence**

Update `SettingsStore.swift`:

```swift
static let ocrRecognitionLanguagesKey = "ocrRecognitionLanguages"

static func ocrRecognitionLanguages(defaults: UserDefaults = .standard) -> [String] {
    guard let identifiers = defaults.array(forKey: ocrRecognitionLanguagesKey) as? [String] else {
        return OCRLanguageOption.defaultIdentifiers
    }

    return OCRLanguageOption.validatedIdentifiers(identifiers)
}

static func setOCRRecognitionLanguages(
    _ identifiers: [String],
    defaults: UserDefaults = .standard
) {
    defaults.set(OCRLanguageOption.validatedIdentifiers(identifiers), forKey: ocrRecognitionLanguagesKey)
}
```

- [ ] **Step 5: Run SettingsStore tests and commit**

Run:

```bash
swift test --filter SettingsStoreTests
```

Expected: PASS.

Commit:

```bash
git add Sources/FrameApp/OCRLanguageOption.swift Sources/FrameApp/SettingsStore.swift Tests/FrameAppTests/SettingsStoreTests.swift
git commit -m "feat: persist OCR language settings"
```

## Task 2: OCR Service Uses Selected Languages

**Files:**
- Modify: `Sources/FrameApp/OCRService.swift`
- Test: `Tests/FrameAppTests/OCRServiceTests.swift`

- [ ] **Step 1: Write failing OCR request configuration tests**

Update `OCRServiceTests`:

```swift
func testConfigureTextRecognitionRequestUsesProvidedLanguages() {
    let request = VNRecognizeTextRequest()

    configureTextRecognitionRequest(request, recognitionLanguages: ["fr-FR", "en-US"])

    XCTAssertEqual(request.recognitionLanguages, ["fr-FR", "en-US"])
}

func testConfigureTextRecognitionRequestUsesSettingsDefaultLanguages() {
    let request = VNRecognizeTextRequest()

    configureTextRecognitionRequest(request)

    XCTAssertEqual(request.recognitionLanguages, SettingsStore.ocrRecognitionLanguages())
}
```

Replace the old hard-coded language assertion with `SettingsStore.ocrRecognitionLanguages()` in `testConfigureTextRecognitionRequestIncludesChineseAndEnglish`.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter OCRServiceTests
```

Expected: compile failure because `configureTextRecognitionRequest(_:recognitionLanguages:)` does not exist.

- [ ] **Step 3: Add injectable recognition language configuration**

Update `OCRService.swift`:

```swift
func configureTextRecognitionRequest(
    _ request: VNRecognizeTextRequest,
    recognitionLanguages: [String] = SettingsStore.ocrRecognitionLanguages()
) {
    request.recognitionLevel = .accurate
    request.recognitionLanguages = OCRLanguageOption.validatedIdentifiers(recognitionLanguages)
    request.usesLanguageCorrection = true
}
```

- [ ] **Step 4: Run OCR service tests and commit**

Run:

```bash
swift test --filter OCRServiceTests
```

Expected: PASS.

Commit:

```bash
git add Sources/FrameApp/OCRService.swift Tests/FrameAppTests/OCRServiceTests.swift
git commit -m "feat: configure OCR request languages from settings"
```

## Task 3: Localized Settings Labels

**Files:**
- Modify: `Sources/FrameApp/AppStrings.swift`
- Test: `Tests/FrameAppTests/AppStringsTests.swift`

- [ ] **Step 1: Write failing localization tests**

Add to `AppStringsTests.testOCRStringsAreLocalized()`:

```swift
XCTAssertEqual(english.settingsOCRLanguages, "OCR Languages")
XCTAssertEqual(english.ocrLanguageDisplayName(.simplifiedChinese), "Simplified Chinese")
XCTAssertEqual(english.ocrLanguageDisplayName(.japanese), "Japanese")

XCTAssertEqual(chinese.settingsOCRLanguages, "OCR 识别语言")
XCTAssertEqual(chinese.ocrLanguageDisplayName(.simplifiedChinese), "简体中文")
XCTAssertEqual(chinese.ocrLanguageDisplayName(.japanese), "日文")
```

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
swift test --filter AppStringsTests
```

Expected: compile failure for missing strings methods.

- [ ] **Step 3: Add localized strings**

Add `settingsOCRLanguages` and `ocrLanguageDisplayName(_:)` to `AppStrings.swift`.

```swift
var settingsOCRLanguages: String {
    switch language {
    case .en: "OCR Languages"
    case .zhHans: "OCR 识别语言"
    }
}

func ocrLanguageDisplayName(_ option: OCRLanguageOption) -> String {
    switch (language, option) {
    case (.en, .simplifiedChinese): "Simplified Chinese"
    case (.zhHans, .simplifiedChinese): "简体中文"
    case (.en, .traditionalChinese): "Traditional Chinese"
    case (.zhHans, .traditionalChinese): "繁体中文"
    case (.en, .english): "English"
    case (.zhHans, .english): "英文"
    case (.en, .japanese): "Japanese"
    case (.zhHans, .japanese): "日文"
    case (.en, .korean): "Korean"
    case (.zhHans, .korean): "韩文"
    default: option.rawValue
    }
}
```

Then replace the `default` branch with explicit names for every `OCRLanguageOption` before committing.

- [ ] **Step 4: Run localization tests and commit**

Run:

```bash
swift test --filter AppStringsTests
```

Expected: PASS.

Commit:

```bash
git add Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/AppStringsTests.swift
git commit -m "feat: localize OCR language settings"
```

## Task 4: Settings UI Language Checkboxes

**Files:**
- Modify: `Sources/FrameApp/SettingsWindowController.swift`
- Test: `Tests/FrameAppTests/SettingsWindowControllerTests.swift`

- [ ] **Step 1: Write failing Settings UI test**

Add a test that opens Settings and searches labels in the SwiftUI-hosted view:

```swift
func testSettingsWindowShowsOCRLanguageControls() throws {
    let controller = SettingsWindowController()
    controller.show(
        strings: AppStrings(language: .en),
        onShortcutChange: { _ in true },
        onCheckPermission: {},
        onLanguageChange: { _ in },
        onChooseScreenshotDirectory: { nil },
        onResetScreenshotDirectory: {}
    )

    let window = try XCTUnwrap(NSApp.windows.first { $0.title == "Settings" })
    XCTAssertTrue(window.contentView.map { containsText("OCR Languages", in: $0) } ?? false)
    XCTAssertTrue(window.contentView.map { containsText("Simplified Chinese", in: $0) } ?? false)
}
```

Add a recursive helper if needed:

```swift
private func containsText(_ text: String, in view: NSView) -> Bool {
    if let textField = view as? NSTextField, textField.stringValue == text {
        return true
    }

    return view.subviews.contains { containsText(text, in: $0) }
}
```

- [ ] **Step 2: Run test and verify RED**

Run:

```bash
swift test --filter SettingsWindowControllerTests/testSettingsWindowShowsOCRLanguageControls
```

Expected: FAIL because OCR language controls are not shown.

- [ ] **Step 3: Add OCR language checkbox section**

In `GeneralSettingsView`, add state:

```swift
@State private var selectedOCRLanguageIdentifiers = Set(SettingsStore.ocrRecognitionLanguages())
```

Add a form section after app language:

```swift
LabeledContent(strings.settingsOCRLanguages) {
    VStack(alignment: .leading, spacing: 6) {
        ForEach(OCRLanguageOption.allCases) { option in
            Toggle(
                strings.ocrLanguageDisplayName(option),
                isOn: Binding(
                    get: { selectedOCRLanguageIdentifiers.contains(option.rawValue) },
                    set: { isSelected in
                        updateOCRLanguage(option, isSelected: isSelected)
                    }
                )
            )
        }
    }
}
```

Add helper:

```swift
private func updateOCRLanguage(_ option: OCRLanguageOption, isSelected: Bool) {
    if isSelected {
        selectedOCRLanguageIdentifiers.insert(option.rawValue)
    } else {
        selectedOCRLanguageIdentifiers.remove(option.rawValue)
    }

    let validated = SettingsStore.setOCRRecognitionLanguages(
        Array(selectedOCRLanguageIdentifiers),
        defaults: .standard
    )
    selectedOCRLanguageIdentifiers = Set(validated)
}
```

If `setOCRRecognitionLanguages` does not return `[String]` yet, update it to return the persisted validated list and adjust Task 1 tests if needed.

- [ ] **Step 4: Run Settings UI tests and commit**

Run:

```bash
swift test --filter SettingsWindowControllerTests
```

Expected: PASS.

Commit:

```bash
git add Sources/FrameApp/SettingsWindowController.swift Tests/FrameAppTests/SettingsWindowControllerTests.swift Sources/FrameApp/SettingsStore.swift Tests/FrameAppTests/SettingsStoreTests.swift
git commit -m "feat: add OCR language settings UI"
```

## Task 5: Full Verification And Local GUI Handoff

**Files:**
- Modify only if earlier tasks reveal a focused issue.

- [ ] **Step 1: Run full verification**

Run:

```bash
swift test
swift build
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
```

Expected: all pass. Existing `CGWindowListCreateImage` deprecation warnings may appear during release build.

- [ ] **Step 2: Replace local stable-signed app**

Run:

```bash
osascript -e 'tell application "Frame" to quit' >/dev/null 2>&1 || true
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
xattr -dr com.apple.quarantine ~/Applications/Frame.app 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 ~/Applications/Frame.app
codesign -dv --verbose=2 ~/Applications/Frame.app 2>&1 | grep "Authority=Frame Local Dev CLI"
open ~/Applications/Frame.app
```

Expected: codesign verifies and prints `Authority=Frame Local Dev CLI`.

- [ ] **Step 3: Commit any final doc or test adjustment**

If no files changed after verification, skip this commit. Otherwise:

```bash
git status --short
git add <focused-files>
git commit -m "test: stabilize OCR language settings"
```

## Plan Self-Review

- Spec coverage: persistence, default languages, settings UI, OCR request configuration, validation, tests, and stable local GUI handoff are covered.
- Red-flag scan: no forbidden vague implementation steps remain.
- Type consistency: `OCRLanguageOption`, `SettingsStore.ocrRecognitionLanguages`, `SettingsStore.setOCRRecognitionLanguages`, and `configureTextRecognitionRequest(_:recognitionLanguages:)` are used consistently.
