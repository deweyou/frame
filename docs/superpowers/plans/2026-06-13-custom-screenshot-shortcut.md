# Custom Screenshot Shortcut Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users record and persist a custom screenshot shortcut from Settings without proactive system conflict detection.

**Architecture:** `FrameCore` owns a deterministic `ScreenshotShortcut` value object, validation, display formatting, persistence encoding, and legacy preset migration. `FrameApp` maps valid shortcuts to Carbon registration parameters and presents a compact native recorder control in the Screenshot settings row.

**Tech Stack:** Swift, SwiftUI, AppKit, Carbon hot keys, XCTest.

---

## File Structure

- Modify `Sources/FrameCore/KeyboardShortcut.swift`: replace the preset-only `ScreenshotShortcut` enum with a value type that supports letters/numbers, modifier sets, validation, display names, and legacy migration.
- Modify `Sources/FrameApp/SettingsStore.swift`: keep the existing `screenshotShortcut` key and persist the new encoded shortcut string.
- Modify `Sources/FrameApp/HotKeyController.swift`: register key code and Carbon modifier flags from the custom shortcut value.
- Modify `Sources/FrameApp/AppDelegate.swift`: keep rollback behavior and log/display the custom shortcut display name.
- Modify `Sources/FrameApp/AppStrings.swift`: add compact recorder prompt/error strings in Chinese and English.
- Modify `Sources/FrameApp/SettingsWindowController.swift`: replace the shortcut picker with a focused shortcut recorder SwiftUI/AppKit bridge.
- Modify `Tests/FrameCoreTests/FrameCoreTests.swift`: add validation, display, persistence, and legacy migration tests.
- Modify `Tests/FrameAppTests/SettingsStoreTests.swift`: add persistence/migration tests through `SettingsStore`.
- Modify `Tests/FrameAppTests/SettingsWindowControllerTests.swift`: assert recorder metrics and remove preset-picker expectations.
- Add or modify `Tests/FrameAppTests/HotKeyControllerTests.swift`: test deterministic Carbon mapping without registering a real global hot key.
- Modify `DESIGN.md`: record that screenshot shortcut editing uses an inline recorder and does not proactively inspect system conflicts.

## Task 1: Core Shortcut Model

**Files:**
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`
- Modify: `Sources/FrameCore/KeyboardShortcut.swift`

- [x] **Step 1: Write failing core tests**

Add focused tests near the existing shortcut tests:

```swift
func testScreenshotShortcutDefaultsToCommandShiftA() {
    XCTAssertEqual(ScreenshotShortcut.default.key, .letter("A"))
    XCTAssertEqual(ScreenshotShortcut.default.modifiers, [.command, .shift])
    XCTAssertEqual(ScreenshotShortcut.default.displayName, "⌘⇧A")
    XCTAssertEqual(ScreenshotShortcut.default.storageValue, "cmd+shift+a")
}

func testScreenshotShortcutMigratesLegacyPresetStorage() {
    XCTAssertEqual(ScreenshotShortcut.persistedValue(for: "commandShiftS"), .init(key: .letter("S"), modifiers: [.command, .shift]))
    XCTAssertEqual(ScreenshotShortcut.persistedValue(for: "commandShiftD"), .init(key: .letter("D"), modifiers: [.command, .shift]))
    XCTAssertEqual(ScreenshotShortcut.persistedValue(for: "commandShiftF"), .init(key: .letter("F"), modifiers: [.command, .shift]))
}

func testScreenshotShortcutFallsBackForUnknownStorage() {
    XCTAssertEqual(ScreenshotShortcut.persistedValue(for: nil), .default)
    XCTAssertEqual(ScreenshotShortcut.persistedValue(for: "unknown"), .default)
}

func testScreenshotShortcutAcceptsLettersAndNumbersWithTwoModifiers() {
    XCTAssertEqual(
        ScreenshotShortcut.validate(key: .letter("Z"), modifiers: [.command, .option]),
        .valid(.init(key: .letter("Z"), modifiers: [.command, .option]))
    )
    XCTAssertEqual(
        ScreenshotShortcut.validate(key: .number("7"), modifiers: [.control, .shift]),
        .valid(.init(key: .number("7"), modifiers: [.control, .shift]))
    )
}

func testScreenshotShortcutRejectsUnsafeCombinations() {
    XCTAssertEqual(ScreenshotShortcut.validate(key: .letter("A"), modifiers: [.command]), .invalid(.insufficientModifiers))
    XCTAssertEqual(ScreenshotShortcut.validate(key: .letter("A"), modifiers: [.shift]), .invalid(.insufficientModifiers))
    XCTAssertEqual(ScreenshotShortcut.validate(key: .unsupported, modifiers: [.command, .shift]), .invalid(.unsupportedKey))
    XCTAssertEqual(ScreenshotShortcut.validate(key: .letter("R"), modifiers: [.command, .shift]), .invalid(.reservedShortcut))
}
```

- [x] **Step 2: Run RED**

Run:

```bash
swift test --filter 'FrameCoreTests/testScreenshotShortcut'
```

Expected: FAIL because `ScreenshotShortcut` is still a preset enum and does not expose the new API.

- [x] **Step 3: Implement value type**

Replace preset-only behavior with:

```swift
public enum ScreenshotShortcutModifier: String, CaseIterable, Sendable {
    case command = "cmd"
    case option
    case control
    case shift

