# OCR Scrub Selection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the plain OCR text panel with a WeChat-style scrub-selection panel that shows the screenshot, renders selectable text cuts, and copies only selected cuts.

**Architecture:** `FrameCore` owns OCR cut tokenization, row ordering, and selected-text formatting. `FrameApp` keeps Vision recognition in `OCRService`, renders the AppKit scrub panel in `OCRTextPanelController`, and keeps clipboard/status ownership in `AppDelegate`. The first version derives cuts from recognized lines and can later attach per-range Vision bounds for image-overlay selection.

**Tech Stack:** Swift, AppKit, Swift Testing, XCTest, Apple Vision, existing `FrameCore`/`FrameApp` package layout.

---

## File Structure

- Create `Sources/FrameCore/RecognizedTextCutLayout.swift`
  - Owns `RecognizedTextCut`, `RecognizedTextCutRow`, `RecognizedTextCutLayout`, tokenizer, deterministic selected-text formatting, and cut selection helpers.
- Modify `Tests/FrameCoreTests/FrameCoreTests.swift`
  - Adds tokenizer and selected-text formatting tests.
- Modify `Sources/FrameApp/OCRTextPanelController.swift`
  - Replaces the `NSTextView` content with screenshot preview, cut grid, select-all button, and copy-selected button.
- Modify `Tests/FrameAppTests/OCRTextPanelControllerTests.swift`
  - Updates existing text-panel tests to assert preview/cut controls, select-all behavior, copy-selected routing, panel reuse, and close behavior.
- Modify `Sources/FrameApp/AppDelegate.swift`
  - Changes OCR panel callback from `copyAll` to `copyText`, so both Quick Access OCR and HUD OCR copy the selected text supplied by the panel.
- Modify `Sources/FrameApp/AppStrings.swift` and `Tests/FrameAppTests/AppStringsTests.swift`
  - Adds localized labels for select all and copy selected.

---

### Task 1: Core OCR Cut Model

**Files:**
- Create: `Sources/FrameCore/RecognizedTextCutLayout.swift`
- Modify: `Tests/FrameCoreTests/FrameCoreTests.swift`

- [ ] **Step 1: Write failing tokenizer and formatting tests**

Append these tests to `Tests/FrameCoreTests/FrameCoreTests.swift` inside `FrameCoreTests`:

```swift
@Test
func testRecognizedTextCutLayoutTokenizesCJKCharactersAndLatinRuns() {
    let layout = RecognizedTextCutLayout(
        textLayout: RecognizedTextLayout(lines: [
            RecognizedTextLine(
                text: "为什么 ListV4/tanstack 全量",
                bounds: NormalizedImageRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
                confidence: 0.9
            ),
        ])
    )

    #expect(layout.rows.count == 1)
    #expect(layout.rows[0].cuts.map(\.text) == ["为", "什", "么", "ListV4/tanstack", "全", "量"])
}
```

Add selected text ordering coverage:

```swift
@Test
func testRecognizedTextCutLayoutCopiesSelectedCutsInVisualOrder() {
    let layout = RecognizedTextCutLayout(
        textLayout: RecognizedTextLayout(lines: [
            RecognizedTextLine(
                text: "第二行",
                bounds: NormalizedImageRect(x: 0.1, y: 0.4, width: 0.4, height: 0.1),
                confidence: nil
            ),
            RecognizedTextLine(
                text: "Hello world",
                bounds: NormalizedImageRect(x: 0.1, y: 0.7, width: 0.4, height: 0.1),
                confidence: nil
            ),
        ])
    )

    let selected = Set(layout.rows.flatMap(\.cuts).map(\.id).filter { id in
        layout.cut(for: id)?.text != "world"
    })

    #expect(layout.selectedText(for: selected) == "Hello\n第二行")
}
```

Add fallback coverage:

```swift
@Test
func testRecognizedTextCutLayoutFallsBackToLineCutWhenTokenizerDropsEverything() {
    let layout = RecognizedTextCutLayout(
        textLayout: RecognizedTextLayout(lines: [
            RecognizedTextLine(
                text: "   ",
                bounds: NormalizedImageRect(x: 0, y: 0, width: 1, height: 0.1),
                confidence: nil
            ),
            RecognizedTextLine(
                text: "visible",
                bounds: NormalizedImageRect(x: 0, y: 0.5, width: 1, height: 0.1),
                confidence: nil
            ),
        ])
    )

    #expect(layout.rows.count == 1)
    #expect(layout.rows[0].cuts.map(\.text) == ["visible"])
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
swift test --filter FrameCoreTests/testRecognizedTextCutLayout
```

