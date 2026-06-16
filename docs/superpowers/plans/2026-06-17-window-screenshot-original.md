# Window Screenshot Original Output Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `Original` window screenshot style that preserves the captured window image without adding Frame's styled background canvas.

**Architecture:** Extend the existing `WindowScreenshotDecorationStyle` enum so Settings, persistence, localization, and capture routing keep one style model. `CaptureService` branches after single-window capture and visible-content cropping: `original` returns the existing raw PNG path, while the three decorated styles continue through `WindowScreenshotDecorator`.

**Tech Stack:** Swift 6, AppKit, ScreenCaptureKit, XCTest, SwiftPM.

---

## File Structure

- Modify `Sources/FrameApp/WindowScreenshotDecorator.swift`: add `original` to the style enum and make decorator-only switches handle the decorated styles explicitly.
- Modify `Sources/FrameApp/CaptureService.swift`: route `original` to `rawScreenshot(from:rect:scale:)`.
- Modify `Sources/FrameApp/AppStrings.swift`: localize `Original` / `原图`.
- Modify `Tests/FrameAppTests/SettingsStoreTests.swift`: prove the new option persists.
- Modify `Tests/FrameAppTests/AppStringsTests.swift`: prove both localizations expose the picker label.
- Modify `Tests/FrameAppTests/CaptureServiceTests.swift`: prove original output keeps source dimensions and does not add a canvas.
- Modify `Tests/FrameAppTests/SettingsWindowControllerTests.swift`: prove the screenshot style picker exposes four style choices.
- Modify `README.md`, `README_ZH.md`, `docs/architecture.md`, and `docs/development.md`: list the new option and manual smoke expectation.

## Task 1: Add Failing Tests For Original Style Persistence And Copy

**Files:**
- Modify: `Tests/FrameAppTests/SettingsStoreTests.swift`
- Modify: `Tests/FrameAppTests/AppStringsTests.swift`
- Modify: `Tests/FrameAppTests/SettingsWindowControllerTests.swift`

- [ ] **Step 1: Add a failing SettingsStore persistence test**

Add this test below `testWindowScreenshotDecorationStylePersistsExplicitChoice`:

```swift
func testWindowScreenshotDecorationStylePersistsOriginalChoice() {
    SettingsStore.setWindowScreenshotDecorationStyle(.original, defaults: defaults)

    XCTAssertEqual(SettingsStore.windowScreenshotDecorationStyle(defaults: defaults), .original)
}
```

- [ ] **Step 2: Add failing AppStrings assertions**

In `testExplicitEnglishStrings`, after the existing transparent shadow assertion, add:

```swift
XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.original), "Original")
```

In `testExplicitChineseStrings`, after the existing transparent shadow assertion, add:

```swift
XCTAssertEqual(strings.windowScreenshotDecorationStyleName(.original), "原图")
```

- [ ] **Step 3: Add a failing Settings metrics test**

Add this test near the existing Settings screenshot metrics tests:

```swift
func testScreenshotStylePickerIncludesOriginalOutputOption() {
    XCTAssertEqual(WindowScreenshotDecorationStyle.allCases, [
        .softBackdrop,
        .canvasGlow,
        .transparentShadow,
        .original,
    ])
}
```

- [ ] **Step 4: Run tests to verify RED**

Run:

```sh
swift test --filter 'SettingsStoreTests/testWindowScreenshotDecorationStylePersistsOriginalChoice|AppStringsTests/testExplicit|SettingsWindowControllerTests/testScreenshotStylePickerIncludesOriginalOutputOption'
```

Expected: FAIL because `WindowScreenshotDecorationStyle` has no `original` case.

## Task 2: Implement Original Style Model And Localized Name

**Files:**
- Modify: `Sources/FrameApp/WindowScreenshotDecorator.swift`
- Modify: `Sources/FrameApp/AppStrings.swift`

- [ ] **Step 1: Add the enum case**

Change `WindowScreenshotDecorationStyle` to:

```swift
enum WindowScreenshotDecorationStyle: String, CaseIterable, Identifiable {
    case softBackdrop
    case canvasGlow
    case transparentShadow
    case original

    var id: String {
        rawValue
    }

    func displayName(strings: AppStrings) -> String {
        strings.windowScreenshotDecorationStyleName(self)
    }
}
```

- [ ] **Step 2: Add localized names**

In `AppStrings.windowScreenshotDecorationStyleName(_:)`, add:

```swift
case .original:
    switch language {
    case .zhHans: "原图"
    case .en: "Original"
    }
```

