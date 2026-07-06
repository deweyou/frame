import CoreGraphics
import Foundation
import XCTest
import FrameCore

final class ZFrameCoreTests: XCTestCase {
    func testFrameVersionConstants() {
        XCTAssert(FrameVersion.shortVersion == "0.1.1")
        XCTAssert(FrameVersion.build == "2")
        XCTAssert(FrameVersion.displayName == "0.1.1 (2)")
    }

    func testDefaultShortcutsMatchMvpDefaults() {
        XCTAssert(KeyboardShortcut.defaultScreenshot.key == "a")
        XCTAssert(KeyboardShortcut.defaultScreenshot.displayName == "Command+Shift+A")
        XCTAssert(!KeyboardShortcut.defaultScreenshot.isReservedOnly)
    }

    func testScreenshotShortcutDefaultsToCommandShiftA() {
        XCTAssertEqual(ScreenshotShortcut.default.key, .letter("A"))
        XCTAssertEqual(ScreenshotShortcut.default.modifiers, [.command, .shift])
        XCTAssertEqual(ScreenshotShortcut.default.displayName, "⌘⇧A")
        XCTAssertEqual(ScreenshotShortcut.default.storageValue, "cmd+shift+a")
        XCTAssertEqual(ScreenshotShortcut.default.keyboardShortcut.displayName, "Command+Shift+A")
    }

    func testCommandShiftRRemainsAvailableForConfiguredRecordingShortcut() {
        XCTAssertEqual(ScreenshotShortcut.defaultRecording.key, .letter("R"))
        XCTAssertEqual(ScreenshotShortcut.defaultRecording.modifiers, [.command, .shift])
        XCTAssertEqual(ScreenshotShortcut.defaultRecording.displayName, "⌘⇧R")
        XCTAssertEqual(ScreenshotShortcut.defaultRecording.storageValue, "cmd+shift+r")
        XCTAssertEqual(ScreenshotShortcut.defaultRecording.keyboardShortcut.displayName, "Command+Shift+R")
    }