Expected: FAIL because `RecognizedTextCutLayout` is not defined.

- [ ] **Step 3: Implement the cut model**

Create `Sources/FrameCore/RecognizedTextCutLayout.swift`:

```swift
import Foundation

public struct RecognizedTextCut: Identifiable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let text: String
    public let lineIndex: Int
    public let tokenIndex: Int
    public let bounds: NormalizedImageRect
    public let needsLeadingSpace: Bool

    public init(
        id: UUID = UUID(),
        text: String,
        lineIndex: Int,
        tokenIndex: Int,
        bounds: NormalizedImageRect,
        needsLeadingSpace: Bool
    ) {
        self.id = id
        self.text = text
        self.lineIndex = lineIndex
        self.tokenIndex = tokenIndex
        self.bounds = bounds
        self.needsLeadingSpace = needsLeadingSpace
    }
}

public struct RecognizedTextCutRow: Equatable, Sendable {
    public let lineIndex: Int
    public let cuts: [RecognizedTextCut]

    public init(lineIndex: Int, cuts: [RecognizedTextCut]) {
        self.lineIndex = lineIndex
        self.cuts = cuts
    }
}

public struct RecognizedTextCutLayout: Equatable, Sendable {
    public let rows: [RecognizedTextCutRow]

    public init(textLayout: RecognizedTextLayout) {
        var rows: [RecognizedTextCutRow] = []

        for (lineIndex, line) in textLayout.lines.enumerated() {
            let cuts = Self.tokenize(line.text, lineIndex: lineIndex, lineBounds: line.bounds)
            if !cuts.isEmpty {
                rows.append(RecognizedTextCutRow(lineIndex: lineIndex, cuts: cuts))
            }
        }

        self.rows = rows
    }

    public var allCutIDs: Set<UUID> {
        Set(rows.flatMap(\.cuts).map(\.id))
    }

    public func cut(for id: UUID) -> RecognizedTextCut? {
        rows.flatMap(\.cuts).first { $0.id == id }
    }

    public func selectedText(for selectedIDs: Set<UUID>) -> String {
        rows.compactMap { row -> String? in
            var text = ""
            for cut in row.cuts where selectedIDs.contains(cut.id) {
                if cut.needsLeadingSpace, !text.isEmpty {
                    text.append(" ")
                }
                text.append(cut.text)
            }
            return text.isEmpty ? nil : text
        }
        .joined(separator: "\n")
    }

    private static func tokenize(
        _ text: String,
        lineIndex: Int,
        lineBounds: NormalizedImageRect
    ) -> [RecognizedTextCut] {
        var cuts: [RecognizedTextCut] = []
        var token = ""
        var tokenNeedsLeadingSpace = false
        var sawWhitespaceBeforeToken = false

        func flushToken() {
            guard !token.isEmpty else {
                return
            }

            cuts.append(RecognizedTextCut(
                text: token,
                lineIndex: lineIndex,
                tokenIndex: cuts.count,
                bounds: lineBounds,
                needsLeadingSpace: tokenNeedsLeadingSpace
            ))
            token = ""
            tokenNeedsLeadingSpace = false
        }

        for scalar in text.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                flushToken()
                sawWhitespaceBeforeToken = true
                continue
            }

            let character = String(Character(scalar))
            if isCJK(scalar) {
                flushToken()
                cuts.append(RecognizedTextCut(
                    text: character,
                    lineIndex: lineIndex,
                    tokenIndex: cuts.count,
                    bounds: lineBounds,
                    needsLeadingSpace: sawWhitespaceBeforeToken && !cuts.isEmpty
                ))
                sawWhitespaceBeforeToken = false
            } else if isWordLike(scalar) {
                if token.isEmpty {
                    tokenNeedsLeadingSpace = sawWhitespaceBeforeToken && !cuts.isEmpty
                }
                token.append(character)
                sawWhitespaceBeforeToken = false
            } else if isCodeJoiner(scalar), !token.isEmpty {
                token.append(character)
                sawWhitespaceBeforeToken = false
            } else {
                flushToken()
                cuts.append(RecognizedTextCut(
                    text: character,
                    lineIndex: lineIndex,
                    tokenIndex: cuts.count,
                    bounds: lineBounds,
                    needsLeadingSpace: sawWhitespaceBeforeToken && !cuts.isEmpty
                ))
                sawWhitespaceBeforeToken = false
            }
        }

        flushToken()
        return cuts
    }

    private static func isWordLike(_ scalar: UnicodeScalar) -> Bool {
        CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
    }

    private static func isCodeJoiner(_ scalar: UnicodeScalar) -> Bool {
        scalar == "/" || scalar == "." || scalar == "@"
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x9FFF, 0x3040...0x30FF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }
}
```

