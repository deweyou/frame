# Settings, Localization, and Capture Placeholder Design

## Goal

Frame should let users choose where screenshots are saved, avoid showing a `0 x 0` capture HUD before the first selection, and centralize user-facing copy so the app supports Simplified Chinese and English.

## Scope

In scope:

- Add a Settings window reachable from the menu bar app.
- Persist screenshot save location locally.
- Persist language preference locally.
- Support language modes: follow system, Simplified Chinese, English.
- Default to the computer language when language mode is follow system.
- Replace the first-open empty HUD with a centered placeholder hint.
- Centralize current user-facing copy behind one localization boundary.

Out of scope:

- Cloud sync for settings.
- Per-project or per-capture save destinations.
- Runtime translation downloads.
- Full AppKit `.strings` resource migration.
- Recording, OCR, annotation, history, and other non-v0.1 features.

## User Experience

### Settings Window

The menu bar menu gains a Settings item. The settings window uses native AppKit controls and stays compact:

- Save location row:
  - Shows the current screenshot folder path.
  - Defaults to Desktop.
  - Provides a Choose button that opens an `NSOpenPanel` configured for directories only.
  - Provides a Reset button that returns to Desktop.
- Language row:
  - Uses a popup/menu control with Follow System, 中文, and English.
  - Changing the language updates newly opened menus, alerts, panels, and overlay copy.

Settings are persisted in `UserDefaults`. They are local to the Mac and survive app relaunches.

### Save Location Behavior

Quick Access save writes PNG files to the configured screenshot directory. When no custom location is set, or the stored custom location is missing, Frame falls back to Desktop.

If saving fails because the configured folder is unavailable or unwritable, Frame shows a localized failure alert that includes the attempted path and the underlying system error. The stored setting remains unchanged so users can fix permissions or choose a new folder.

### Capture Placeholder

When region capture starts without a previous selection, the overlay dims the screen and shows a centered glass placeholder with concise copy:

- English: `Drag to select an area`
- Simplified Chinese: `拖拽以选择截图区域`

The placeholder is not a selectable region. It disappears as soon as the user starts dragging. The existing selection border, handles, and size HUD appear only after a real selection exists.

When a previous selection exists in the current app session, Frame keeps the current behavior: restore that selection and show the normal HUD.

## Architecture

### Settings Boundary

Add a small settings boundary in `FrameApp`:

- `SettingsStore` owns `UserDefaults` keys, default values, and save directory resolution.
- `SettingsWindowController` owns native settings UI and writes user changes through `SettingsStore`.
- `ScreenshotFileWriter` receives a directory provider or store dependency and writes to the resolved screenshot directory.

The file writer remains the only component that writes PNG files. Settings UI does not perform file output.

### Localization Boundary

Add `AppStrings` in `FrameApp` as the single code-level source for user-facing copy. It exposes typed properties or methods for menu titles, alert titles, button labels, HUD hints, Quick Access actions, log-friendly text, and setting labels.

`AppLanguage` models:

- `system`
- `zhHans`
- `en`

When the setting is `system`, `AppStrings` resolves the active language from `Locale.preferredLanguages`, choosing Simplified Chinese for `zh` language codes and English otherwise.

This code-level string table is intentional for v0.1 because the app is a small SwiftPM AppKit utility. It keeps tests simple and avoids resource packaging churn. A future `.strings` migration can keep the same `AppStrings` API.

### Runtime Refresh

Menu copy should refresh when the language setting changes. Alert copy and overlay copy can resolve strings when they are shown. Existing Quick Access panels can keep the copy they were created with; new panels use the new language.

### Placeholder Boundary

`SelectionOverlayWindow` / `SelectionOverlayView` owns the placeholder because it already owns overlay drawing, HUD visibility, and selection state. `SelectionOverlayController` passes the current strings into windows when capture begins.

The placeholder is purely visual. It must not change `SelectionGeometry`, selected rect validation, or capture confirmation behavior.

## Testing

Unit tests should cover deterministic logic:

- `SettingsStore` defaults to Desktop when no save location is stored.
- `SettingsStore` returns a stored custom save directory.
- `ScreenshotFileWriter` writes to the configured directory rather than always Desktop.
- `AppStrings` resolves Chinese and English copy explicitly.
- `AppStrings` maps follow-system Chinese language identifiers to Simplified Chinese and non-Chinese identifiers to English.

Manual smoke testing should cover AppKit behavior:

- Open Settings from the menu bar.
- Choose a screenshot folder, relaunch Frame, and confirm the path persists.
- Save a screenshot from Quick Access and confirm the file appears in the selected folder.
- Reset save location and confirm future saves return to Desktop.
- Switch language and confirm menus, alerts, settings labels, Quick Access buttons, and capture placeholder use the selected language.
- Start capture with no previous selection and confirm the centered placeholder appears instead of `0 x 0`.
- Start capture after confirming a selection and confirm the previous selection restores with the normal size HUD.

## Durable Decisions

- Settings are local-only and stored in `UserDefaults`.
- Save failures do not silently rewrite the configured directory.
- `AppStrings` is the supported localization boundary for v0.1.
- The initial placeholder is centered and transient; the HUD remains reserved for real selections.