    func testScreenshotShortcutMigratesLegacyPresetStorage() {
        XCTAssertEqual(
            ScreenshotShortcut.persistedValue(for: "commandShiftA"),
            ScreenshotShortcut(key: .letter("A"), modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            ScreenshotShortcut.persistedValue(for: "commandShiftS"),
            ScreenshotShortcut(key: .letter("S"), modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            ScreenshotShortcut.persistedValue(for: "commandShiftD"),
            ScreenshotShortcut(key: .letter("D"), modifiers: [.command, .shift])
        )
        XCTAssertEqual(
            ScreenshotShortcut.persistedValue(for: "commandShiftF"),
            ScreenshotShortcut(key: .letter("F"), modifiers: [.command, .shift])
        )
    }

    func testScreenshotShortcutPersistsAndReadsEncodedStorage() {
        let shortcut = ScreenshotShortcut(key: .number("7"), modifiers: [.command, .option])

        XCTAssertEqual(shortcut.displayName, "⌘⌥7")
        XCTAssertEqual(shortcut.keyboardShortcut.displayName, "Command+Option+7")
        XCTAssertEqual(shortcut.storageValue, "cmd+option+7")
        XCTAssertEqual(ScreenshotShortcut.persistedValue(for: "cmd+option+7"), shortcut)
    }

    func testScreenshotShortcutFallsBackForUnknownStorage() {
        XCTAssertEqual(ScreenshotShortcut.persistedValue(for: nil), .default)
        XCTAssertEqual(ScreenshotShortcut.persistedValue(for: "unknown"), .default)
    }

    func testScreenshotShortcutAcceptsLettersAndNumbersWithTwoModifiers() {
        XCTAssertEqual(
            ScreenshotShortcut.validate(key: .letter("Z"), modifiers: [.command, .option]),
            .valid(ScreenshotShortcut(key: .letter("Z"), modifiers: [.command, .option]))
        )
        XCTAssertEqual(
            ScreenshotShortcut.validate(key: .number("7"), modifiers: [.control, .shift]),
            .valid(ScreenshotShortcut(key: .number("7"), modifiers: [.control, .shift]))
        )
    }

    func testScreenshotShortcutRejectsUnsafeCombinations() {
        XCTAssertEqual(
            ScreenshotShortcut.validate(key: .letter("A"), modifiers: [.command]),
            .invalid(.insufficientModifiers)
        )
        XCTAssertEqual(
            ScreenshotShortcut.validate(key: .letter("A"), modifiers: [.shift]),
            .invalid(.insufficientModifiers)
        )
        XCTAssertEqual(
            ScreenshotShortcut.validate(key: .unsupported, modifiers: [.command, .shift]),
            .invalid(.unsupportedKey)
        )
        XCTAssertEqual(
            ScreenshotShortcut.validate(key: .letter("R"), modifiers: [.command, .shift]),
            .valid(ScreenshotShortcut(key: .letter("R"), modifiers: [.command, .shift]))
        )
    }

    func testShortcutValidationRejectsDuplicateShortcutWhenProvided() {
        XCTAssertEqual(
            ScreenshotShortcut.validate(
                key: .letter("A"),
                modifiers: [.command, .shift],
                duplicateShortcut: .default
            ),
            .invalid(.duplicateShortcut)
        )
    }

    func testRecordingShortcutPersistenceAllowsCommandShiftR() {
        XCTAssertEqual(
            ScreenshotShortcut.persistedValue(
                for: "cmd+shift+r",
                defaultShortcut: .defaultRecording,
                reservedShortcuts: []
            ),
            .defaultRecording
        )
    }

    func testImageWorkspaceDefaultsToPointerTool() {
        let state = ImageWorkspaceState(kind: .temporaryPreview)

        XCTAssert(state.kind == .temporaryPreview)
        XCTAssert(state.selectedTool == .select)
        XCTAssert(state.closePolicy == .escapeOrExplicitClose)
    }

    func testPinnedWorkspaceOnlyClosesExplicitly() {
        let state = ImageWorkspaceState(kind: .pinned)

        XCTAssert(state.kind == .pinned)
        XCTAssert(state.closePolicy == .explicitCloseOnly)
    }

    func testSelectingEditingToolsUpdatesWorkspaceState() {
        var state = ImageWorkspaceState(kind: .temporaryPreview)

        for tool in ImageAnnotationTool.allCases {
            state.select(tool)
            XCTAssert(state.selectedTool == tool)
        }
    }

    func testScreenshotFilenameUsesFrameTimestampFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(
            from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0)!,
                year: 2026,
                month: 5,
                day: 18,
                hour: 9,
                minute: 7,
                second: 6
            )
        )!

        let naming = ScreenshotNaming(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssert(naming.filename(for: date) == "Frame 2026-05-18 09.07.06.png")
    }

    func testDesktopSaveURLAppendsGeneratedFilename() {
        let desktopDirectory = URL(fileURLWithPath: "/Users/deweyou/Desktop", isDirectory: true)

        let saveURL = ScreenshotNaming.saveURL(
            desktopDirectory: desktopDirectory,
            filename: "Frame test.png"
        )

        XCTAssert(saveURL.path == "/Users/deweyou/Desktop/Frame test.png")
    }

    func testSelectionRectNormalizesDragDirections() {
        let rect = SelectionGeometry.normalizedRect(
            from: CGPoint(x: 120, y: 90),
            to: CGPoint(x: 20, y: 10)
        )

        XCTAssert(rect.origin.x == 20)
        XCTAssert(rect.origin.y == 10)
        XCTAssert(rect.width == 100)
        XCTAssert(rect.height == 80)
    }