- [ ] **Step 4: Run core tests**

Run:

```bash
swift test --filter FrameCoreTests/testRecognizedTextCutLayout
```

Expected: PASS for the new cut layout tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/FrameCore/RecognizedTextCutLayout.swift Tests/FrameCoreTests/FrameCoreTests.swift
git commit -m "feat: add OCR cut layout model"
```

---

### Task 2: OCR Panel Strings and Callback Shape

**Files:**
- Modify: `Sources/FrameApp/AppStrings.swift`
- Modify: `Tests/FrameAppTests/AppStringsTests.swift`
- Modify: `Sources/FrameApp/AppDelegate.swift`

- [ ] **Step 1: Write failing string tests**

Append to `Tests/FrameAppTests/AppStringsTests.swift`:

```swift
func testOCRScrubSelectionStringsAreLocalized() {
    let english = AppStrings(language: .en)
    XCTAssertEqual(english.ocrSelectAll, "Select All")
    XCTAssertEqual(english.ocrCopySelected, "Copy Selected")

    let chinese = AppStrings(language: .zhHans)
    XCTAssertEqual(chinese.ocrSelectAll, "全选")
    XCTAssertEqual(chinese.ocrCopySelected, "复制")
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter AppStringsTests/testOCRScrubSelectionStringsAreLocalized
```

Expected: FAIL because `ocrSelectAll` and `ocrCopySelected` are not defined.

- [ ] **Step 3: Add strings**

Add these properties to `Sources/FrameApp/AppStrings.swift` near the existing OCR strings:

```swift
var ocrSelectAll: String {
    switch language {
    case .zhHans: "全选"
    case .en: "Select All"
    }
}

var ocrCopySelected: String {
    switch language {
    case .zhHans: "复制"
    case .en: "Copy Selected"
    }
}
```

- [ ] **Step 4: Change AppDelegate copy callback shape**

Modify `showOCRPanel` in `Sources/FrameApp/AppDelegate.swift` so the panel supplies text:

```swift
private func showOCRPanel(_ layout: RecognizedTextLayout, for screenshot: CapturedScreenshot) {
    ocrTextPanelController.show(
        layout: layout,
        for: screenshot,
        strings: strings,
        copyText: { [weak self] text in
            guard let self,
                  self.copyRecognizedText(text) else {
                return false
            }

            self.quickAccessPanelController.setOCRStatus(
                .message(self.strings.ocrCopied, resetAfter: 1.4),
                for: screenshot
            )
            return true
        }
    )
}
```

Expected after this step: build fails until `OCRTextPanelController.show` accepts `copyText`.

- [ ] **Step 5: Commit after Task 3 updates the panel signature**

Do not commit this task alone if the package does not compile. Commit it together with Task 3 if necessary:

```bash
git add Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/AppStringsTests.swift Sources/FrameApp/AppDelegate.swift Sources/FrameApp/OCRTextPanelController.swift Tests/FrameAppTests/OCRTextPanelControllerTests.swift
git commit -m "feat: add OCR scrub panel actions"
```

---

### Task 3: Scrub Selection Panel UI

**Files:**
- Modify: `Sources/FrameApp/OCRTextPanelController.swift`
- Modify: `Tests/FrameAppTests/OCRTextPanelControllerTests.swift`

- [ ] **Step 1: Replace text-view expectations with scrub-panel expectations**

In `Tests/FrameAppTests/OCRTextPanelControllerTests.swift`, replace `testOCRPanelShowsSelectableRecognizedTextAndCopyAllButton` with:

```swift
func testOCRPanelShowsScreenshotPreviewCutsAndDisabledCopyButton() throws {
    _ = NSApplication.shared
    let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
    let controller = OCRTextPanelController()
    retainedControllers.append(controller)
    let screenshot = try makeScreenshot()

    controller.show(
        layout: RecognizedTextLayout(lines: [
            RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
        ]),
        for: screenshot,
        strings: AppStrings(language: .en),
        copyText: { _ in true }
    )

    let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
    defer { panel.close() }
    let contentView = try XCTUnwrap(panel.contentView)
    panel.contentView?.layoutSubtreeIfNeeded()

    XCTAssertNotNil(findImageView(in: contentView))
    XCTAssertEqual(findButtons(in: contentView, accessibilityPrefix: "OCR Cut").map(\.title), ["为", "什", "么", "hello"])

    let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
    XCTAssertFalse(copyButton.isEnabled)
}
```

Replace `testCopyAllButtonInvokesClosureUsingSenderWindow` with:

```swift
func testSelectAllThenCopySelectedInvokesClosureWithSelectedText() throws {
    _ = NSApplication.shared
    let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
    let controller = OCRTextPanelController()
    retainedControllers.append(controller)
    let screenshot = try makeScreenshot()
    var copiedText: String?

    controller.show(
        layout: RecognizedTextLayout(lines: [
            RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
        ]),
        for: screenshot,
        strings: AppStrings(language: .en),
        copyText: { text in
            copiedText = text
            return true
        }
    )

    let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
    defer { panel.close() }
    let contentView = try XCTUnwrap(panel.contentView)

    let selectAllButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Select All"))
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(selectAllButton.action), to: selectAllButton.target, from: selectAllButton))

    let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
    XCTAssertTrue(copyButton.isEnabled)
    XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(copyButton.action), to: copyButton.target, from: copyButton))
    XCTAssertEqual(copiedText, "为什么 hello")
}
```

Update existing calls in reuse/close tests from `copyAll: { true }` to `copyText: { _ in true }`.

Add helpers:

```swift
private func findImageView(in view: NSView) -> NSImageView? {
    if let imageView = view as? NSImageView {
        return imageView
    }
    for subview in view.subviews {
        if let imageView = findImageView(in: subview) {
            return imageView
        }
    }
    return nil
}

