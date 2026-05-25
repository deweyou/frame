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

    @Test
    func testWindowHoverActivatesAfterDelayForSameCandidate() {
        let candidate = WindowCandidate(
            id: 42,
            ownerProcessID: 100,
            bounds: CGRect(x: 10, y: 20, width: 320, height: 240)
        )
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 40, y: 60),
            isOverHUD: false,
            timestamp: 1.0
        ) == nil)
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 42, y: 61),
            isOverHUD: false,
            timestamp: 1.34
        ) == nil)
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 42, y: 61),
            isOverHUD: false,
            timestamp: 1.35
        ) == candidate)
    }

    @Test
    func testWindowHoverCancelsWhenMouseEntersHUD() {
        let candidate = WindowCandidate(
            id: 8,
            ownerProcessID: 100,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 120)
        )
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        _ = selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 10, y: 10),
            isOverHUD: false,
            timestamp: 2.0
        )
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 10, y: 10),
            isOverHUD: true,
            timestamp: 2.4
        ) == nil)
        #expect(selector.activeCandidate == nil)
    }

    @Test
    func testWindowHoverRestartsForDifferentCandidate() {
        let first = WindowCandidate(
            id: 1,
            ownerProcessID: 100,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        let second = WindowCandidate(
            id: 2,
            ownerProcessID: 101,
            bounds: CGRect(x: 220, y: 0, width: 200, height: 200)
        )
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        _ = selector.update(
            candidate: first,
            mouseLocation: CGPoint(x: 20, y: 20),
            isOverHUD: false,
            timestamp: 1.0
        )
        #expect(selector.update(
            candidate: second,
            mouseLocation: CGPoint(x: 230, y: 20),
            isOverHUD: false,
            timestamp: 1.4
        ) == nil)
        #expect(selector.update(
            candidate: second,
            mouseLocation: CGPoint(x: 230, y: 20),
            isOverHUD: false,
            timestamp: 1.75
        ) == second)
    }

    @Test
    func testRegionEditingDisablesAutomaticHoverForSession() {
        let candidate = WindowCandidate(
            id: 3,
            ownerProcessID: 100,
            bounds: CGRect(x: 0, y: 0, width: 200, height: 200)
        )
        var selector = WindowHoverSelection(activationDelay: 0.35, movementTolerance: 6)

        selector.lockRegionEditingForSession()

        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 20, y: 20),
            isOverHUD: false,
            timestamp: 1.0
        ) == nil)
        #expect(selector.update(
            candidate: candidate,
            mouseLocation: CGPoint(x: 20, y: 20),
            isOverHUD: false,
            timestamp: 2.0
        ) == nil)
        #expect(selector.isRegionLockedForSession)
    }
}