    func testTinySelectionsAreRejected() {
        XCTAssert(!SelectionGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 4, height: 10)))
        XCTAssert(!SelectionGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 10, height: 4)))
        XCTAssert(SelectionGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 8, height: 8)))
    }

    func testSelectionCaptureMarksWindowSelections() {
        let rect = CGRect(x: 10, y: 20, width: 320, height: 240)
        let capture = SelectionCapture(rect: rect, kind: .window(id: 42))

        XCTAssert(capture.rect == rect)
        XCTAssert(capture.kind == .window(id: 42))
    }

    func testCenterResizePreservesCenter() {
        let original = CGRect(x: 100, y: 120, width: 200, height: 100)
        let resized = SelectionSizing.centeredRect(
            around: original.center,
            size: CGSize(width: 120, height: 80),
            inside: CGRect(x: 0, y: 0, width: 500, height: 400)
        )

        XCTAssert(resized.midX == original.midX)
        XCTAssert(resized.midY == original.midY)
        XCTAssert(resized.size == CGSize(width: 120, height: 80))
    }

    func testLockedWidthEditDerivesHeight() {
        let size = SelectionSizing.size(
            editing: .width,
            value: 160,
            currentSize: CGSize(width: 100, height: 50),
            mode: .locked(SelectionAspectRatio(width: 16, height: 9))
        )

        XCTAssert(size == CGSize(width: 160, height: 90))
    }

    func testLockedHeightEditDerivesWidth() {
        let size = SelectionSizing.size(
            editing: .height,
            value: 90,
            currentSize: CGSize(width: 100, height: 50),
            mode: .locked(SelectionAspectRatio(width: 16, height: 9))
        )

        XCTAssert(size == CGSize(width: 160, height: 90))
    }

    func testPresetFitDoesNotEnlargeCurrentSelection() {
        let current = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let fitted = SelectionSizing.fit(
            aspectRatio: SelectionAspectRatio(width: 16, height: 9),
            inside: current
        )

        XCTAssert(fitted.width == 1200)
        XCTAssert(fitted.height == 675)
        XCTAssert(fitted.midX == current.midX)
        XCTAssert(fitted.midY == current.midY)
    }

    func testTallPresetFitDoesNotEnlargeCurrentSelection() {
        let current = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let fitted = SelectionSizing.fit(
            aspectRatio: SelectionAspectRatio(width: 16, height: 9),
            inside: current
        )

        XCTAssert(fitted.width == 800)
        XCTAssert(fitted.height == 450)
        XCTAssert(fitted.midX == current.midX)
        XCTAssert(fitted.midY == current.midY)
    }

    func testDefaultPresetSelectionFitsInsideSixtyPercentScreenBox() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = SelectionSizing.defaultSelection(
            aspectRatio: SelectionAspectRatio(width: 16, height: 9),
            screenBounds: screen
        )

        XCTAssert(selection.width == 864)
        XCTAssert(selection.height == 486)
        XCTAssert(selection.midX == screen.midX)
        XCTAssert(selection.midY == screen.midY)
    }

    func testLockedOversizedSelectionClampsWhilePreservingRatio() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let selection = SelectionSizing.centeredRect(
            around: screen.center,
            size: CGSize(width: 2000, height: 1125),
            inside: screen,
            preserving: SelectionAspectRatio(width: 16, height: 9)
        )

        XCTAssert(selection.width == 1000)
        XCTAssert(selection.height == 562.5)
        XCTAssert(selection.midX == screen.midX)
        XCTAssert(selection.midY == screen.midY)
    }

    func testRecognizedTextLayoutOrdersLinesTopToBottomThenLeftToRight() {
        let lines = [
            RecognizedTextLine(text: "third", bounds: NormalizedImageRect(x: 0.1, y: 0.1, width: 0.2, height: 0.08), confidence: 0.8),
            RecognizedTextLine(text: "second", bounds: NormalizedImageRect(x: 0.4, y: 0.7, width: 0.2, height: 0.08), confidence: 0.9),
            RecognizedTextLine(text: "first", bounds: NormalizedImageRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08), confidence: 0.95),
        ]

        let layout = RecognizedTextLayout(lines: lines)

        XCTAssert(layout.lines.map(\.text) == ["first", "second", "third"])
        XCTAssert(layout.fullText == "first second\nthird")
    }

    func testRecognizedTextLayoutDropsEmptyLinesAndKeepsMetadata() {
        let line = RecognizedTextLine(
            text: "hello",
            bounds: NormalizedImageRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1),
            confidence: 0.72
        )

        let layout = RecognizedTextLayout(lines: [
            RecognizedTextLine(text: " ", bounds: .zero, confidence: nil),
            line,
        ])

        XCTAssert(layout.lines == [line])
        XCTAssert(layout.fullText == "hello")
        XCTAssert(layout.lines[0].bounds == line.bounds)
        XCTAssert(layout.lines[0].confidence == 0.72)
    }

    func testRecognizedTextLayoutEmptyResultsHaveEmptyText() {
        let layout = RecognizedTextLayout(lines: [])

        XCTAssert(layout.lines.isEmpty)
        XCTAssert(layout.fullText == "")
        XCTAssert(layout.isEmpty)
    }

    func testRecognizedTextLayoutUsesDeterministicTieBreakersWithinRows() {
        let lines = [
            RecognizedTextLine(text: "wide", bounds: NormalizedImageRect(x: 0.2, y: 0.5, width: 0.3, height: 0.1), confidence: nil),
            RecognizedTextLine(text: "higher", bounds: NormalizedImageRect(x: 0.2, y: 0.51, width: 0.2, height: 0.1), confidence: nil),
            RecognizedTextLine(text: "narrow", bounds: NormalizedImageRect(x: 0.2, y: 0.5, width: 0.2, height: 0.1), confidence: nil),
            RecognizedTextLine(text: "right", bounds: NormalizedImageRect(x: 0.2001, y: 0.5, width: 0.1, height: 0.1), confidence: nil),
        ]

        let layout = RecognizedTextLayout(lines: lines)

        XCTAssert(layout.lines.map(\.text) == ["higher", "narrow", "wide", "right"])
        XCTAssert(layout.fullText == "higher narrow wide right")
    }

    func testRecognizedTextLayoutSeparatesRowsPastToleranceBoundary() {
        let sameRowTop = RecognizedTextLine(text: "same-top", bounds: NormalizedImageRect(x: 0.1, y: 0.56, width: 0.2, height: 0.1), confidence: nil)
        let sameRowBottom = RecognizedTextLine(text: "same-bottom", bounds: NormalizedImageRect(x: 0.4, y: 0.5, width: 0.2, height: 0.1), confidence: nil)
        let nextRow = RecognizedTextLine(text: "next", bounds: NormalizedImageRect(x: 0.1, y: 0.439, width: 0.2, height: 0.1), confidence: nil)

        let layout = RecognizedTextLayout(lines: [
            nextRow,
            sameRowBottom,
            sameRowTop,
        ])

        XCTAssert(layout.lines.map(\.text) == ["same-top", "same-bottom", "next"])
        XCTAssert(layout.fullText == "same-top same-bottom\nnext")
    }

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

        XCTAssert(layout.rows.count == 1)
        XCTAssert(layout.rows[0].cuts.map(\.text) == ["为", "什", "么", "ListV4/tanstack", "全", "量"])
    }

    func testRecognizedTextTokenizerCandidatesPreserveStringRanges() {
        let text = "为什么 ListV4/tanstack 全量"
        let candidates = RecognizedTextCutLayout.tokenizerCandidates(in: text)

        XCTAssert(candidates.map(\.text) == ["为", "什", "么", "ListV4/tanstack", "全", "量"])
        XCTAssert(candidates.map { String(text[$0.range]) } == candidates.map(\.text))
        XCTAssert(candidates.map(\.needsLeadingSpace) == [false, false, false, true, true, false])
    }

    func testRecognizedTextCutLayoutPrefersLineTokenBounds() {
        let tokenBounds = NormalizedImageRect(x: 0.2, y: 0.72, width: 0.1, height: 0.04)
        let lineBounds = NormalizedImageRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1)
        let layout = RecognizedTextCutLayout(
            textLayout: RecognizedTextLayout(lines: [
                RecognizedTextLine(
                    text: "Hello",
                    bounds: lineBounds,
                    confidence: 0.9,
                    tokens: [
                        RecognizedTextToken(text: "Hello", bounds: tokenBounds, needsLeadingSpace: false),
                    ]
                ),
            ])
        )

        XCTAssert(layout.rows.count == 1)
        XCTAssert(layout.rows[0].cuts.count == 1)
        XCTAssert(layout.rows[0].cuts[0].text == "Hello")
        XCTAssert(layout.rows[0].cuts[0].bounds == tokenBounds)
    }

    func testRecognizedTextCutLayoutSplitsPureCodeJoinerPunctuation() {
        let layout = RecognizedTextCutLayout(
            textLayout: RecognizedTextLayout(lines: [
                RecognizedTextLine(
                    text: "... @@ //",
                    bounds: NormalizedImageRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
                    confidence: nil
                ),
            ])
        )

        XCTAssert(layout.rows.count == 1)
        XCTAssert(layout.rows[0].cuts.map(\.text) == [".", ".", ".", "@", "@", "/", "/"])
    }

    func testRecognizedTextCutLayoutRestrictsWordRunsToASCIILatinAndDigits() {
        let layout = RecognizedTextCutLayout(
            textLayout: RecognizedTextLayout(lines: [
                RecognizedTextLine(
                    text: "abc αβ АБ café",
                    bounds: NormalizedImageRect(x: 0.1, y: 0.7, width: 0.8, height: 0.1),
                    confidence: nil
                ),
            ])
        )

        XCTAssert(layout.rows.count == 1)
        XCTAssert(layout.rows[0].cuts.map(\.text) == ["abc", "α", "β", "А", "Б", "caf", "é"])
    }

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

        XCTAssert(layout.selectedText(for: selected) == "Hello\n第二行")
    }

    func testRecognizedTextCutLayoutSkipsEmptyRowsFromTextLayout() {
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

        XCTAssert(layout.rows.count == 1)
        XCTAssert(layout.rows[0].cuts.map(\.text) == ["visible"])
    }

    func testImageAnnotationDocumentDefaultsToSelectableShapeEditing() {
        let document = ImageAnnotationDocument()

        XCTAssertEqual(document.selectedTool, .select)
        XCTAssertEqual(document.editingOptions.shapeKind, .rectangle)
        XCTAssertEqual(document.editingOptions.mosaicMode, .rectangle)
        XCTAssertEqual(document.editingOptions.style.strokeColor, .red)
        XCTAssertEqual(document.editingOptions.style.lineWidth, 4)
        XCTAssertTrue(document.elements.isEmpty)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
        XCTAssertFalse(document.hasUncommittedEdits)
    }

    func testImageAnnotationDocumentAddsSelectsMovesResizesAndDeletesElements() {
        var document = ImageAnnotationDocument()
        let element = ImageAnnotationElement(
            kind: .shape(.rectangle),
            bounds: CGRect(x: 10, y: 20, width: 80, height: 40),
            style: .default
        )

        document.add(element)

        XCTAssertEqual(document.elements.count, 1)
        XCTAssertEqual(document.selectedElementID, element.id)
        XCTAssertEqual(document.topmostElementID(at: CGPoint(x: 20, y: 30)), element.id)

        document.moveSelected(by: CGSize(width: 5, height: -10))
        XCTAssertEqual(document.elements[0].bounds, CGRect(x: 15, y: 10, width: 80, height: 40))

        document.resizeSelected(to: CGRect(x: 15, y: 10, width: 120, height: 64))
        XCTAssertEqual(document.elements[0].bounds, CGRect(x: 15, y: 10, width: 120, height: 64))

        document.deleteSelected()
        XCTAssertTrue(document.elements.isEmpty)
        XCTAssertNil(document.selectedElementID)
        XCTAssertTrue(document.canUndo)
    }

    func testImageAnnotationDocumentUndoRedoRestoresElementSnapshots() {
        var document = ImageAnnotationDocument()
        let first = ImageAnnotationElement(
            kind: .shape(.ellipse),
            bounds: CGRect(x: 10, y: 20, width: 80, height: 40),
            style: .default
        )
        let second = ImageAnnotationElement(
            kind: .text("Frame"),
            bounds: CGRect(x: 40, y: 80, width: 120, height: 32),
            style: .default
        )

        document.add(first)
        document.add(second)
        document.undo()

        XCTAssertEqual(document.elements.map(\.id), [first.id])
        XCTAssertEqual(document.selectedElementID, first.id)
        XCTAssertTrue(document.canRedo)

        document.redo()

        XCTAssertEqual(document.elements.map(\.id), [first.id, second.id])
        XCTAssertEqual(document.selectedElementID, second.id)
    }

    func testImageAnnotationDocumentGroupsContinuousGeometryEditing() {
        var document = ImageAnnotationDocument()
        let element = ImageAnnotationElement(
            kind: .shape(.rectangle),
            bounds: CGRect(x: 10, y: 20, width: 80, height: 40),
            style: .default
        )
        document.add(element)

        document.beginEditingSelectedElement()
        document.moveSelected(by: CGSize(width: 5, height: 5), recordingUndo: false)
        document.moveSelected(by: CGSize(width: 10, height: -2), recordingUndo: false)

        XCTAssertEqual(document.elements[0].bounds, CGRect(x: 25, y: 23, width: 80, height: 40))

        document.undo()

        XCTAssertEqual(document.elements[0].bounds, CGRect(x: 10, y: 20, width: 80, height: 40))
        document.redo()
        XCTAssertEqual(document.elements[0].bounds, CGRect(x: 25, y: 23, width: 80, height: 40))
    }

    func testImageAnnotationDocumentUpdatesToolOptionsAndCommitsCurrentRendition() {
        var document = ImageAnnotationDocument()

        document.selectTool(.mosaic)
        document.setShapeKind(.arrow)
        document.setMosaicMode(.brush)
        document.setStyle(
            ImageAnnotationStyle(
                strokeColor: .blue,
                fillColor: .yellow.withAlpha(0.32),
                lineWidth: 8,
                fontSize: 18,
                fontWeight: .bold,
                mosaicBlockSize: 14,
                mosaicStrength: 0.9
            )
        )
        document.add(ImageAnnotationElement(
            kind: .mosaic(.brush),
            bounds: CGRect(x: 0, y: 0, width: 64, height: 64),
            points: [CGPoint(x: 8, y: 8), CGPoint(x: 48, y: 48)],
            style: document.editingOptions.style
        ))

        XCTAssertEqual(document.selectedTool, .mosaic)
        XCTAssertEqual(document.editingOptions.shapeKind, .arrow)
        XCTAssertEqual(document.editingOptions.mosaicMode, .brush)
        XCTAssertEqual(document.editingOptions.style.strokeColor, .blue)
        XCTAssertEqual(document.editingOptions.style.fillColor, .yellow.withAlpha(0.32))
        XCTAssertTrue(document.hasUncommittedEdits)

        document.markCurrentRenditionSaved()

        XCTAssertTrue(document.elements.isEmpty)
        XCTAssertNil(document.selectedElementID)
        XCTAssertFalse(document.canUndo)
        XCTAssertFalse(document.canRedo)
        XCTAssertFalse(document.hasUncommittedEdits)
        XCTAssertEqual(document.selectedTool, .mosaic)
    }

    func testImageAnnotationDocumentReplacesSelectedText() {
        var document = ImageAnnotationDocument()
        let text = ImageAnnotationElement(
            kind: .text("Hello"),
            bounds: CGRect(x: 10, y: 20, width: 80, height: 28),
            style: .default
        )

        document.add(text)
        document.replaceSelectedText("Frame")

        XCTAssertEqual(document.elements.first?.kind, .text("Frame"))
    }

    func testImageAnnotationDocumentUpdatesSelectedTextStyle() {
        var document = ImageAnnotationDocument()
        var style = ImageAnnotationStyle.default
        style.fontSize = 16
        let text = ImageAnnotationElement(
            kind: .text("Hello"),
            bounds: CGRect(x: 10, y: 20, width: 80, height: 28),
            style: style
        )

        document.add(text)
        style.fontSize = 28
        document.updateSelectedStyle(style)

        XCTAssertEqual(document.elements.first?.style.fontSize, 28)
        XCTAssertTrue(document.hasUncommittedEdits)
        XCTAssertTrue(document.canUndo)

        document.undo()

        XCTAssertEqual(document.elements.first?.style.fontSize, 16)
    }
}
