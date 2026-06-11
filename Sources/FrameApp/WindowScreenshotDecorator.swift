import AppKit
import CoreGraphics

enum WindowScreenshotDecorationStyle: String, CaseIterable, Identifiable {
    case softBackdrop
    case canvasGlow
    case transparentShadow

    var id: String {
        rawValue
    }

    func displayName(strings: AppStrings) -> String {
        strings.windowScreenshotDecorationStyleName(self)
    }
}

struct WindowScreenshotDecorator {
    func decoratedImage(
        from image: CGImage,
        style: WindowScreenshotDecorationStyle
    ) -> CGImage? {
        let sourceSize = CGSize(width: image.width, height: image.height)
        let layout = WindowScreenshotDecorationLayout(sourceSize: sourceSize, style: style)

        guard layout.canvasSize.width > 0, layout.canvasSize.height > 0 else {
            return nil
        }

        let width = Int(layout.canvasSize.width.rounded(.up))
        let height = Int(layout.canvasSize.height.rounded(.up))
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let canvasRect = CGRect(x: 0, y: 0, width: width, height: height)
        drawBackground(style: style, in: canvasRect, context: context)

        drawWindowShadow(in: layout.imageRect, layout: layout, context: context)
        drawWindowImage(image, in: layout.imageRect, cornerRadius: layout.cornerRadius, context: context)
        drawWindowStroke(in: layout.imageRect, cornerRadius: layout.cornerRadius, context: context)

        return context.makeImage()
    }

    func decoratedScreenshot(
        from image: CGImage,
        sourceRect: CGRect,
        scale: CGFloat,
        style: WindowScreenshotDecorationStyle
    ) throws -> CapturedScreenshot {
        guard let decoratedImage = decoratedImage(from: image, style: style) else {
            throw WindowScreenshotDecoratorError.renderFailed
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: decoratedImage)
        guard let pngData = bitmapRepresentation.representation(using: .png, properties: [:]) else {
            throw WindowScreenshotDecoratorError.pngEncodingFailed
        }

        let imageScale = max(scale, 1)
        let imageSize = CGSize(
            width: CGFloat(decoratedImage.width) / imageScale,
            height: CGFloat(decoratedImage.height) / imageScale
        )
        return CapturedScreenshot(
            pngData: pngData,
            image: NSImage(cgImage: decoratedImage, size: imageSize),
            rect: CGRect(origin: sourceRect.origin, size: imageSize)
        )
    }

    private func drawBackground(
        style: WindowScreenshotDecorationStyle,
        in rect: CGRect,
        context: CGContext
    ) {
        switch style {
        case .softBackdrop:
            context.setFillColor(NSColor(red: 0.94, green: 0.95, blue: 0.93, alpha: 1).cgColor)
            context.fill(rect)
            drawLinearGradient(
                colors: [
                    NSColor(red: 0.90, green: 0.93, blue: 0.91, alpha: 1).cgColor,
                    NSColor(red: 0.98, green: 0.94, blue: 0.87, alpha: 1).cgColor,
                ],
                in: rect,
                context: context
            )
        case .canvasGlow:
            context.setFillColor(NSColor(red: 0.88, green: 0.91, blue: 0.94, alpha: 1).cgColor)
            context.fill(rect)
            drawLinearGradient(
                colors: [
                    NSColor(red: 0.78, green: 0.88, blue: 0.86, alpha: 1).cgColor,
                    NSColor(red: 0.96, green: 0.90, blue: 0.82, alpha: 1).cgColor,
                    NSColor(red: 0.90, green: 0.84, blue: 0.92, alpha: 1).cgColor,
                ],
                in: rect,
                context: context
            )
        case .transparentShadow:
            context.clear(rect)
        }
    }

