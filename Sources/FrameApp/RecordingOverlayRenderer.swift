import AppKit
import CoreImage
import CoreMedia
import CoreText
import FrameCore

struct RecordingOverlayConfiguration: Equatable {
    let recordsMouseClicks: Bool
    let recordsKeyboardHints: Bool
    let mouseHintColor: RecordingMouseHintColor

    init(options: RecordingOptions) {
        recordsMouseClicks = options.showsMouseClickHighlights
        recordsKeyboardHints = options.showsKeyboardHints
        mouseHintColor = options.mouseHintColor
    }

    var isEnabled: Bool {
        recordsMouseClicks || recordsKeyboardHints
    }
}

struct RecordingOverlaySnapshot {
    struct Click: Equatable {
        let point: CGPoint
        let age: TimeInterval
    }

    struct KeyHint: Equatable {
        let label: String
        let age: TimeInterval
        let isTransient: Bool
    }

    let clicks: [Click]
    let keyHint: KeyHint?

    var isEmpty: Bool {
        clicks.isEmpty && keyHint == nil
    }
}

final class RecordingOverlayEventStore: @unchecked Sendable {
    private struct ClickEvent {
        let point: CGPoint
        let time: TimeInterval
    }

    private struct KeyEvent {
        let label: String
        let time: TimeInterval
    }

    private let lock = NSLock()
    private let clickDuration: TimeInterval
    private let keyDuration: TimeInterval
    private let keyboardState = RecordingOverlayKeyboardState()
    private var clicks: [ClickEvent] = []
    private var transientKeyEvents: [KeyEvent] = []

    init(clickDuration: TimeInterval = 0.45, keyDuration: TimeInterval = 0.9) {
        self.clickDuration = clickDuration
        self.keyDuration = keyDuration
    }

    func recordClick(at point: CGPoint, time: TimeInterval) {
        lock.withLock {
            clicks.append(ClickEvent(point: point, time: time))
            prune(before: time - max(clickDuration, keyDuration))
        }
    }

    func recordTransientKey(label: String, time: TimeInterval) {
        guard !label.isEmpty else {
            return
        }

        lock.withLock {
            transientKeyEvents.append(KeyEvent(label: label, time: time))
            prune(before: time - max(clickDuration, keyDuration))
        }
    }

    func updateKeyboardModifierFlags(_ modifierFlags: NSEvent.ModifierFlags, time: TimeInterval) {
        lock.withLock {
            keyboardState.updateModifierFlags(modifierFlags, time: time)
            prune(before: time - max(clickDuration, keyDuration))
        }
    }

    func recordKeyDown(keyCode: UInt16, label: String, modifierFlags: NSEvent.ModifierFlags, time: TimeInterval) {
        lock.withLock {
            keyboardState.keyDown(keyCode: keyCode, label: label, modifierFlags: modifierFlags, time: time)
            prune(before: time - max(clickDuration, keyDuration))
        }
    }

    func recordKeyUp(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, time: TimeInterval) {
        lock.withLock {
            keyboardState.keyUp(keyCode: keyCode, modifierFlags: modifierFlags, time: time)
            prune(before: time - max(clickDuration, keyDuration))
        }
    }

    func snapshot(at time: TimeInterval) -> RecordingOverlaySnapshot {
        lock.withLock {
            prune(before: time - max(clickDuration, keyDuration))
            let activeClicks = clicks.compactMap { click -> RecordingOverlaySnapshot.Click? in
                let age = time - click.time
                guard age >= 0, age <= clickDuration else {
                    return nil
                }

                return RecordingOverlaySnapshot.Click(point: click.point, age: age)
            }
            let activeKeyHint = keyboardState.snapshot(at: time).map { key in
                RecordingOverlaySnapshot.KeyHint(label: key.label, age: key.age, isTransient: false)
            }
            let transientKeyHint = transientKeyEvents.last.flatMap { key -> RecordingOverlaySnapshot.KeyHint? in
                let age = time - key.time
                guard age >= 0, age <= keyDuration else {
                    return nil
                }

                return RecordingOverlaySnapshot.KeyHint(label: key.label, age: age, isTransient: true)
            }

            return RecordingOverlaySnapshot(clicks: activeClicks, keyHint: activeKeyHint ?? transientKeyHint)
        }
    }

