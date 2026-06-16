import AppKit
import FrameCore

enum ImageAnnotationTextStyle {
    static let minimumBoundsSize = CGSize(width: 80, height: 24)

    static func font(for style: ImageAnnotationStyle, scale: CGFloat = 1) -> NSFont {
        NSFont.systemFont(
            ofSize: pointSize(for: style, scale: scale),
            weight: style.fontWeight == .bold ? .bold : .regular
        )
    }

    static func attributes(for style: ImageAnnotationStyle, scale: CGFloat = 1) -> [NSAttributedString.Key: Any] {
        [
            .font: font(for: style, scale: scale),
            .foregroundColor: foregroundColor(for: style),
        ]
    }

    static func pointSize(for style: ImageAnnotationStyle, scale: CGFloat = 1) -> CGFloat {
        max(1, max(8, style.fontSize) * scale)
    }

    static func foregroundColor(for style: ImageAnnotationStyle) -> NSColor {
        style.strokeColor.nsColor
    }

    static func bounds(for text: String, origin: CGPoint, style: ImageAnnotationStyle) -> CGRect {
        let measuredText = text.isEmpty ? " " : text
        let textBounds = (measuredText as NSString).boundingRect(
            with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes(for: style),
            context: nil
        )
        let font = font(for: style)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: max(minimumBoundsSize.width, ceil(textBounds.width)),
            height: max(minimumBoundsSize.height, ceil(textBounds.height), lineHeight)
        )
    }
}
