import AppKit
import CoreGraphics
import FrameCore

struct CapturedScreenshot {
    let pngData: Data
    let image: NSImage
    let rect: CGRect
}

@MainActor
final class CaptureService {
    func capture(selection: SelectionCapture) throws -> CapturedScreenshot {
        switch selection.kind {
        case .region:
            return try capture(rect: selection.rect)
        case let .window(id):
            return try captureWindow(id: id, rect: selection.rect)
        }
    }

    func capture(rect: CGRect) throws -> CapturedScreenshot {
        guard !rect.isNull,
              !rect.isEmpty,
              rect.width > 0,
              rect.height > 0 else {
            throw CaptureServiceError.invalidSelectionRect(rect)
        }

        let captureRect = quartzCaptureRect(for: rect)
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        ) else {
            throw CaptureServiceError.captureFailed(rect: rect, captureRect: captureRect)
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRepresentation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CaptureServiceError.pngEncodingFailed
        }

        let image = NSImage(cgImage: cgImage, size: rect.size)
        return CapturedScreenshot(pngData: pngData, image: image, rect: rect)
    }

    private func captureWindow(id: UInt32, rect: CGRect) throws -> CapturedScreenshot {
        guard !rect.isNull,
              !rect.isEmpty,
              rect.width > 0,
              rect.height > 0 else {
            throw CaptureServiceError.invalidSelectionRect(rect)
        }

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(id),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            throw CaptureServiceError.windowCaptureFailed(id: id, rect: rect)
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRepresentation.representation(
            using: .png,
            properties: [:]
        ) else {
            throw CaptureServiceError.pngEncodingFailed
        }

        let image = NSImage(cgImage: cgImage, size: rect.size)
        return CapturedScreenshot(pngData: pngData, image: image, rect: rect)
    }

    private func quartzCaptureRect(for cocoaRect: CGRect) -> CGRect {
        guard let screen = screen(for: cocoaRect),
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return cocoaRect
        }

        let displayID = CGDirectDisplayID(displayNumber.uint32Value)
        let displayBounds = CGDisplayBounds(displayID)
        let localMinX = cocoaRect.minX - screen.frame.minX
        let localMinY = cocoaRect.minY - screen.frame.minY

        return CGRect(
            x: displayBounds.minX + localMinX,
            y: displayBounds.maxY - localMinY - cocoaRect.height,
            width: cocoaRect.width,
            height: cocoaRect.height
        )
    }

    private func screen(for rect: CGRect) -> NSScreen? {
        let rectCenter = CGPoint(x: rect.midX, y: rect.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(rectCenter) }) {
            return containingScreen
        }

        return NSScreen.screens.max { firstScreen, secondScreen in
            firstScreen.frame.intersection(rect).area < secondScreen.frame.intersection(rect).area
        }
    }
}

private enum CaptureServiceError: Error, LocalizedError {
    case invalidSelectionRect(CGRect)
    case captureFailed(rect: CGRect, captureRect: CGRect)
    case windowCaptureFailed(id: UInt32, rect: CGRect)
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case let .invalidSelectionRect(rect):
            "选择区域无效：\(rect.debugDescription)"
        case let .captureFailed(rect, captureRect):
            "系统截图失败。选择区域：\(rect.debugDescription)，捕获区域：\(captureRect.debugDescription)"
        case let .windowCaptureFailed(id, rect):
            "系统窗口截图失败。窗口 ID：\(id)，选择区域：\(rect.debugDescription)"
        case .pngEncodingFailed:
            "截图 PNG 编码失败。"
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else {
            return 0
        }

        return width * height
    }
}
