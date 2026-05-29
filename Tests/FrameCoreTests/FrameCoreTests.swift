import CoreGraphics
import Foundation
import Testing
import FrameCore

struct FrameCoreTests {
    @Test
    func testFrameVersionConstants() {
        #expect(FrameVersion.shortVersion == "0.1.0")
        #expect(FrameVersion.build == "1")
        #expect(FrameVersion.displayName == "0.1.0 (1)")
    }

    @Test
    func testDefaultShortcutsMatchMvpDefaults() {
        #expect(KeyboardShortcut.defaultScreenshot.key == "a")
        #expect(KeyboardShortcut.defaultScreenshot.displayName == "Command+Shift+A")
        #expect(KeyboardShortcut.defaultRecording.key == "r")
        #expect(KeyboardShortcut.defaultRecording.displayName == "Command+Shift+R")
        #expect(KeyboardShortcut.defaultRecording.isReservedOnly)
        #expect(!KeyboardShortcut.defaultScreenshot.isReservedOnly)
    }

    @Test
    func testScreenshotShortcutOptionsExposeDisplayNames() {
        #expect(ScreenshotShortcut.commandShiftA.keyboardShortcut.displayName == "Command+Shift+A")
        #expect(ScreenshotShortcut.commandShiftS.keyboardShortcut.displayName == "Command+Shift+S")
        #expect(ScreenshotShortcut.commandShiftD.keyboardShortcut.displayName == "Command+Shift+D")
        #expect(ScreenshotShortcut.commandShiftF.keyboardShortcut.displayName == "Command+Shift+F")
    }

    @Test
    func testScreenshotShortcutPersistenceFallsBackToDefault() {
        #expect(ScreenshotShortcut.persistedValue(for: "commandShiftS") == .commandShiftS)
        #expect(ScreenshotShortcut.persistedValue(for: nil) == .commandShiftA)
        #expect(ScreenshotShortcut.persistedValue(for: "unknown") == .commandShiftA)
    }

    @Test
    func testImageWorkspaceDefaultsToViewWithoutActiveTool() {
        let state = ImageWorkspaceState(kind: .temporaryPreview)

        #expect(state.kind == .temporaryPreview)
        #expect(state.selectedTool == nil)
        #expect(state.closePolicy == .escapeOrExplicitClose)
    }

    @Test
    func testPinnedWorkspaceOnlyClosesExplicitly() {
        let state = ImageWorkspaceState(kind: .pinned)

        #expect(state.kind == .pinned)
        #expect(state.closePolicy == .explicitCloseOnly)
    }

    @Test
    func testSelectingEditingToolsUpdatesWorkspaceState() {
        var state = ImageWorkspaceState(kind: .temporaryPreview)

        for tool in ImageEditingTool.allCases {
            state.select(tool)
            #expect(state.selectedTool == tool)
        }
    }

    @Test
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