    private func prune(before time: TimeInterval) {
        clicks.removeAll { $0.time < time }
        transientKeyEvents.removeAll { $0.time < time }
    }
}

final class RecordingOverlayKeyboardState {
    private struct HeldKey {
        let keyCode: UInt16
        let label: String
        let pressedAt: TimeInterval
    }

    private struct ReleasedKey {
        let keyCode: UInt16
        let label: String
        let releasedAt: TimeInterval
    }

    private let releaseLingerDuration: TimeInterval
    private var modifierFlags: NSEvent.ModifierFlags = []
    private var heldKeys: [HeldKey] = []
    private var releasedKeys: [ReleasedKey] = []
    private var changedAt: TimeInterval = 0

    init(releaseLingerDuration: TimeInterval = 0.14) {
        self.releaseLingerDuration = releaseLingerDuration
    }

    func updateModifierFlags(_ modifierFlags: NSEvent.ModifierFlags, time: TimeInterval) {
        self.modifierFlags = RecordingOverlayKeyFormatter.recordableModifierFlags(modifierFlags)
        if self.modifierFlags.isEmpty && heldKeys.isEmpty {
            releasedKeys.removeAll()
        }
        changedAt = time
    }

    func keyDown(keyCode: UInt16, label: String, modifierFlags: NSEvent.ModifierFlags, time: TimeInterval) {
        updateModifierFlags(modifierFlags, time: time)
        guard !label.isEmpty,
              RecordingOverlayKeyFormatter.isModifierKeyCode(keyCode) == false else {
            return
        }

        releasedKeys.removeAll { $0.keyCode == keyCode || time - $0.releasedAt > releaseLingerDuration }
        if let index = heldKeys.firstIndex(where: { $0.keyCode == keyCode }) {
            heldKeys[index] = HeldKey(keyCode: keyCode, label: label, pressedAt: heldKeys[index].pressedAt)
        } else {
            heldKeys.append(HeldKey(keyCode: keyCode, label: label, pressedAt: time))
        }
        changedAt = time
    }

    func keyUp(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, time: TimeInterval) {
        updateModifierFlags(modifierFlags, time: time)
        if self.modifierFlags.isEmpty == false,
           let releasedKey = heldKeys.first(where: { $0.keyCode == keyCode }) {
            releasedKeys.removeAll { $0.keyCode == keyCode || time - $0.releasedAt > releaseLingerDuration }
            releasedKeys.append(ReleasedKey(keyCode: keyCode, label: releasedKey.label, releasedAt: time))
        }
        heldKeys.removeAll { $0.keyCode == keyCode }
        if self.modifierFlags.isEmpty && heldKeys.isEmpty {
            releasedKeys.removeAll()
        }
        changedAt = time
    }

    func snapshot(at time: TimeInterval) -> RecordingOverlaySnapshot.KeyHint? {
        releasedKeys.removeAll { time - $0.releasedAt > releaseLingerDuration }
        if modifierFlags.isEmpty && heldKeys.isEmpty {
            releasedKeys.removeAll()
        }
        let parts = RecordingOverlayKeyFormatter.modifierLabels(for: modifierFlags)
            + heldKeys.map(\.label)
            + releasedKeys.map(\.label)
        guard parts.isEmpty == false else {
            return nil
        }

        return RecordingOverlaySnapshot.KeyHint(label: parts.joined(), age: max(0, time - changedAt), isTransient: false)
    }
}

enum RecordingOverlayCoordinateMapper {
    static func pixelPoint(screenPoint: CGPoint, selectionRect: CGRect, pixelSize: CGSize) -> CGPoint {
        let scaleX = pixelSize.width / max(1, selectionRect.width)
        let scaleY = pixelSize.height / max(1, selectionRect.height)
        return CGPoint(
            x: (screenPoint.x - selectionRect.minX) * scaleX,
            y: (selectionRect.maxY - screenPoint.y) * scaleY
        )
    }
}