private func findButtons(in view: NSView, accessibilityPrefix: String) -> [NSButton] {
    var buttons: [NSButton] = []
    if let button = view as? NSButton,
       button.accessibilityLabel()?.hasPrefix(accessibilityPrefix) == true {
        buttons.append(button)
    }
    for subview in view.subviews {
        buttons.append(contentsOf: findButtons(in: subview, accessibilityPrefix: accessibilityPrefix))
    }
    return buttons
}
```

- [ ] **Step 2: Run panel tests to verify failure**

Run:

```bash
swift test --filter OCRTextPanelControllerTests
```

Expected: FAIL because the panel still creates a text view and `copyText` does not exist.

- [ ] **Step 3: Implement panel item state and new show signature**

In `Sources/FrameApp/OCRTextPanelController.swift`, change the stored callback and `show` signature:

```swift
private var panelItems: [OCRTextPanelItem] = []

func show(
    layout: RecognizedTextLayout,
    for screenshot: CapturedScreenshot,
    strings: AppStrings,
    copyText: @escaping (String) -> Bool
) {
    let cutLayout = RecognizedTextCutLayout(textLayout: layout)
    if let existingItem = panelItem(for: screenshot) {
        existingItem.copyText = copyText
        existingItem.cutLayout = cutLayout
        existingItem.selectedCutIDs = []
        update(existingItem, screenshot: screenshot, strings: strings)
        activatePanel(existingItem.panel)
        return
    }

    let panel = makePanel(title: strings.ocrPanelTitle)
    let item = OCRTextPanelItem(
        panel: panel,
        screenshotID: screenshot.id,
        cutLayout: cutLayout,
        copyText: copyText
    )
    panel.contentView = makeContentView(screenshot: screenshot, strings: strings, item: item)
    panelItems.append(item)
    installLifecycleCallbacks(for: item)
    activatePanel(panel)
}
```

Replace `OCRTextPanelItem` with:

```swift
private final class OCRTextPanelItem {
    let panel: OCRTextPanel
    let screenshotID: UUID
    var cutLayout: RecognizedTextCutLayout
    var selectedCutIDs: Set<UUID> = []
    var copyText: (String) -> Bool