        #expect(naming.filename(for: date) == "Frame 2026-05-18 09.07.06.png")
    }

    @Test
    func testDesktopSaveURLAppendsGeneratedFilename() {
        let desktopDirectory = URL(fileURLWithPath: "/Users/deweyou/Desktop", isDirectory: true)

        let saveURL = ScreenshotNaming.saveURL(
            desktopDirectory: desktopDirectory,
            filename: "Frame test.png"
        )

        #expect(saveURL.path == "/Users/deweyou/Desktop/Frame test.png")
    }

    @Test
    func testSelectionRectNormalizesDragDirections() {
        let rect = SelectionGeometry.normalizedRect(
            from: CGPoint(x: 120, y: 90),
            to: CGPoint(x: 20, y: 10)
        )

        #expect(rect.origin.x == 20)
        #expect(rect.origin.y == 10)
        #expect(rect.width == 100)
        #expect(rect.height == 80)
    }

    @Test
    func testTinySelectionsAreRejected() {
        #expect(!SelectionGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 4, height: 10)))
        #expect(!SelectionGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 10, height: 4)))
        #expect(SelectionGeometry.isValidSelection(CGRect(x: 0, y: 0, width: 8, height: 8)))
    }

    @Test
    func testSelectionCaptureMarksWindowSelections() {
        let rect = CGRect(x: 10, y: 20, width: 320, height: 240)
        let capture = SelectionCapture(rect: rect, kind: .window(id: 42))

        #expect(capture.rect == rect)
        #expect(capture.kind == .window(id: 42))
    }

    @Test
    func testCenterResizePreservesCenter() {
        let original = CGRect(x: 100, y: 120, width: 200, height: 100)
        let resized = SelectionSizing.centeredRect(
            around: original.center,
            size: CGSize(width: 120, height: 80),
            inside: CGRect(x: 0, y: 0, width: 500, height: 400)
        )

        #expect(resized.midX == original.midX)
        #expect(resized.midY == original.midY)
        #expect(resized.size == CGSize(width: 120, height: 80))
    }

    @Test
    func testLockedWidthEditDerivesHeight() {
        let size = SelectionSizing.size(
            editing: .width,
            value: 160,
            currentSize: CGSize(width: 100, height: 50),
            mode: .locked(SelectionAspectRatio(width: 16, height: 9))
        )

        #expect(size == CGSize(width: 160, height: 90))
    }

    @Test
    func testLockedHeightEditDerivesWidth() {
        let size = SelectionSizing.size(
            editing: .height,
            value: 90,
            currentSize: CGSize(width: 100, height: 50),
            mode: .locked(SelectionAspectRatio(width: 16, height: 9))
        )

        #expect(size == CGSize(width: 160, height: 90))
    }

    @Test
    func testPresetFitDoesNotEnlargeCurrentSelection() {
        let current = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let fitted = SelectionSizing.fit(
            aspectRatio: SelectionAspectRatio(width: 16, height: 9),
            inside: current
        )

        #expect(fitted.width == 1200)
        #expect(fitted.height == 675)
        #expect(fitted.midX == current.midX)
        #expect(fitted.midY == current.midY)
    }

    @Test
    func testTallPresetFitDoesNotEnlargeCurrentSelection() {
        let current = CGRect(x: 0, y: 0, width: 800, height: 1200)
        let fitted = SelectionSizing.fit(
            aspectRatio: SelectionAspectRatio(width: 16, height: 9),
            inside: current
        )

        #expect(fitted.width == 800)
        #expect(fitted.height == 450)
        #expect(fitted.midX == current.midX)
        #expect(fitted.midY == current.midY)
    }

    @Test
    func testDefaultPresetSelectionFitsInsideSixtyPercentScreenBox() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let selection = SelectionSizing.defaultSelection(
            aspectRatio: SelectionAspectRatio(width: 16, height: 9),
            screenBounds: screen
        )

        #expect(selection.width == 864)
        #expect(selection.height == 486)
        #expect(selection.midX == screen.midX)
        #expect(selection.midY == screen.midY)
    }

    @Test
    func testLockedOversizedSelectionClampsWhilePreservingRatio() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let selection = SelectionSizing.centeredRect(
            around: screen.center,
            size: CGSize(width: 2000, height: 1125),
            inside: screen,
            preserving: SelectionAspectRatio(width: 16, height: 9)
        )

        #expect(selection.width == 1000)
        #expect(selection.height == 562.5)
        #expect(selection.midX == screen.midX)
        #expect(selection.midY == screen.midY)
    }

    @Test
    func testRecognizedTextLayoutOrdersLinesTopToBottomThenLeftToRight() {
        let lines = [
            RecognizedTextLine(text: "third", bounds: NormalizedImageRect(x: 0.1, y: 0.1, width: 0.2, height: 0.08), confidence: 0.8),
            RecognizedTextLine(text: "second", bounds: NormalizedImageRect(x: 0.4, y: 0.7, width: 0.2, height: 0.08), confidence: 0.9),
            RecognizedTextLine(text: "first", bounds: NormalizedImageRect(x: 0.1, y: 0.7, width: 0.2, height: 0.08), confidence: 0.95),
        ]

        let layout = RecognizedTextLayout(lines: lines)

        #expect(layout.lines.map(\.text) == ["first", "second", "third"])
        #expect(layout.fullText == "first second\nthird")
    }

    @Test
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

        #expect(layout.lines == [line])
        #expect(layout.fullText == "hello")
        #expect(layout.lines[0].bounds == line.bounds)
        #expect(layout.lines[0].confidence == 0.72)
    }

    @Test
    func testRecognizedTextLayoutEmptyResultsHaveEmptyText() {
        let layout = RecognizedTextLayout(lines: [])

        #expect(layout.lines.isEmpty)
        #expect(layout.fullText == "")
        #expect(layout.isEmpty)
    }
}
