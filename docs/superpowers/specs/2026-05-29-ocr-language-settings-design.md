# OCR Language Settings Design

## Goal

Let users tune Apple Vision OCR languages from Frame settings. The default should work well for Chinese users who commonly capture Chinese, English, Japanese, and Korean text, while still allowing less common languages to be enabled explicitly.

## Product Decisions

- Default OCR languages are Simplified Chinese, Traditional Chinese, English, Japanese, and Korean.
- Users can add or remove OCR languages from Settings.
- The setting applies to future OCR requests only; it does not re-run OCR for panels that are already open.
- Frame must keep at least one OCR language enabled.
- Invalid or obsolete persisted language identifiers fall back safely instead of breaking OCR.
- The UI exposes Vision-supported languages as user-facing names, not raw language identifiers.
- Full-language recognition is available through user selection, but is not the default.

## Scope

This iteration includes:

- A persisted OCR language list in `SettingsStore`.
- A project-owned OCR language option model.
- A Settings UI section for selecting OCR languages.
- OCR request configuration that reads the persisted language list.
- Defaults and validation for empty or invalid persisted values.
- Tests for defaults, persistence, validation, request configuration, and basic Settings UI presentation.

This iteration excludes:

- Automatic language detection before OCR.
- Per-screenshot language selection.
- Per-result language display.
- Downloading or installing language packs.
- Dynamic filtering by current system locale.
- Re-running OCR when the setting changes.

## UX

The Settings > General pane gets an OCR language section below the app language controls or near other OCR-related settings. It uses native checkboxes so users can scan and toggle languages quickly.

The default checked languages are:

- Simplified Chinese
- Traditional Chinese
- English
- Japanese
- Korean

All other supported languages start unchecked. If a user unchecks every language, Frame should immediately restore the default set. This keeps the setting simple and avoids a disabled OCR state.

## Architecture

- Add an `OCRLanguageOption` model in `FrameApp` with:
  - Vision language identifier, such as `zh-Hans`.
  - localized display name from `AppStrings`.
  - default-enabled flag.
- `SettingsStore` owns persistence and validation:
  - store selected identifiers in `UserDefaults`.
  - return default identifiers when no value exists.
  - filter identifiers not present in `OCRLanguageOption.allCases`.
  - return defaults when the persisted set becomes empty after filtering.
- `OCRService` configures `VNRecognizeTextRequest.recognitionLanguages` from `SettingsStore.ocrRecognitionLanguages()`.
- `SettingsWindowController` displays checkboxes and writes changes through `SettingsStore`.

Keep Vision API usage inside `OCRService`. Settings and UI code should deal only in project-owned language identifiers.

## Error Handling

- If persisted languages are missing, empty, or all invalid, use the default language set.
- If users attempt to unselect the final language, restore the default language set.
- If Vision rejects a selected language at runtime, OCR failure follows the existing OCR failure path and keeps the Quick Access preview available.

## Testing Strategy

- `SettingsStoreTests`:
  - returns default OCR languages with empty defaults.
  - persists selected OCR languages.
  - filters invalid persisted identifiers.
  - falls back to defaults when persisted identifiers are empty or invalid.
- `OCRServiceTests`:
  - request configuration uses the provided language list.
  - request configuration falls back through `SettingsStore` defaults when needed.
- `AppStringsTests`:
  - OCR language section and language display strings are localized.
- `SettingsWindowControllerTests`:
  - General settings includes OCR language controls.

## Acceptance Criteria

- New installs recognize Simplified Chinese, Traditional Chinese, English, Japanese, and Korean by default.
- Users can change OCR languages from Settings.
- OCR requests use the selected languages.
- The app never persists or applies an empty OCR language list.
- Invalid stored language identifiers do not break OCR.
- The local GUI test handoff uses the stable `Frame Local Dev CLI` signing flow.

## Open Follow-Ups

- Consider an "All languages" convenience action if the checkbox list feels tedious.
- Consider a search/filter field if Vision exposes many more supported languages later.
- Consider per-screenshot language presets only if users need fast switching.