    init(
        panel: OCRTextPanel,
        screenshotID: UUID,
        cutLayout: RecognizedTextCutLayout,
        copyText: @escaping (String) -> Bool
    ) {
        self.panel = panel
        self.screenshotID = screenshotID
        self.cutLayout = cutLayout
        self.copyText = copyText
    }
}
```

- [ ] **Step 4: Implement content view**

Replace `makeContentView(layout:strings:)` with:

```swift
private func makeContentView(
    screenshot: CapturedScreenshot,
    strings: AppStrings,
    item: OCRTextPanelItem
) -> NSView {
    let contentView = NSView()
    contentView.translatesAutoresizingMaskIntoConstraints = false

    let imageView = NSImageView(image: screenshot.image)
    imageView.translatesAutoresizingMaskIntoConstraints = false
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.04).cgColor
    imageView.setAccessibilityLabel("OCR Screenshot Preview")

    let scrollView = NSScrollView()
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.hasVerticalScroller = true
    scrollView.borderType = .noBorder
    scrollView.documentView = makeCutContainer(for: item)

    let selectAllButton = NSButton(title: strings.ocrSelectAll, target: self, action: #selector(selectAllButtonClicked))
    selectAllButton.translatesAutoresizingMaskIntoConstraints = false
    selectAllButton.bezelStyle = .rounded
    selectAllButton.setAccessibilityLabel(strings.ocrSelectAll)

    let copyButton = NSButton(title: strings.ocrCopySelected, target: self, action: #selector(copySelectedButtonClicked))
    copyButton.translatesAutoresizingMaskIntoConstraints = false
    copyButton.bezelStyle = .rounded
    copyButton.setAccessibilityLabel(strings.ocrCopySelected)
    copyButton.isEnabled = false

    contentView.addSubview(imageView)
    contentView.addSubview(scrollView)
    contentView.addSubview(selectAllButton)
    contentView.addSubview(copyButton)

    NSLayoutConstraint.activate([
        imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
        imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
        imageView.heightAnchor.constraint(lessThanOrEqualToConstant: 180),
        imageView.heightAnchor.constraint(greaterThanOrEqualToConstant: 90),

        scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
        scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        scrollView.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 14),
        scrollView.bottomAnchor.constraint(equalTo: selectAllButton.topAnchor, constant: -12),

        selectAllButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
        selectAllButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

        copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
        copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
    ])

    return contentView
}
```

Add cut container creation:

```swift
private func makeCutContainer(for item: OCRTextPanelItem) -> NSView {
    let stackView = NSStackView()
    stackView.orientation = .vertical
    stackView.alignment = .leading
    stackView.spacing = 10
    stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    stackView.translatesAutoresizingMaskIntoConstraints = false

    for row in item.cutLayout.rows {
        let rowStack = NSStackView()
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.spacing = 4
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        for cut in row.cuts {
            rowStack.addArrangedSubview(makeCutButton(cut))
        }
        stackView.addArrangedSubview(rowStack)
    }

    return stackView
}

private func makeCutButton(_ cut: RecognizedTextCut) -> NSButton {
    let button = OCRCutButton(cutID: cut.id)
    button.title = cut.text
    button.target = self
    button.action = #selector(cutButtonClicked)
    button.bezelStyle = .regularSquare
    button.isBordered = false
    button.wantsLayer = true
    button.layer?.cornerRadius = 4
    button.setAccessibilityLabel("OCR Cut \(cut.text)")
    applyCutButtonStyle(button, isSelected: false)
    return button
}
```

Add `OCRCutButton`:

```swift
private final class OCRCutButton: NSButton {
    let cutID: UUID

    init(cutID: UUID) {
        self.cutID = cutID
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }
}
```

- [ ] **Step 5: Implement selection actions**

Add action methods:

```swift
@objc private func cutButtonClicked(_ sender: OCRCutButton) {
    guard let item = panelItem(for: sender.window) else {
        return
    }

    if item.selectedCutIDs.contains(sender.cutID) {
        item.selectedCutIDs.remove(sender.cutID)
    } else {
        item.selectedCutIDs.insert(sender.cutID)
    }

    refreshSelection(in: item)
}

@objc private func selectAllButtonClicked(_ sender: NSButton) {
    guard let item = panelItem(for: sender.window) else {
        return
    }

    item.selectedCutIDs = item.cutLayout.allCutIDs
    refreshSelection(in: item)
}