    private func drawLinearGradient(colors: [CGColor], in rect: CGRect, context: CGContext) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: nil
        ) else {
            return
        }

        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.maxY),
            end: CGPoint(x: rect.maxX, y: rect.minY),
            options: []
        )
    }

    private func drawWindowShadow(
        in rect: CGRect,
        layout: WindowScreenshotDecorationLayout,
        context: CGContext
    ) {
        drawShadowLayer(
            in: rect,
            cornerRadius: layout.cornerRadius,
            offset: layout.ambientShadowOffset,
            blur: layout.ambientShadowBlur,
            alpha: layout.ambientShadowAlpha,
            context: context
        )
        drawShadowLayer(
            in: rect.insetBy(dx: 2, dy: 2),
            cornerRadius: max(0, layout.cornerRadius - 2),
            offset: layout.contactShadowOffset,
            blur: layout.contactShadowBlur,
            alpha: layout.contactShadowAlpha,
            context: context
        )
    }

    private func drawShadowLayer(
        in rect: CGRect,
        cornerRadius: CGFloat,
        offset: CGSize,
        blur: CGFloat,
        alpha: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        context.setShadow(
            offset: offset,
            blur: blur,
            color: NSColor.black.withAlphaComponent(alpha).cgColor
        )
        context.setFillColor(NSColor.black.withAlphaComponent(0.24).cgColor)
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        ))
        context.fillPath()
        context.restoreGState()
    }

    private func drawWindowImage(
        _ image: CGImage,
        in rect: CGRect,
        cornerRadius: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        context.addPath(CGPath(
            roundedRect: rect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        ))
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private func drawWindowStroke(
        in rect: CGRect,
        cornerRadius: CGFloat,
        context: CGContext
    ) {
        context.saveGState()
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.10).cgColor)
        context.setLineWidth(1)
        context.addPath(CGPath(
            roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
            cornerWidth: max(0, cornerRadius - 0.5),
            cornerHeight: max(0, cornerRadius - 0.5),
            transform: nil
        ))
        context.strokePath()
        context.restoreGState()
    }
}

struct WindowScreenshotDecorationLayout: Equatable {
    let canvasSize: CGSize
    let imageRect: CGRect
    let cornerRadius: CGFloat
    let ambientShadowOffset: CGSize
    let ambientShadowBlur: CGFloat
    let ambientShadowAlpha: CGFloat
    let contactShadowOffset: CGSize
    let contactShadowBlur: CGFloat
    let contactShadowAlpha: CGFloat

    init(sourceSize: CGSize, style: WindowScreenshotDecorationStyle) {
        let metrics = WindowScreenshotDecorationMetrics(style: style)
        let imageSize = CGSize(
            width: sourceSize.width * metrics.contentScale,
            height: sourceSize.height * metrics.contentScale
        )
        let horizontalPadding = max(metrics.minimumHorizontalPadding, sourceSize.width * metrics.horizontalPaddingRatio)
        let topPadding = max(metrics.minimumTopPadding, sourceSize.height * metrics.topPaddingRatio)
        let bottomPadding = max(metrics.minimumBottomPadding, sourceSize.height * metrics.bottomPaddingRatio)

        canvasSize = CGSize(
            width: max(sourceSize.width, imageSize.width + horizontalPadding * 2),
            height: imageSize.height + topPadding + bottomPadding
        )
        imageRect = CGRect(
            x: (canvasSize.width - imageSize.width) / 2,
            y: bottomPadding,
            width: imageSize.width,
            height: imageSize.height
        )
        cornerRadius = min(
            metrics.maximumCornerRadius,
            max(metrics.minimumCornerRadius, min(imageSize.width, imageSize.height) * metrics.cornerRadiusRatio)
        )
        ambientShadowOffset = CGSize(
            width: 0,
            height: -max(metrics.minimumAmbientShadowOffset, imageSize.height * metrics.ambientShadowOffsetRatio)
        )
        ambientShadowBlur = min(
            metrics.maximumAmbientShadowBlur,
            max(metrics.minimumAmbientShadowBlur, min(imageSize.width, imageSize.height) * metrics.ambientShadowBlurRatio)
        )
        ambientShadowAlpha = metrics.ambientShadowAlpha
        contactShadowOffset = CGSize(
            width: 0,
            height: -max(metrics.minimumContactShadowOffset, imageSize.height * metrics.contactShadowOffsetRatio)
        )
        contactShadowBlur = min(
            metrics.maximumContactShadowBlur,
            max(metrics.minimumContactShadowBlur, min(imageSize.width, imageSize.height) * metrics.contactShadowBlurRatio)
        )
        contactShadowAlpha = metrics.contactShadowAlpha
    }
}

private struct WindowScreenshotDecorationMetrics {
    private static let sharedContentScale: CGFloat = 0.92
    private static let sharedHorizontalPaddingRatio: CGFloat = 0.12
    private static let sharedTopPaddingRatio: CGFloat = 0.16
    private static let sharedBottomPaddingRatio: CGFloat = 0.22
    private static let sharedMinimumHorizontalPadding: CGFloat = 56
    private static let sharedMinimumTopPadding: CGFloat = 52
    private static let sharedMinimumBottomPadding: CGFloat = 66