- [ ] **Step 3: Keep decorator metric switches exhaustive**

In `WindowScreenshotDecorator.swift`, `drawBackground(style:in:context:)` and `WindowScreenshotDecorationMetrics.init(style:)` should not silently treat `original` as decorated. Add `case .original` branches that return without drawing in `drawBackground`, and use the shared soft-backdrop metrics in `WindowScreenshotDecorationMetrics` only as a defensive fallback for direct decorator calls. Capture routing in Task 4 prevents normal original captures from calling the decorator.

- [ ] **Step 4: Run tests to verify GREEN for style model**

Run:

```sh
swift test --filter 'SettingsStoreTests/testWindowScreenshotDecorationStylePersistsOriginalChoice|AppStringsTests/testExplicit|SettingsWindowControllerTests/testScreenshotStylePickerIncludesOriginalOutputOption'
```

Expected: PASS.

## Task 3: Add Failing Raw Output Test

**Files:**
- Modify: `Tests/FrameAppTests/CaptureServiceTests.swift`
- Modify: `Sources/FrameApp/CaptureService.swift`

- [ ] **Step 1: Write the desired raw output test**

Add this test to `CaptureServiceTests` after the transparent shadow test:

```swift
func testOriginalWindowScreenshotKeepsSourcePixelsWithoutCanvas() throws {
    let sourceImage = try makeImageWithTransparentMargins()
    let screenshot = try makeWindowScreenshotForTesting(
        from: sourceImage,
        rect: CGRect(x: 10, y: 20, width: 10, height: 8),
        scale: 1,
        style: .original
    )
    let outputImage = try XCTUnwrap(screenshot.image.cgImage(forProposedRect: nil, context: nil, hints: nil))

    XCTAssertEqual(outputImage.width, sourceImage.width)
    XCTAssertEqual(outputImage.height, sourceImage.height)
    XCTAssertEqual(screenshot.image.size, CGSize(width: 10, height: 8))
    XCTAssertEqual(screenshot.rect, CGRect(x: 10, y: 20, width: 10, height: 8))
    XCTAssertEqual(try pixel(at: CGPoint(x: 0, y: 0), in: outputImage).alpha, 0)
}
```

- [ ] **Step 2: Run test to verify the desired API is missing**

Run:

```sh
swift test --filter CaptureServiceTests/testOriginalWindowScreenshotKeepsSourcePixelsWithoutCanvas
```

Expected: FAIL to compile because `makeWindowScreenshotForTesting` does not
exist yet. This proves the test describes the intended behavior through a small
capture-output seam that the implementation must provide.

- [ ] **Step 3: Add the minimal test seam and deliberately wrong behavior**

Expose a nonisolated helper in `CaptureService.swift` near `makeSingleWindowCaptureConfiguration`:

```swift
func makeWindowScreenshotForTesting(
    from cgImage: CGImage,
    rect: CGRect,
    scale: CGFloat,
    style: WindowScreenshotDecorationStyle
) throws -> CapturedScreenshot {
    try CaptureService.makeWindowScreenshot(
        from: cgImage,
        rect: rect,
        scale: scale,
        style: style,
        decorator: WindowScreenshotDecorator()
    )
}
```

Also add a private static helper on `CaptureService` that initially delegates to the decorated path for every style:

```swift
private static func makeWindowScreenshot(
    from cgImage: CGImage,
    rect: CGRect,
    scale: CGFloat,
    style: WindowScreenshotDecorationStyle,
    decorator: WindowScreenshotDecorator
) throws -> CapturedScreenshot {
    try decorator.decoratedScreenshot(
        from: cgImage,
        sourceRect: rect,
        scale: scale,
        style: style
    )
}
```

- [ ] **Step 4: Run test to verify behavior RED**

Run:

```sh
swift test --filter CaptureServiceTests/testOriginalWindowScreenshotKeepsSourcePixelsWithoutCanvas
```

Expected: FAIL because `.original` still produces a larger decorated canvas.

## Task 4: Route Original Captures To Raw PNG Output

**Files:**
- Modify: `Sources/FrameApp/CaptureService.swift`
- Modify: `Tests/FrameAppTests/CaptureServiceTests.swift`

- [ ] **Step 1: Implement raw helper reuse**

Move the body of `rawScreenshot(from:rect:scale:)` into a static helper:

```swift
private static func rawScreenshot(from cgImage: CGImage, rect: CGRect, scale: CGFloat) throws -> CapturedScreenshot {
    let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
    guard let pngData = bitmapRepresentation.representation(
        using: .png,
        properties: [:]
    ) else {
        throw CaptureServiceError.pngEncodingFailed
    }

    let imageScale = max(scale, 1)
    let imageSize = CGSize(
        width: CGFloat(cgImage.width) / imageScale,
        height: CGFloat(cgImage.height) / imageScale
    )
    let image = NSImage(cgImage: cgImage, size: imageSize)
    return CapturedScreenshot(pngData: pngData, image: image, rect: CGRect(origin: rect.origin, size: imageSize))
}
```

Keep the existing instance method as:

```swift
private func rawScreenshot(from cgImage: CGImage, rect: CGRect, scale: CGFloat) throws -> CapturedScreenshot {
    try Self.rawScreenshot(from: cgImage, rect: rect, scale: scale)
}
```

- [ ] **Step 2: Route `original` in the shared helper**

Change `makeWindowScreenshot` to:

```swift
private static func makeWindowScreenshot(
    from cgImage: CGImage,
    rect: CGRect,
    scale: CGFloat,
    style: WindowScreenshotDecorationStyle,
    decorator: WindowScreenshotDecorator
) throws -> CapturedScreenshot {
    switch style {
    case .original:
        return try rawScreenshot(from: cgImage, rect: rect, scale: scale)
    case .softBackdrop, .canvasGlow, .transparentShadow:
        return try decorator.decoratedScreenshot(
            from: cgImage,
            sourceRect: rect,
            scale: scale,
            style: style
        )
    }
}
```

- [ ] **Step 3: Use the helper from window capture**

Change `screenshot(from:rect:scale:)` to:

```swift
private func screenshot(from cgImage: CGImage, rect: CGRect, scale: CGFloat) throws -> CapturedScreenshot {
    try Self.makeWindowScreenshot(
        from: cgImage,
        rect: rect,
        scale: scale,
        style: windowScreenshotDecorationStyle(),
        decorator: windowScreenshotDecorator
    )
}
```

- [ ] **Step 4: Run CaptureServiceTests**

Run:

```sh
swift test --filter CaptureServiceTests
```

Expected: PASS.

## Task 5: Update Product Docs And Manual Smoke Checks

**Files:**
- Modify: `README.md`
- Modify: `README_ZH.md`
- Modify: `docs/architecture.md`
- Modify: `docs/development.md`

- [ ] **Step 1: Update README window capture language**

In `README.md`, change the window capture bullet to mention styled or original output:

```markdown
- Window capture: double-click an eligible app window to capture either a styled window screenshot or the original window image, configurable in Settings.
```

Change the style list bullet to:

```markdown
- Window screenshot styles: choose Soft Backdrop, Canvas Glow, Transparent Shadow, or Original for window captures.
```

- [ ] **Step 2: Update README_ZH window capture language**

In `README_ZH.md`, change the matching bullets to:

```markdown
- 窗口截图：双击可捕获的应用窗口，输出带样式的窗口截图或原始窗口图片，并可在设置中选择样式。
```

```markdown
- 窗口截图样式：窗口截图可选择柔和背景、画布光影、透明投影或原图。
```

- [ ] **Step 3: Update architecture tradeoff docs**

In `docs/architecture.md`, update the `CaptureService` runtime description so it says window captures pass through `WindowScreenshotDecorator` unless the selected style is Original.

Update the Current Tradeoffs window-capture bullet so it lists `Original` and explains it skips decoration after visible-content cropping.

- [ ] **Step 4: Update manual smoke checks**

In `docs/development.md`, update smoke step 8 to list all four options and step 22 to confirm Original keeps raw output while region screenshots remain undecorated.

## Task 6: Full Verification And Handoff

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run targeted tests**

Run:

```sh
swift test --filter 'SettingsStoreTests/testWindowScreenshotDecorationStyle|AppStringsTests/testExplicit|SettingsWindowControllerTests/testScreenshotStylePickerIncludesOriginalOutputOption|CaptureServiceTests'
```

Expected: PASS.

- [ ] **Step 2: Run repository verification**

Run:

```sh
swift test
swift build
scripts/package-app.sh
```

Expected: all commands pass and `.build/app/Frame.app` is created.

- [ ] **Step 3: Inspect final diff**

Run:

```sh
git diff --stat
git diff --check
```

Expected: only task-related files changed; `git diff --check` reports no whitespace errors.

- [ ] **Step 4: Final handoff**

Report:

- Flow used: full spec flow with TDD.
- Spec and plan paths.
- Tests added.
- Verification commands and results.
- Ask whether to replace the local test app, because this is a GUI-facing change.
