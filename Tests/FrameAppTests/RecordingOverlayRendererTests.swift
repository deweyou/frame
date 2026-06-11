import CoreMedia
import FrameCore
import XCTest
@testable import FrameApp

final class RecordingOverlayRendererTests: XCTestCase {
    func testMouseLocationMapsIntoRecordingPixelCoordinates() {
        let point = RecordingOverlayCoordinateMapper.pixelPoint(
            screenPoint: CGPoint(x: 150, y: 180),
            selectionRect: CGRect(x: 100, y: 100, width: 100, height: 100),
            pixelSize: CGSize(width: 200, height: 200)
        )

        XCTAssertEqual(point, CGPoint(x: 100, y: 40))
    }

    func testKeyEventLabelUsesModifierSymbolsAndUppercaseCharacter() {
        let label = RecordingOverlayKeyFormatter.label(
            charactersIgnoringModifiers: "p",
            keyCode: 35,
            modifierFlags: [.command, .shift]
        )

        XCTAssertEqual(label, "⌘⇧P")
    }

    func testKeyEventLabelShowsPlainTextInputWithoutShortcutModifiers() {
        let label = RecordingOverlayKeyFormatter.label(
            charactersIgnoringModifiers: "a",
            keyCode: 0,
            modifierFlags: []
        )

        XCTAssertEqual(label, "A")
    }