@objc private func copySelectedButtonClicked(_ sender: NSButton) {
    guard let item = panelItem(for: sender.window) else {
        return
    }

    let text = item.cutLayout.selectedText(for: item.selectedCutIDs)
    guard !text.isEmpty else {
        return
    }

    _ = item.copyText(text)
}
```

Add style refresh helpers:

```swift
private func refreshSelection(in item: OCRTextPanelItem) {
    guard let contentView = item.panel.contentView else {
        return
    }

    for button in findCutButtons(in: contentView) {
        applyCutButtonStyle(button, isSelected: item.selectedCutIDs.contains(button.cutID))
    }

    findButton(in: contentView, accessibilityLabel: AppStrings.current().ocrCopySelected)?.isEnabled =
        !item.selectedCutIDs.isEmpty
}

private func applyCutButtonStyle(_ button: OCRCutButton, isSelected: Bool) {
    button.contentTintColor = isSelected ? .controlAccentColor : .labelColor
    button.layer?.backgroundColor = isSelected
        ? NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        : NSColor.controlBackgroundColor.withAlphaComponent(0.7).cgColor
}

private func findCutButtons(in view: NSView) -> [OCRCutButton] {
    var buttons: [OCRCutButton] = []
    if let button = view as? OCRCutButton {
        buttons.append(button)
    }
    for subview in view.subviews {
        buttons.append(contentsOf: findCutButtons(in: subview))
    }
    return buttons
}

private func findButton(in view: NSView, accessibilityLabel: String) -> NSButton? {
    if let button = view as? NSButton,
       button.accessibilityLabel() == accessibilityLabel {
        return button
    }
    for subview in view.subviews {
        if let button = findButton(in: subview, accessibilityLabel: accessibilityLabel) {
            return button
        }
    }
    return nil
}
```

- [ ] **Step 6: Implement update for panel reuse**

Replace `update(_ item:layout:)` with:

```swift
private func update(_ item: OCRTextPanelItem, screenshot: CapturedScreenshot, strings: AppStrings) {
    item.panel.contentView = makeContentView(screenshot: screenshot, strings: strings, item: item)
}
```

Delete `findTextView(in:)` and the old `copyAllButtonClicked`.

- [ ] **Step 7: Run AppKit panel tests**

Run:

```bash
swift test --filter OCRTextPanelControllerTests
```

Expected: PASS.

- [ ] **Step 8: Commit with Task 2 changes if needed**

```bash
git add Sources/FrameApp/OCRTextPanelController.swift Tests/FrameAppTests/OCRTextPanelControllerTests.swift Sources/FrameApp/AppStrings.swift Tests/FrameAppTests/AppStringsTests.swift Sources/FrameApp/AppDelegate.swift
git commit -m "feat: add OCR scrub selection panel"
```

---

### Task 4: Drag-to-Select Scrubbing

**Files:**
- Modify: `Sources/FrameApp/OCRTextPanelController.swift`
- Modify: `Tests/FrameAppTests/OCRTextPanelControllerTests.swift`

- [ ] **Step 1: Add testable selection method**

Add this test to `Tests/FrameAppTests/OCRTextPanelControllerTests.swift`:

```swift
func testSelectingCutsByIDsEnablesCopySelected() throws {
    _ = NSApplication.shared
    let windowsBeforeShow = Set(NSApp.windows.map(ObjectIdentifier.init))
    let controller = OCRTextPanelController()
    retainedControllers.append(controller)
    let screenshot = try makeScreenshot()

    controller.show(
        layout: RecognizedTextLayout(lines: [
            RecognizedTextLine(text: "为什么 hello", bounds: .zero, confidence: 0.9),
        ]),
        for: screenshot,
        strings: AppStrings(language: .en),
        copyText: { _ in true }
    )

    let panel = try XCTUnwrap(NSApp.windows.first { !windowsBeforeShow.contains(ObjectIdentifier($0)) } as? NSPanel)
    defer { panel.close() }
    let contentView = try XCTUnwrap(panel.contentView)
    let cutButtons = findButtons(in: contentView, accessibilityPrefix: "OCR Cut")
    XCTAssertGreaterThan(cutButtons.count, 1)

    controller.selectCutButtonsForTesting(Array(cutButtons.prefix(2)), in: panel)

    let copyButton = try XCTUnwrap(findButton(in: contentView, accessibilityLabel: "Copy Selected"))
    XCTAssertTrue(copyButton.isEnabled)
}
```

- [ ] **Step 2: Run test to verify failure**

Run:

```bash
swift test --filter OCRTextPanelControllerTests/testSelectingCutsByIDsEnablesCopySelected
```

Expected: FAIL because `selectCutButtonsForTesting` is not defined.

- [ ] **Step 3: Add drag-select state and test hook**

Add to `OCRTextPanelController`:

```swift
func selectCutButtonsForTesting(_ buttons: [NSButton], in panel: NSPanel) {
    guard let item = panelItem(for: panel) else {
        return
    }

    for button in buttons {
        guard let cutButton = button as? OCRCutButton else {
            continue
        }
        item.selectedCutIDs.insert(cutButton.cutID)
    }

    refreshSelection(in: item)
}
```

Add a panel lookup overload:

```swift
private func panelItem(for panel: NSPanel) -> OCRTextPanelItem? {
    panelItems.first { $0.panel === panel }
}
```

- [ ] **Step 4: Implement mouse-enter scrubbing**

In `OCRCutButton`, add hover tracking:

```swift
var onMouseEntered: ((OCRCutButton) -> Void)?
private var trackingArea: NSTrackingArea?