    public var symbol: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
}

public enum ScreenshotShortcutKey: Equatable, Sendable {
    case letter(String)
    case number(String)
    case unsupported
}

public enum ScreenshotShortcutValidationFailure: Equatable, Sendable {
    case unsupportedKey
    case insufficientModifiers
    case reservedShortcut
}

public enum ScreenshotShortcutValidationResult: Equatable, Sendable {
    case valid(ScreenshotShortcut)
    case invalid(ScreenshotShortcutValidationFailure)
}

public struct ScreenshotShortcut: Equatable, Hashable, Sendable {
    public let key: ScreenshotShortcutKey
    public let modifiers: Set<ScreenshotShortcutModifier>

    public init(key: ScreenshotShortcutKey, modifiers: Set<ScreenshotShortcutModifier>) {
        self.key = key
        self.modifiers = modifiers
    }
}
```

Add deterministic `default`, `displayName`, `storageValue`, `persistedValue(for:)`, legacy migration, and `validate(key:modifiers:)` following the spec. Preserve `KeyboardShortcut.defaultScreenshot` / `.defaultRecording` for existing recording hint code.

- [x] **Step 4: Run GREEN**

Run:

```bash
swift test --filter 'FrameCoreTests/testScreenshotShortcut'
```

Expected: PASS.

## Task 2: Persistence And Carbon Mapping

**Files:**
- Modify: `Tests/FrameAppTests/SettingsStoreTests.swift`
- Create or modify: `Tests/FrameAppTests/HotKeyControllerTests.swift`
- Modify: `Sources/FrameApp/SettingsStore.swift`
- Modify: `Sources/FrameApp/HotKeyController.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [x] **Step 1: Write failing app tests**

Add settings store tests:

```swift
func testScreenshotShortcutPersistsCustomStorageValue() {
    let shortcut = ScreenshotShortcut(key: .number("7"), modifiers: [.command, .option])

    SettingsStore.setScreenshotShortcut(shortcut, defaults: defaults)

    XCTAssertEqual(defaults.string(forKey: SettingsStore.screenshotShortcutKey), "cmd+option+7")
    XCTAssertEqual(SettingsStore.screenshotShortcut(defaults: defaults), shortcut)
}

func testScreenshotShortcutReadsLegacyPresetValue() {
    defaults.set("commandShiftS", forKey: SettingsStore.screenshotShortcutKey)

    XCTAssertEqual(
        SettingsStore.screenshotShortcut(defaults: defaults),
        ScreenshotShortcut(key: .letter("S"), modifiers: [.command, .shift])
    )
}
```

Add HotKey mapping tests:

```swift
@MainActor
final class HotKeyControllerTests: XCTestCase {
    func testRegistrationParametersMapCustomShortcutToCarbonValues() {
        let shortcut = ScreenshotShortcut(key: .letter("Z"), modifiers: [.command, .option, .shift])

        let parameters = HotKeyController.registrationParameters(for: shortcut)

        XCTAssertEqual(parameters.keyCode, kVK_ANSI_Z)
        XCTAssertEqual(parameters.modifierFlags, UInt32(cmdKey | optionKey | shiftKey))
    }
}
```

- [x] **Step 2: Run RED**

Run:

```bash
swift test --filter 'SettingsStoreTests/testScreenshotShortcut'
swift test --filter 'HotKeyControllerTests'
```

Expected: FAIL because persistence still writes legacy raw enum values and HotKey mapping is private preset-only behavior.

- [x] **Step 3: Implement persistence and mapping**

Change `SettingsStore.setScreenshotShortcut` to persist `shortcut.storageValue`. Add `HotKeyController.RegistrationParameters` and `static func registrationParameters(for:)` so tests can verify mapping without registering global shortcuts. Use those parameters in `RegisterEventHotKey`.

Update `HotKeyRegistrationError.registerHotKeyFailed` to include the attempted `ScreenshotShortcut` display name so the error is generic but accurate:

```swift
case registerHotKeyFailed(OSStatus, ScreenshotShortcut)
```

Update `AppDelegate.changeScreenshotShortcut(to:)` logging to `shortcut.displayName`.

- [x] **Step 4: Run GREEN**

Run:

```bash
swift test --filter 'SettingsStoreTests/testScreenshotShortcut'
swift test --filter 'HotKeyControllerTests'
```

Expected: PASS.

## Task 3: Settings Recorder UI

**Files:**
- Modify: `Tests/FrameAppTests/AppStringsTests.swift`
- Modify: `Tests/FrameAppTests/SettingsWindowControllerTests.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`
- Modify: `Sources/FrameApp/SettingsWindowController.swift`

- [x] **Step 1: Write failing UI contract tests**

Add strings tests for recorder prompt/errors:

```swift
func testShortcutRecorderStringsAreLocalized() {
    let zh = AppStrings(language: .zhHans)
    XCTAssertEqual(zh.settingsShortcutRecorderPrompt, "按下快捷键")
    XCTAssertEqual(zh.settingsShortcutRecorderInsufficientModifiers, "请按下至少两个修饰键")
    XCTAssertEqual(zh.settingsShortcutRecorderUnsupportedKey, "只支持字母或数字")
    XCTAssertEqual(zh.settingsShortcutRecorderReservedShortcut, "这个快捷键已由 Frame 保留")

    let en = AppStrings(language: .en)
    XCTAssertEqual(en.settingsShortcutRecorderPrompt, "Press shortcut")
    XCTAssertEqual(en.settingsShortcutRecorderInsufficientModifiers, "Use at least two modifier keys")
    XCTAssertEqual(en.settingsShortcutRecorderUnsupportedKey, "Use a letter or number key")
    XCTAssertEqual(en.settingsShortcutRecorderReservedShortcut, "This shortcut is reserved by Frame")
}
```

Add settings metrics test:

```swift
func testScreenshotShortcutSettingsUseInlineRecorder() {
    XCTAssertTrue(SettingsShortcutRecorderMetrics.usesInlineRecorder)
    XCTAssertEqual(SettingsShortcutRecorderMetrics.width, 118, accuracy: 0.5)
    XCTAssertEqual(SettingsShortcutRecorderMetrics.minHeight, 28, accuracy: 0.5)
    XCTAssertEqual(SettingsShortcutRecorderMetrics.cornerRadius, 7, accuracy: 0.5)
}
```

- [x] **Step 2: Run RED**

Run:

```bash
swift test --filter 'AppStringsTests/testShortcutRecorderStringsAreLocalized'
swift test --filter 'SettingsWindowControllerTests/testScreenshotShortcutSettingsUseInlineRecorder'
```

Expected: FAIL because the recorder strings and metrics do not exist.

- [x] **Step 3: Implement recorder strings and metrics**

Add localized `AppStrings` properties for the prompt and each validation failure. Add:

```swift
enum SettingsShortcutRecorderMetrics {
    static let usesInlineRecorder = true
    static let width: CGFloat = 118
    static let minHeight: CGFloat = 28
    static let cornerRadius: CGFloat = 7
}
```

- [x] **Step 4: Implement recorder view**

Replace the screenshot shortcut picker with:

```swift
SettingsControlRow(strings.settingsScreenshotShortcut, verticalAlignment: .top, verticalPadding: 5) {
    VStack(alignment: .trailing, spacing: 5) {
        ShortcutRecorderControl(
            strings: strings,
            shortcut: selectedShortcut,
            onShortcutChange: changeShortcut
        )

        if let shortcutErrorText {
            Text(shortcutErrorText)
                .font(.system(size: SettingsTypographyMetrics.secondaryFontSize))
                .foregroundStyle(.red)
        }
    }
}
```

Implement `ShortcutRecorderControl` as an `NSViewRepresentable` wrapping a focused `NSButton`/custom `NSView` that captures `keyDown`, enters recording on click, cancels with Escape, validates with `ScreenshotShortcut.validate`, and calls `onShortcutChange` only for `.valid`.

- [x] **Step 5: Run GREEN**

Run:

```bash
swift test --filter 'AppStringsTests/testShortcutRecorderStringsAreLocalized'
swift test --filter 'SettingsWindowControllerTests/testScreenshotShortcutSettingsUseInlineRecorder'
```

Expected: PASS.

## Task 4: Documentation And Full Verification

**Files:**
- Modify: `DESIGN.md`
- Check: `README.md`
- Check: `README_ZH.md`

- [x] **Step 1: Update durable design note**

Add to the Settings section in `DESIGN.md`:

```markdown
- Screenshot shortcut editing uses a compact inline recorder in the screenshot
  row. Validate simple local format rules before applying, but do not
  proactively inspect system-wide shortcut conflicts.
```

- [x] **Step 2: Check README scope**

Run:

```bash
rg -n "settings|shortcut|快捷键|截图快捷键" README.md README_ZH.md
```

Expected: no README update unless the current overview claims fixed-only shortcut behavior.

- [x] **Step 3: Run required verification**

Run:

```bash
swift test
swift build
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
mkdir -p ~/Applications
rm -rf ~/Applications/Frame.app
ditto .build/app/Frame.app ~/Applications/Frame.app
open ~/Applications/Frame.app
codesign -dv --verbose=2 ~/Applications/Frame.app
```

Expected: tests/build/package pass, and codesign output includes `Authority=Frame Local Dev CLI`.

## Self-Review

- Spec coverage: Tasks cover custom value modeling, validation, legacy migration, persistence, Carbon mapping, inline recorder UX, no proactive conflict detection, and rollback-preserving app behavior.
- Placeholder scan: No forbidden placeholder markers remain in implementation steps.
- Type consistency: Plan consistently uses `ScreenshotShortcut`, `ScreenshotShortcutKey`, `ScreenshotShortcutModifier`, `ScreenshotShortcutValidationResult`, and `SettingsShortcutRecorderMetrics`.