    func testKeyEventLabelAllowsNamedKeysWithoutShortcutModifiers() {
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: " ", keyCode: 49, modifierFlags: []), "␣")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\u{1b}", keyCode: 53, modifierFlags: []), "esc")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\r", keyCode: 36, modifierFlags: []), "↩")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\t", keyCode: 48, modifierFlags: []), "⇥")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\u{7f}", keyCode: 51, modifierFlags: []), "⌫")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\u{F700}", keyCode: 126, modifierFlags: []), "↑")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\u{F701}", keyCode: 125, modifierFlags: []), "↓")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\u{F702}", keyCode: 123, modifierFlags: []), "←")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: "\u{F703}", keyCode: 124, modifierFlags: []), "→")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 122, modifierFlags: []), "F1")
    }

    func testKeyEventLabelFallsBackToKeyCodeForGlobalEventTapKeys() {
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 0, modifierFlags: []), "A")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 11, modifierFlags: []), "B")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 18, modifierFlags: []), "1")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 29, modifierFlags: []), "0")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 49, modifierFlags: []), "␣")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 63, modifierFlags: []), "fn")
        XCTAssertEqual(RecordingOverlayKeyFormatter.label(charactersIgnoringModifiers: nil, keyCode: 57, modifierFlags: []), "⇪")
    }

    func testModifierLabelsIncludeFunctionButDoNotPersistCapsLockState() {
        XCTAssertEqual(
            RecordingOverlayKeyFormatter.modifierLabels(for: [.capsLock, .function, .command]),
            ["⌘", "fn"]
        )
    }

    func testKeyboardStateDisplaysHeldModifiersAndKeysUntilReleased() {
        let state = RecordingOverlayKeyboardState()

        state.updateModifierFlags(.command, time: 1)
        XCTAssertEqual(state.snapshot(at: 1)?.label, "⌘")

        state.updateModifierFlags([.command, .shift], time: 1.1)
        XCTAssertEqual(state.snapshot(at: 1.1)?.label, "⌘⇧")

        state.keyDown(keyCode: 0, label: "A", modifierFlags: [.command, .shift], time: 1.2)
        XCTAssertEqual(state.snapshot(at: 1.2)?.label, "⌘⇧A")

        state.keyUp(keyCode: 0, modifierFlags: [.command, .shift], time: 1.3)
        XCTAssertEqual(state.snapshot(at: 1.3)?.label, "⌘⇧A")
        XCTAssertEqual(state.snapshot(at: 1.5)?.label, "⌘⇧")

        state.updateModifierFlags([], time: 1.4)
        XCTAssertNil(state.snapshot(at: 1.4))
    }

    func testKeyboardStateClearsImmediatelyWhenAllKeysAreReleased() {
        let state = RecordingOverlayKeyboardState(releaseLingerDuration: 0.16)

        state.keyDown(keyCode: 0, label: "A", modifierFlags: [], time: 1)
        state.keyUp(keyCode: 0, modifierFlags: [], time: 1.03)

        XCTAssertNil(state.snapshot(at: 1.03))
        XCTAssertNil(state.snapshot(at: 1.08))
    }

    func testKeyboardStateKeepsReleasedKeyBrieflyWhenModifiersRemainHeld() {
        let state = RecordingOverlayKeyboardState(releaseLingerDuration: 0.16)

        let modifiers: NSEvent.ModifierFlags = [.command, .shift]
        state.updateModifierFlags(modifiers, time: 1)
        state.keyDown(keyCode: 0, label: "A", modifierFlags: modifiers, time: 1.02)
        state.keyUp(keyCode: 0, modifierFlags: modifiers, time: 1.04)

        XCTAssertEqual(state.snapshot(at: 1.08)?.label, "⌘⇧A")
        XCTAssertEqual(state.snapshot(at: 1.24)?.label, "⌘⇧")

        state.updateModifierFlags([], time: 1.25)
        XCTAssertNil(state.snapshot(at: 1.25))
    }

    func testEventStoreReturnsOnlyActiveEvents() {
        let store = RecordingOverlayEventStore()
        store.recordClick(at: CGPoint(x: 10, y: 10), time: 1)
        store.recordKeyDown(keyCode: 0, label: "A", modifierFlags: [], time: 1)

        XCTAssertEqual(store.snapshot(at: 1.2).clicks.count, 1)
        XCTAssertEqual(store.snapshot(at: 1.2).keyHint?.label, "A")
        XCTAssertEqual(store.snapshot(at: 2.2).clicks.count, 0)
        XCTAssertEqual(store.snapshot(at: 2.2).keyHint?.label, "A")
        store.recordKeyUp(keyCode: 0, modifierFlags: [], time: 2.3)
        XCTAssertNil(store.snapshot(at: 2.5).keyHint)
    }

    func testRendererChangesPixelsWhenClickOverlayIsActive() throws {
        let source = try makePixelBuffer(width: 80, height: 80, fill: (30, 30, 30, 255))
        let store = RecordingOverlayEventStore()
        store.recordClick(at: CGPoint(x: 40, y: 40), time: 1)
        let renderer = RecordingOverlayRenderer(eventStore: store, pixelSize: CGSize(width: 80, height: 80))

        let rendered = try XCTUnwrap(renderer.render(pixelBuffer: source, at: CMTime(seconds: 1.1, preferredTimescale: 600)))

        XCTAssertNotEqual(pixel(at: CGPoint(x: 40, y: 40), in: rendered), pixel(at: CGPoint(x: 40, y: 40), in: source))
    }

    func testRendererUsesConfiguredMouseHintColorForClickOverlay() throws {
        let source = try makePixelBuffer(width: 80, height: 80, fill: (30, 30, 30, 255))
        let store = RecordingOverlayEventStore()
        store.recordClick(at: CGPoint(x: 40, y: 40), time: 1)
        let renderer = RecordingOverlayRenderer(
            eventStore: store,
            pixelSize: CGSize(width: 80, height: 80),
            mouseHintColor: RecordingMouseHintColor(red: 0, green: 0.2, blue: 1, alpha: 1)
        )

        let rendered = try XCTUnwrap(renderer.render(pixelBuffer: source, at: CMTime(seconds: 1, preferredTimescale: 600)))
        let renderedPixel = pixel(at: CGPoint(x: 44, y: 40), in: rendered)

        XCTAssertGreaterThan(renderedPixel[0], renderedPixel[2])
    }

    func testRendererDrawsKeyboardHintFromBackgroundQueue() throws {
        let source = try makePixelBuffer(width: 180, height: 120, fill: (30, 30, 30, 255))
        let store = RecordingOverlayEventStore()
        store.recordTransientKey(label: "⌘⇧A", time: 1)
        let renderer = RecordingOverlayRenderer(eventStore: store, pixelSize: CGSize(width: 180, height: 120))

        let rendered = DispatchQueue.global(qos: .userInitiated).sync {
            renderer.render(pixelBuffer: source, at: CMTime(seconds: 1.1, preferredTimescale: 600))
        }

        let output = try XCTUnwrap(rendered)
        XCTAssertNotEqual(pixel(at: CGPoint(x: 90, y: 84), in: output), pixel(at: CGPoint(x: 90, y: 84), in: source))
    }

    func testRendererKeepsHeldKeyboardHintVisibleUntilKeyUp() throws {
        let source = try makePixelBuffer(width: 220, height: 140, fill: (30, 30, 30, 255))
        let store = RecordingOverlayEventStore()
        store.recordKeyDown(keyCode: 0, label: "A", modifierFlags: [.command, .shift], time: 1)
        let renderer = RecordingOverlayRenderer(eventStore: store, pixelSize: CGSize(width: 220, height: 140))

        let heldOutput = try XCTUnwrap(renderer.render(pixelBuffer: source, at: CMTime(seconds: 10, preferredTimescale: 600)))
        XCTAssertNotEqual(pixel(at: CGPoint(x: 110, y: 98), in: heldOutput), pixel(at: CGPoint(x: 110, y: 98), in: source))

        store.recordKeyUp(keyCode: 0, modifierFlags: [], time: 10.1)
        let releasedOutput = try XCTUnwrap(renderer.render(pixelBuffer: source, at: CMTime(seconds: 10.3, preferredTimescale: 600)))
        XCTAssertTrue(releasedOutput === source)
    }

    func testRendererReturnsOriginalBufferWhenNoOverlayIsActive() throws {
        let source = try makePixelBuffer(width: 40, height: 40, fill: (20, 20, 20, 255))
        let renderer = RecordingOverlayRenderer(eventStore: RecordingOverlayEventStore(), pixelSize: CGSize(width: 40, height: 40))

        let rendered = try XCTUnwrap(renderer.render(pixelBuffer: source, at: CMTime(seconds: 3, preferredTimescale: 600)))

        XCTAssertTrue(rendered === source)
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        fill: (UInt8, UInt8, UInt8, UInt8)
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, [])
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(buffer))
        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                row[x * 4] = fill.2
                row[x * 4 + 1] = fill.1
                row[x * 4 + 2] = fill.0
                row[x * 4 + 3] = fill.3
            }
        }
        return buffer
    }

    private func pixel(at point: CGPoint, in buffer: CVPixelBuffer) -> [UInt8] {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let base = CVPixelBufferGetBaseAddress(buffer)!
        let index = Int(point.y) * bytesPerRow + Int(point.x) * 4
        let pixel = base.advanced(by: index).assumingMemoryBound(to: UInt8.self)
        return [pixel[0], pixel[1], pixel[2], pixel[3]]
    }
}
