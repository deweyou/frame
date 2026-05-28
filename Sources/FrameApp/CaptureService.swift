import AppKit
import CoreGraphics
import FrameCore
import ScreenCaptureKit

struct CapturedScreenshot {
    let id = UUID()
    let pngData: Data
    let image: NSImage
    let rect: CGRect
}

@MainActor
final class CaptureService {
    func capture(selection: SelectionCapture) async throws -> CapturedScreenshot {
        switch selection.kind {
        case .region:
            return try capture(rect: selection.rect)
        case let .window(id):
            return try await captureWindow(id: id, rect: selection.rect)
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

    private func captureWindow(id: UInt32, rect: CGRect) async throws -> CapturedScreenshot {
        let scale = screen(for: rect)?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 1

        if let cgImage = try? await captureWindowWithScreenCaptureKit(id: id, rect: rect, scale: scale),
           let screenshot = try? screenshot(from: cgImage, rect: rect, scale: scale) {
            return screenshot
        }

        if let cgImage = captureWindowWithCoreGraphics(id: id),
           let screenshot = try? screenshot(from: cgImage, rect: rect, scale: scale) {
            return screenshot
        }

        return try capture(rect: rect)
    }

    private func captureWindowWithScreenCaptureKit(id: UInt32, rect: CGRect, scale: CGFloat) async throws -> CGImage? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(id) }) else {
            return nil
        }

        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window),
            configuration: makeSingleWindowCaptureConfiguration(rect: rect, scale: scale)
        )
        return croppedToVisibleContent(image)
    }

    private func captureWindowWithCoreGraphics(id: UInt32) -> CGImage? {
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            CGWindowID(id),
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            return nil
        }

        return croppedToVisibleContent(image)
    }

    private func screenshot(from cgImage: CGImage, rect: CGRect, scale: CGFloat) throws -> CapturedScreenshot {
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

func makeSingleWindowCaptureConfiguration(rect: CGRect, scale: CGFloat) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    configuration.width = max(1, Int((rect.width * scale).rounded()))
    configuration.height = max(1, Int((rect.height * scale).rounded()))
    configuration.showsCursor = false
    configuration.ignoreShadowsSingleWindow = true
    return configuration
}

func croppedToVisibleContent(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
        return nil
    }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo
    ) else {
        return image
    }

    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    let cropRect = contentBounds(
        in: pixels,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        minimumAlpha: 128
    ) ?? contentBounds(
        in: pixels,
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        minimumAlpha: 2
    )

    guard let cropRect else {
        return nil
    }

    guard cropRect != CGRect(x: 0, y: 0, width: width, height: height) else {
        return image
    }

    return image.cropping(to: cropRect)
}

private func contentBounds(
    in pixels: [UInt8],
    width: Int,
    height: Int,
    bytesPerRow: Int,
    minimumAlpha: UInt8
) -> CGRect? {
    let bytesPerPixel = 4
    var minX = width
    var minY = height
    var maxX = -1
    var maxY = -1

    for y in 0..<height {
        for x in 0..<width {
            let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
            guard alpha >= minimumAlpha else {
                continue
            }

            minX = min(minX, x)
            minY = min(minY, y)
            maxX = max(maxX, x)
            maxY = max(maxY, y)
        }
    }

    guard maxX >= minX, maxY >= minY else {
        return nil
    }

    return CGRect(
        x: minX,
        y: minY,
        width: maxX - minX + 1,
        height: maxY - minY + 1
    )
}

private enum CaptureServiceError: Error, LocalizedError {
    case invalidSelectionRect(CGRect)
    case captureFailed(rect: CGRect, captureRect: CGRect)
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case let .invalidSelectionRect(rect):
            "选择区域无效：\(rect.debugDescription)"
        case let .captureFailed(rect, captureRect):
            "系统截图失败。选择区域：\(rect.debugDescription)，捕获区域：\(captureRect.debugDescription)"
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
