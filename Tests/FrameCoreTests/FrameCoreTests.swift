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
}