    let contentScale: CGFloat
    let horizontalPaddingRatio: CGFloat
    let topPaddingRatio: CGFloat
    let bottomPaddingRatio: CGFloat
    let minimumHorizontalPadding: CGFloat
    let minimumTopPadding: CGFloat
    let minimumBottomPadding: CGFloat
    let minimumCornerRadius: CGFloat
    let maximumCornerRadius: CGFloat
    let cornerRadiusRatio: CGFloat
    let minimumAmbientShadowOffset: CGFloat
    let minimumAmbientShadowBlur: CGFloat
    let maximumAmbientShadowBlur: CGFloat
    let ambientShadowOffsetRatio: CGFloat
    let ambientShadowBlurRatio: CGFloat
    let ambientShadowAlpha: CGFloat
    let minimumContactShadowOffset: CGFloat
    let minimumContactShadowBlur: CGFloat
    let maximumContactShadowBlur: CGFloat
    let contactShadowOffsetRatio: CGFloat
    let contactShadowBlurRatio: CGFloat
    let contactShadowAlpha: CGFloat

    init(style: WindowScreenshotDecorationStyle) {
        switch style {
        case .softBackdrop:
            contentScale = Self.sharedContentScale
            horizontalPaddingRatio = Self.sharedHorizontalPaddingRatio
            topPaddingRatio = Self.sharedTopPaddingRatio
            bottomPaddingRatio = Self.sharedBottomPaddingRatio
            minimumHorizontalPadding = Self.sharedMinimumHorizontalPadding
            minimumTopPadding = Self.sharedMinimumTopPadding
            minimumBottomPadding = Self.sharedMinimumBottomPadding
            minimumCornerRadius = 18
            maximumCornerRadius = 42
            cornerRadiusRatio = 0.065
            minimumAmbientShadowOffset = 22
            minimumAmbientShadowBlur = 42
            maximumAmbientShadowBlur = 96
            ambientShadowOffsetRatio = 0.045
            ambientShadowBlurRatio = 0.12
            ambientShadowAlpha = 0.28
            minimumContactShadowOffset = 8
            minimumContactShadowBlur = 18
            maximumContactShadowBlur = 42
            contactShadowOffsetRatio = 0.018
            contactShadowBlurRatio = 0.055
            contactShadowAlpha = 0.26
        case .canvasGlow:
            contentScale = Self.sharedContentScale
            horizontalPaddingRatio = Self.sharedHorizontalPaddingRatio
            topPaddingRatio = Self.sharedTopPaddingRatio
            bottomPaddingRatio = Self.sharedBottomPaddingRatio
            minimumHorizontalPadding = Self.sharedMinimumHorizontalPadding
            minimumTopPadding = Self.sharedMinimumTopPadding
            minimumBottomPadding = Self.sharedMinimumBottomPadding
            minimumCornerRadius = 20
            maximumCornerRadius = 48
            cornerRadiusRatio = 0.07
            minimumAmbientShadowOffset = 28
            minimumAmbientShadowBlur = 52
            maximumAmbientShadowBlur = 112
            ambientShadowOffsetRatio = 0.052
            ambientShadowBlurRatio = 0.13
            ambientShadowAlpha = 0.34
            minimumContactShadowOffset = 10
            minimumContactShadowBlur = 22
            maximumContactShadowBlur = 48
            contactShadowOffsetRatio = 0.02
            contactShadowBlurRatio = 0.06
            contactShadowAlpha = 0.30
        case .transparentShadow:
            contentScale = Self.sharedContentScale
            horizontalPaddingRatio = Self.sharedHorizontalPaddingRatio
            topPaddingRatio = Self.sharedTopPaddingRatio
            bottomPaddingRatio = Self.sharedBottomPaddingRatio
            minimumHorizontalPadding = Self.sharedMinimumHorizontalPadding
            minimumTopPadding = Self.sharedMinimumTopPadding
            minimumBottomPadding = Self.sharedMinimumBottomPadding
            minimumCornerRadius = 18
            maximumCornerRadius = 42
            cornerRadiusRatio = 0.065
            minimumAmbientShadowOffset = 22
            minimumAmbientShadowBlur = 42
            maximumAmbientShadowBlur = 96
            ambientShadowOffsetRatio = 0.045
            ambientShadowBlurRatio = 0.12
            ambientShadowAlpha = 0.32
            minimumContactShadowOffset = 8
            minimumContactShadowBlur = 18
            maximumContactShadowBlur = 42
            contactShadowOffsetRatio = 0.018
            contactShadowBlurRatio = 0.055
            contactShadowAlpha = 0.28
        }
    }
}

private enum WindowScreenshotDecoratorError: Error, LocalizedError {
    case renderFailed
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed:
            "窗口截图样式渲染失败。"
        case .pngEncodingFailed:
            "窗口截图样式 PNG 编码失败。"
        }
    }
}