enum RecordingOverlayKeyFormatter {
    static func label(
        charactersIgnoringModifiers: String?,
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> String {
        let key = normalizedKey(charactersIgnoringModifiers, keyCode: keyCode)
        guard !key.isEmpty else {
            return ""
        }

        let parts = modifierLabels(for: modifierFlags) + [key]
        return parts.joined()
    }

    static func modifierLabels(for modifierFlags: NSEvent.ModifierFlags) -> [String] {
        var parts: [String] = []
        if modifierFlags.contains(.command) {
            parts.append("⌘")
        }
        if modifierFlags.contains(.shift) {
            parts.append("⇧")
        }
        if modifierFlags.contains(.option) {
            parts.append("⌥")
        }
        if modifierFlags.contains(.control) {
            parts.append("⌃")
        }
        if modifierFlags.contains(.function) {
            parts.append("fn")
        }
        return parts
    }

    static func recordableModifierFlags(_ modifierFlags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        modifierFlags.intersection([.command, .shift, .option, .control, .function])
    }

    static func isModifierKeyCode(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    private static func normalizedKey(_ characters: String?, keyCode: UInt16) -> String {
        if let characters, let first = characters.first {
            switch first {
            case "\u{1b}":
                return "esc"
            case "\r", "\n":
                return "↩"
            case "\t":
                return "⇥"
            case " ":
                return "␣"
            case "\u{7f}":
                return "⌫"
            case "\u{F700}":
                return "↑"
            case "\u{F701}":
                return "↓"
            case "\u{F702}":
                return "←"
            case "\u{F703}":
                return "→"
            default:
                return String(first).uppercased()
            }
        }

        switch keyCode {
        case 0:
            return "A"
        case 1:
            return "S"
        case 2:
            return "D"
        case 3:
            return "F"
        case 4:
            return "H"
        case 5:
            return "G"
        case 6:
            return "Z"
        case 7:
            return "X"
        case 8:
            return "C"
        case 9:
            return "V"
        case 11:
            return "B"
        case 12:
            return "Q"
        case 13:
            return "W"
        case 14:
            return "E"
        case 15:
            return "R"
        case 16:
            return "Y"
        case 17:
            return "T"
        case 18:
            return "1"
        case 19:
            return "2"
        case 20:
            return "3"
        case 21:
            return "4"
        case 22:
            return "6"
        case 23:
            return "5"
        case 24:
            return "="
        case 25:
            return "9"
        case 26:
            return "7"
        case 27:
            return "-"
        case 28:
            return "8"
        case 29:
            return "0"
        case 30:
            return "]"
        case 31:
            return "O"
        case 32:
            return "U"
        case 33:
            return "["
        case 34:
            return "I"
        case 35:
            return "P"
        case 36:
            return "↩"
        case 37:
            return "L"
        case 38:
            return "J"
        case 39:
            return "'"
        case 40:
            return "K"
        case 41:
            return ";"
        case 42:
            return "\\"
        case 43:
            return ","
        case 44:
            return "/"
        case 45:
            return "N"
        case 46:
            return "M"
        case 47:
            return "."
        case 48:
            return "⇥"
        case 49:
            return "␣"
        case 50:
            return "`"
        case 51:
            return "⌫"
        case 53:
            return "esc"
        case 57:
            return "⇪"
        case 63:
            return "fn"
        case 71:
            return "Clear"
        case 76:
            return "Enter"
        case 117:
            return "⌦"
        case 115:
            return "Home"
        case 116:
            return "Page Up"
        case 119:
            return "End"
        case 121:
            return "Page Down"
        case 123:
            return "←"
        case 124:
            return "→"
        case 125:
            return "↓"
        case 126:
            return "↑"
        case 122:
            return "F1"
        case 120:
            return "F2"
        case 99:
            return "F3"
        case 118:
            return "F4"
        case 96:
            return "F5"
        case 97:
            return "F6"
        case 98:
            return "F7"
        case 100:
            return "F8"
        case 101:
            return "F9"
        case 109:
            return "F10"
        case 103:
            return "F11"
        case 111:
            return "F12"
        default:
            return ""
        }
    }
}

final class RecordingOverlayRenderer {
    private let eventStore: RecordingOverlayEventStore
    private let pixelSize: CGSize
    private let mouseHintColor: RecordingMouseHintColor
    private let ciContext = CIContext()

    init(
        eventStore: RecordingOverlayEventStore,
        pixelSize: CGSize,
        mouseHintColor: RecordingMouseHintColor = .default
    ) {
        self.eventStore = eventStore
        self.pixelSize = pixelSize
        self.mouseHintColor = mouseHintColor
    }

    func render(pixelBuffer: CVPixelBuffer, at presentationTime: CMTime) -> CVPixelBuffer? {
        let snapshot = eventStore.snapshot(at: presentationTime.seconds)
        guard !snapshot.isEmpty else {
            return pixelBuffer
        }

        guard let outputBuffer = makePixelBufferLike(pixelBuffer) else {
            return pixelBuffer
        }

        ciContext.render(CIImage(cvPixelBuffer: pixelBuffer), to: outputBuffer)
        draw(snapshot: snapshot, into: outputBuffer)
        return outputBuffer
    }

    private func makePixelBufferLike(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var output: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(source),
            CVPixelBufferGetHeight(source),
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            ] as CFDictionary,
            &output
        )
        guard status == kCVReturnSuccess else {
            return nil
        }

        return output
    }

