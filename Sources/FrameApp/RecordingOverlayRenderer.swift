import AppKit
import CoreImage
import CoreMedia
import FrameCore

struct RecordingOverlayConfiguration: Equatable {
    let recordsMouseClicks: Bool
    let recordsKeyboardHints: Bool

    init(options: RecordingOptions) {
        recordsMouseClicks = options.showsCursor
        recordsKeyboardHints = options.showsKeyboardHints
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
    private var clicks: [ClickEvent] = []
    private var keyEvents: [KeyEvent] = []

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

    func recordKey(label: String, time: TimeInterval) {
        guard !label.isEmpty else {
            return
        }

        lock.withLock {
            keyEvents.append(KeyEvent(label: label, time: time))
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
            let keyHint = keyEvents.last.flatMap { key -> RecordingOverlaySnapshot.KeyHint? in
                let age = time - key.time
                guard age >= 0, age <= keyDuration else {
                    return nil
                }

                return RecordingOverlaySnapshot.KeyHint(label: key.label, age: age)
            }

            return RecordingOverlaySnapshot(clicks: activeClicks, keyHint: keyHint)
        }
    }

    private func prune(before time: TimeInterval) {
        clicks.removeAll { $0.time < time }
        keyEvents.removeAll { $0.time < time }
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
    static func label(charactersIgnoringModifiers: String?, modifierFlags: NSEvent.ModifierFlags) -> String {
        let key = normalizedKey(charactersIgnoringModifiers)
        guard !key.isEmpty else {
            return ""
        }

        var parts: [String] = []
        if modifierFlags.contains(.command) {
            parts.append("⌘")
        }
        if modifierFlags.contains(.option) {
            parts.append("⌥")
        }
        if modifierFlags.contains(.control) {
            parts.append("⌃")
        }
        if modifierFlags.contains(.shift) {
            parts.append("⇧")
        }
        parts.append(key)
        return parts.joined()
    }

    private static func normalizedKey(_ characters: String?) -> String {
        guard let characters, let first = characters.first else {
            return ""
        }

        switch first {
        case "\u{1b}":
            return "Esc"
        case "\r", "\n":
            return "Return"
        case "\t":
            return "Tab"
        case " ":
            return "Space"
        default:
            return String(first).uppercased()
        }
    }
}

final class RecordingOverlayRenderer {
    private let eventStore: RecordingOverlayEventStore
    private let pixelSize: CGSize
    private let ciContext = CIContext()

    init(eventStore: RecordingOverlayEventStore, pixelSize: CGSize) {
        self.eventStore = eventStore
        self.pixelSize = pixelSize
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

        context.setFillColor(NSColor.systemRed.withAlphaComponent(0.18 * alpha).cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.92 * alpha).cgColor)
        context.setLineWidth(3)
        context.strokeEllipse(in: rect)
        context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.78 * alpha).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect.insetBy(dx: 4, dy: 4))
    }

    private func drawKeyHint(_ keyHint: RecordingOverlaySnapshot.KeyHint, in context: CGContext) {
        let progress = min(1, max(0, keyHint.age / 0.9))
        let alpha = progress < 0.78 ? 1 : max(0, 1 - ((progress - 0.78) / 0.22))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white.withAlphaComponent(0.95 * alpha),
        ]
        let textSize = (keyHint.label as NSString).size(withAttributes: attributes)
        let horizontalPadding: CGFloat = 18
        let pillSize = CGSize(width: max(68, textSize.width + horizontalPadding * 2), height: 38)
        let rect = CGRect(
            x: floor((pixelSize.width - pillSize.width) / 2),
            y: max(14, pixelSize.height - pillSize.height - 18),
            width: pillSize.width,
            height: pillSize.height
        )
        let path = CGPath(roundedRect: rect, cornerWidth: 19, cornerHeight: 19, transform: nil)
        context.setFillColor(NSColor.black.withAlphaComponent(0.58 * alpha).cgColor)
        context.addPath(path)
        context.fillPath()

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (keyHint.label as NSString).draw(
            in: CGRect(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2,
                width: textSize.width,
                height: textSize.height
            ),
            withAttributes: attributes
        )
        NSGraphicsContext.restoreGraphicsState()
    }
}