override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea {
        removeTrackingArea(trackingArea)
    }
    let nextArea = NSTrackingArea(
        rect: bounds,
        options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
        owner: self,
        userInfo: nil
    )
    addTrackingArea(nextArea)
    trackingArea = nextArea
}

override func mouseEntered(with event: NSEvent) {
    super.mouseEntered(with: event)
    guard event.pressedMouseButtons & 1 == 1 else {
        return
    }
    onMouseEntered?(self)
}
```

In `makeCutButton(_:)`, attach the callback:

```swift
button.onMouseEntered = { [weak self, weak button] hoveredButton in
    guard let self,
          let window = button?.window,
          let item = self.panelItem(for: window) else {
        return
    }

    item.selectedCutIDs.insert(hoveredButton.cutID)
    self.refreshSelection(in: item)
}
```

- [ ] **Step 5: Run panel tests**

Run:

```bash
swift test --filter OCRTextPanelControllerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/FrameApp/OCRTextPanelController.swift Tests/FrameAppTests/OCRTextPanelControllerTests.swift
git commit -m "feat: support OCR cut scrubbing"
```

---

### Task 5: Full Verification and Local App Handoff

**Files:**
- No code files unless previous tasks reveal compile issues.

- [ ] **Step 1: Run full tests**

```bash
swift test
```

Expected: all XCTest and Swift Testing suites pass.

- [ ] **Step 2: Run build**

```bash
swift build
```

Expected: exit 0.

- [ ] **Step 3: Package with stable local signing**

```bash
FRAME_CODESIGN_IDENTITY="Frame Local Dev CLI" scripts/package-app.sh
```

Expected: package script creates `.build/app/Frame.app` and prints `Signed with identity: Frame Local Dev CLI`.

- [ ] **Step 4: Replace the local test app**

```bash
osascript -e 'tell application "Frame" to quit' >/dev/null 2>&1 || true
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/Frame.app"
ditto .build/app/Frame.app "$HOME/Applications/Frame.app"
xattr -dr com.apple.quarantine "$HOME/Applications/Frame.app" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/Frame.app"
codesign -dv --verbose=2 "$HOME/Applications/Frame.app" 2>&1 | grep "Authority=Frame Local Dev CLI"
open "$HOME/Applications/Frame.app"
```

Expected: codesign verifies the app and prints `Authority=Frame Local Dev CLI`.

- [ ] **Step 5: Memory check**

Run repo-memory. Expected result: no additional durable docs are needed if this plan and the design spec remain accurate after implementation.

---

## Self-Review

- Spec coverage: token/cut model, screenshot preview, cut grid, click selection, drag selection, select all, copy selected, Quick Access/HUD shared route, tests, and stable signed local handoff are covered.
- Placeholder scan: no open placeholders or unspecified test instructions remain.
- Type consistency: `RecognizedTextCutLayout`, `copyText`, `ocrSelectAll`, `ocrCopySelected`, `OCRCutButton`, and panel item state names are consistent across tasks.
