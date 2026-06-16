# Window Screenshot Original Output Design

## Goal

Frame should let users keep a window screenshot as the original captured window
image instead of always shrinking it onto a styled background canvas.

## User-Facing Behavior

- Settings adds one more option to the existing Window screenshot style picker:
  `Original` / `原图`.
- The default remains `Soft Backdrop` so existing users keep the current styled
  window screenshot behavior unless they choose otherwise.
- When `Original` is selected, double-click window capture outputs the captured
  window image at its original captured size.
- `Original` skips the decoration pipeline: no content downscaling, no filled
  background, no synthesized shadow, no rounded clipping, and no border stroke.
- Region screenshots, fullscreen screenshots, recording, Quick Access, copy,
  save, workspace, OCR, and capture history continue to consume the normal
  `CapturedScreenshot` value and do not need separate user-facing behavior.

## Scope

In scope:

- Add the `Original` style to the persisted window screenshot style model.
- Localize the new picker option in English and Simplified Chinese.
- Route only window captures with `Original` through raw PNG output after the
  existing single-window capture and visible-content crop steps.
- Keep existing decorated styles unchanged.
- Update product and manual testing docs that list window screenshot styles.

Out of scope:

- New style preview UI inside Settings.
- Changing the default style.
- Changing region or fullscreen capture output.
- Changing ScreenCaptureKit or CoreGraphics capture fallback order.

## Architecture

`WindowScreenshotDecorationStyle` becomes the single output-style enum for both
decorated and raw window screenshots. Adding `original` to this enum keeps
Settings persistence, picker rendering, and localized naming on the existing
path.

`CaptureService` continues to own capture selection and platform fallback. After
it obtains and crops a single-window `CGImage`, it reads the selected style:

- `original`: encode the cropped `CGImage` directly through the existing raw
  screenshot helper.
- Decorated styles: keep using `WindowScreenshotDecorator.decoratedScreenshot`.

This keeps all downstream capture consumers unchanged because both paths return
`CapturedScreenshot` with PNG data, `NSImage`, and rect metadata.

## Error Handling

The original output path reuses the existing raw PNG encoding error. Decoration
rendering and PNG encoding errors remain scoped to decorated styles. If
single-window capture fails, the existing fallback behavior stays unchanged.

## Testing

- `SettingsStoreTests` should cover persisting and reading `Original`.
- `AppStringsTests` should cover `Original` / `原图`.
- `CaptureServiceTests` should cover that original window output preserves
  source pixel dimensions and transparent corner/background pixels instead of
  adding a larger canvas.
- Existing decorator tests should keep proving the three decorated styles still
  add or preserve their intended canvas behavior.
- Manual smoke docs should include switching between all four style options and
  confirming `Original` keeps the raw window output while region screenshots
  remain undecorated.

## Acceptance Criteria

- A user can open Settings and select `Original` from Window screenshot style.
- The selected option persists after closing and reopening Settings.
- Window screenshots captured with `Original` are not scaled down and do not have
  an added background canvas.
- The three existing decorated styles keep their current output behavior.
- README, README_ZH, architecture/development docs, tests, build, and packaging
  verification reflect the new option.
