# Custom Screenshot Shortcut Design

## Goal

Frame should let users customize the screenshot shortcut from Settings while
keeping the shortcut input safe, simple, and native to macOS.

The first version should replace the fixed preset picker with a shortcut
recording control for the screenshot shortcut row. Users can click the control,
press a valid key combination, and have Frame persist and register it.

## Product Decisions

- The default screenshot shortcut remains `Command+Shift+A`.
- Custom shortcuts are limited to letter and number keys with at least two
  modifier keys from Command, Option, Control, and Shift.
- Single-letter shortcuts, one-modifier shortcuts, function keys, arrows,
  symbols, media keys, and global system-special keys are out of scope.
- Frame does not proactively detect conflicts with macOS or other apps in
  Settings. Duplicate shortcut conflicts are considered acceptable for this
  iteration.
- If Carbon hot key registration fails at runtime, Frame restores the previous
  working shortcut and shows a generic registration failure message. It should
  not classify the failure as a conflict.
- Existing persisted preset values such as `commandShiftA`, `commandShiftS`,
  `commandShiftD`, and `commandShiftF` must migrate to the new shortcut storage.

## Scope

This feature includes:

- A deterministic shortcut value type that stores key code, key label, and
  modifiers.
- Safe shortcut validation for letter and number keys with at least two
  modifiers.
- Backward-compatible persistence for existing preset shortcut values.
- Carbon hot key registration from the custom shortcut value.
- A Settings shortcut recorder row that can enter recording mode, accept valid
  shortcuts, reject invalid shortcuts, and cancel recording with Escape.
- Tests for parsing, validation, persistence migration, display names, and
  registration parameter mapping where deterministic.

This feature excludes:

- Proactive system-wide conflict detection.
- Enumerating or reading macOS keyboard shortcuts from System Settings.
- Multiple shortcuts for the same action.
- Custom shortcuts for recording, OCR, history, or stop-recording commands.
- Import/export or reset-all shortcut management.

## UX Flow

1. User opens Settings.
2. The Screenshot section shows a row labeled `截图快捷键`.
3. The trailing control shows the current shortcut, for example `⌘⇧A`.
4. User clicks the control.
5. The control enters recording mode and shows a short prompt such as
   `按下快捷键`.
6. While recording, modifier and key presses update the control text immediately,
   for example `⌘`, `⌘⇧`, or `⌘A`, so users can see that input is being captured.
7. User presses a key combination.
8. If the combination is invalid, the control stays in recording mode and shows
   a short inline error near the row.
9. If the combination is valid, Settings asks the app layer to apply it.
10. If applying succeeds, the row exits recording mode and shows the new shortcut.
11. If applying fails, the row restores the previous shortcut and shows a
    generic failure state.
12. Pressing Escape exits recording mode without changing the shortcut.

## Validation Rules

A shortcut is valid when all of these are true:

- The key is a Latin letter `A-Z` or number `0-9`.
- At least two modifier keys are pressed.
- At least one of the modifier keys is Command, Option, or Control. This avoids
  accepting combinations that are mostly Shift-only text input.
- The shortcut does not match Frame-reserved shortcuts, currently including the
  reserved recording shortcut `Command+Shift+R`.

Validation should return structured failures so Settings can distinguish
invalid format, insufficient modifiers, and reserved Frame shortcuts.

## Architecture

Use `FrameCore` for deterministic shortcut modeling and validation, and keep
AppKit/Carbon details in `FrameApp`.

- `FrameCore` owns the custom screenshot shortcut value, display formatting,
  persistence encoding/decoding, legacy preset migration, and validation rules.
- `SettingsStore` persists the encoded shortcut string in the existing
  `screenshotShortcut` key, preserving existing user defaults.
- `HotKeyController` registers the selected shortcut through Carbon using the
  value's key code and modifier flags.
- `AppDelegate` remains the boundary that attempts registration, persists on
  success, and rolls back on registration failure.
- `SettingsWindowController` replaces the shortcut Picker with a focused
  shortcut recorder control.

## UI Design

The recorder should look like a compact macOS control, not a large editor:

- Default state: a rounded trailing control showing the current shortcut.
- Recording state: same footprint, focused/accented outline, prompt text, and
  live preview of pressed modifiers or combinations.
- Invalid state: compact inline secondary/error text below or next to the row
  without changing the whole Settings layout.
- Escape cancels recording.
- The control should remain keyboard accessible and expose an accessibility label
  for the current shortcut and recording state.

## Error Handling

- Invalid user input is handled inline and does not call app registration.
- Runtime registration failure restores the previous shortcut and shows the
  existing generic hot key registration alert or an equivalent generic Settings
  row error.
- If migration reads an unknown shortcut string, Frame falls back to
  `Command+Shift+A`.

## Testing Strategy

Core tests:

- Default shortcut is `Command+Shift+A`.
- Legacy preset values migrate to equivalent custom shortcuts.
- Unknown persisted values fall back to default.
- Valid letter and number shortcuts with at least two modifiers are accepted.
- One-modifier shortcuts, non-alphanumeric keys, and reserved shortcuts are
  rejected.
- Display names use compact symbols such as `⌘⇧A`.

App tests:

- Settings store persists and reads the encoded custom shortcut.
- Settings window metrics expose the shortcut recorder behavior instead of the
  preset picker.
- Shortcut recorder updates its visible title for pressed modifiers and invalid
  combinations while recording.
- Hot key registration mapping uses the custom shortcut key code and modifiers.

Manual smoke:

- Open Settings, click the screenshot shortcut recorder, press a valid shortcut,
  close Settings, and confirm the new shortcut starts capture.
- Press Escape while recording and confirm the shortcut does not change.
- Press an invalid one-modifier shortcut and confirm the row rejects it without
  changing the persisted shortcut while still showing the attempted combination.

## Acceptance Criteria

- Users can set a screenshot shortcut using at least two modifiers plus a letter
  or number key.
- Settings rejects invalid shortcuts inline before persistence.
- Existing preset shortcuts continue to load correctly.
- The selected shortcut persists across launches.
- The global screenshot shortcut uses the selected custom shortcut after a
  successful registration.
- Registration failures roll back without losing the previous working shortcut.
- While recording, the control previews the currently pressed modifiers or
  attempted combination before accepting or rejecting it.

## Open Follow-Ups

- Add proactive system or app conflict detection only if duplicate shortcuts
  become a real support issue.
- Consider custom shortcuts for other actions after screenshot shortcut editing
  is stable.
