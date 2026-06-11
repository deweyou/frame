# Window Screenshot Decoration Design

## Goal

Frame should decorate window screenshots with a selectable output style while leaving region screenshots, fullscreen screenshots, and recording unchanged.

## User-Facing Behavior

- Window screenshots use a decoration style chosen in Settings.
- The default style is `Soft Backdrop`.
- Settings exposes three names:
  - `Soft Backdrop` / `柔和背景`
  - `Canvas Glow` / `画布光影`
  - `Transparent Shadow` / `透明投影`
- The style names must not mention competitor products.
- Region screenshots and fullscreen screenshots keep the existing raw capture output.
- Recording stays out of scope.

## Style Semantics

- `Soft Backdrop`: a restrained neutral background and a natural window shadow.
- `Canvas Glow`: a richer sharing-oriented background with a stronger shadow.
- `Transparent Shadow`: transparent surrounding canvas plus synthesized shadow, with no filled background.

All styles share identical output geometry for the same source window: same canvas size, same window rect, same padding, and same corner radius. Style switching must not change the apparent window size when comparing screenshots from the same window.

## Architecture

Add a focused `WindowScreenshotDecorator` in `FrameApp`. `CaptureService` continues to own platform capture and calls the decorator only after successful single-window capture. The decorator accepts a `CGImage` plus a `WindowScreenshotDecorationStyle`, renders a new PNG-compatible image, and returns normal `CapturedScreenshot` data so Quick Access, clipboard, save, OCR, workspace preview, and history reuse existing paths.

Settings persistence stays in `SettingsStore`, and `SettingsWindowController` adds a menu picker in the General pane. The setting is read when each window screenshot is captured, so changing it affects subsequent captures without app restart.

## Testing

- Unit test settings default, persistence, and invalid fallback.
- Unit test decorator dimensions, alpha behavior, and style differences with synthetic images.
- Unit test that region/fullscreen capture helpers remain unchanged where practical.
- Run the repository verification commands before handoff.
