import AppKit

enum FrameHUDChrome {
    enum Surface {
        case toolbar
        case editor
        case overlay
    }

    static let primaryIcon = NSColor.white.withAlphaComponent(0.90)
    static let secondaryIcon = NSColor.white.withAlphaComponent(0.68)
    static let disabledIcon = NSColor.white.withAlphaComponent(0.38)
    static let hoverFill = NSColor.white.withAlphaComponent(0.14)
    static let divider = NSColor.white.withAlphaComponent(0.20)
    static let border = NSColor.white.withAlphaComponent(0.20)
    static let selectedFill = NSColor.controlAccentColor.withAlphaComponent(0.82)
    static let selectedIcon = NSColor.white

    static func backgroundColor(for surface: Surface) -> NSColor {
        switch surface {
        case .toolbar:
            NSColor.black.withAlphaComponent(0.60)
        case .editor:
            NSColor.black.withAlphaComponent(0.84)
        case .overlay:
            NSColor.black.withAlphaComponent(0.68)
        }
    }

    @MainActor
    static func configure(
        _ view: NSVisualEffectView,
        surface: Surface,
        cornerRadius: CGFloat,
        masksToBounds: Bool = true
    ) {
        view.appearance = NSAppearance(named: .vibrantDark)
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = masksToBounds
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = border.cgColor
        view.layer?.backgroundColor = backgroundColor(for: surface).cgColor
    }

    static func configureAccessoryChip(
        _ layer: CALayer?,
        cornerRadius: CGFloat,
        masksToBounds: Bool = true
    ) {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = masksToBounds
        layer?.backgroundColor = backgroundColor(for: .overlay).cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = border.cgColor
    }
}