    private func draw(snapshot: RecordingOverlaySnapshot, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: baseAddress,
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return
        }

        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        context.saveGState()
        context.translateBy(x: 0, y: height)
        context.scaleBy(x: 1, y: -1)

        for click in snapshot.clicks {
            drawClick(click, in: context)
        }
        if let keyHint = snapshot.keyHint {
            drawKeyHint(keyHint, in: context)
        }

        context.restoreGState()
    }

    private func drawClick(_ click: RecordingOverlaySnapshot.Click, in context: CGContext) {
        let progress = min(1, max(0, click.age / 0.45))
        let radius = 12 + progress * 20
        let alpha = 1 - progress
        let rect = CGRect(
            x: click.point.x - radius,
            y: click.point.y - radius,
            width: radius * 2,
            height: radius * 2
        )

        context.setFillColor(mouseHintColor.nsColor.withAlphaComponent(0.18 * alpha).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.92 * alpha).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: rect)
        context.setStrokeColor(mouseHintColor.nsColor.withAlphaComponent(0.78 * alpha).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect.insetBy(dx: 4, dy: 4))
    }

    private func drawKeyHint(_ keyHint: RecordingOverlaySnapshot.KeyHint, in context: CGContext) {
        let progress = min(1, max(0, keyHint.age / 0.9))
        let alpha = keyHint.isTransient && progress >= 0.78 ? max(0, 1 - ((progress - 0.78) / 0.22)) : 1
        let minDimension = min(pixelSize.width, pixelSize.height)
        let fontSize = min(46, max(20, minDimension * 0.16))
        let font = CTFontCreateWithName("Menlo-Semibold" as CFString, fontSize, nil)
        let textColor = CGColor(
            srgbRed: 1,
            green: 1,
            blue: 1,
            alpha: 0.95 * alpha
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): textColor,
        ]
        let attributedString = NSAttributedString(string: keyHint.label, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributedString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let textHeight = ascent + descent
        let horizontalPadding = max(12, fontSize * 0.48)
        let verticalPadding = max(6, fontSize * 0.28)
        let maxPillWidth = max(48, pixelSize.width - 24)
        let pillSize = CGSize(
            width: min(maxPillWidth, max(fontSize * 2.2, textWidth + horizontalPadding * 2)),
            height: textHeight + verticalPadding * 2
        )
        let rect = CGRect(
            x: floor((pixelSize.width - pillSize.width) / 2),
            y: max(10, pixelSize.height - pillSize.height - max(12, fontSize * 0.6)),
            width: pillSize.width,
            height: pillSize.height
        )
        let radius = min(22, pillSize.height / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.setFillColor(NSColor.black.withAlphaComponent(0.58 * alpha).cgColor)
        context.addPath(path)
        context.fillPath()

        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(
            x: rect.midX - textWidth / 2,
            y: (pillSize.height - textHeight) / 2 + descent
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

extension RecordingMouseHintColor {
    var nsColor: NSColor {
        NSColor(
            srgbRed: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: CGFloat(alpha)
        )
    }
}
