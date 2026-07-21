import AppKit

enum ScrollingScreenshotPreviewStatus: Equatable {
    case waiting
    case capturing
    case noNewContent
    case unreliableOverlap
}

@MainActor
protocol ScrollingScreenshotPreviewPresenting: AnyObject {
    func show(selectionRect: CGRect)
    func update(image: NSImage?, status: ScrollingScreenshotPreviewStatus)
    func close()
}

@MainActor
final class ScrollingScreenshotPreviewPanelController: ScrollingScreenshotPreviewPresenting {
    struct Layout: Equatable {
        let frame: CGRect
        let size: CGSize
    }

    private let screenFrameProvider: (() -> CGRect?)?
    private var panel: NSPanel?
    private var statusDotView: NSView?
    private var previewImageView: ScrollingScreenshotPreviewImageView?
    private var status: ScrollingScreenshotPreviewStatus = .waiting

    init(screenFrameProvider: (() -> CGRect?)? = nil) {
        self.screenFrameProvider = screenFrameProvider
    }

    func show(selectionRect: CGRect) {
        close()
        let screenFrame = screenFrameProvider?() ?? Self.screenFrame(containing: selectionRect)
        guard let screenFrame,
              let layout = Self.previewLayout(selectionRect: selectionRect, screenFrame: screenFrame)
        else {
            return
        }

        let panel = NSPanel(
            contentRect: CGRect(origin: .zero, size: layout.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .transient]
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.sharingType = .none

        let rootView = NSView(frame: CGRect(origin: .zero, size: layout.size))
        rootView.wantsLayer = true
        rootView.layer?.backgroundColor = HUDChromePalette.deepGlassBackgroundColor.cgColor
        rootView.layer?.borderColor = HUDChromePalette.deepGlassBorderColor.cgColor
        rootView.layer?.borderWidth = 1
        rootView.layer?.cornerRadius = 12
        rootView.layer?.masksToBounds = true

        let statusDotView = NSView()
        statusDotView.translatesAutoresizingMaskIntoConstraints = false
        statusDotView.wantsLayer = true
        statusDotView.layer?.cornerRadius = 4

        let previewImageView = ScrollingScreenshotPreviewImageView()
        previewImageView.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(previewImageView)
        rootView.addSubview(statusDotView)
        panel.contentView = rootView

        NSLayoutConstraint.activate([
            statusDotView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 12),
            statusDotView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -12),
            statusDotView.widthAnchor.constraint(equalToConstant: 8),
            statusDotView.heightAnchor.constraint(equalToConstant: 8),

            previewImageView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 8),
            previewImageView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -8),
            previewImageView.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 8),
            previewImageView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -8),
        ])

        self.panel = panel
        self.statusDotView = statusDotView
        self.previewImageView = previewImageView
        update(image: nil, status: .waiting)
        panel.setFrame(layout.frame, display: false)
        panel.orderFrontRegardless()
    }

    func update(image: NSImage?, status: ScrollingScreenshotPreviewStatus) {
        guard panel != nil else {
            return
        }
        self.status = status
        if let image {
            previewImageView?.image = image
        }
        statusDotView?.layer?.backgroundColor = Self.statusColor(for: status).cgColor
        previewImageView?.needsDisplay = true
    }

    func close() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        statusDotView = nil
        previewImageView = nil
        status = .waiting
    }

    static func previewLayout(selectionRect: CGRect, screenFrame: CGRect) -> Layout? {
        let gap: CGFloat = 12
        let horizontalInset: CGFloat = 12
        let verticalInset: CGFloat = 12
        let leftSpace = selectionRect.minX - screenFrame.minX - gap - horizontalInset
        let rightSpace = screenFrame.maxX - selectionRect.maxX - gap - horizontalInset
        let preferredRight = rightSpace >= leftSpace

        for size in [preferredSize, compactSize] {
            let canUseRight = rightSpace >= size.width
            let canUseLeft = leftSpace >= size.width
            guard canUseRight || canUseLeft else {
                continue
            }

            let useRight = preferredRight ? canUseRight : !canUseLeft
            let originX = useRight
                ? selectionRect.maxX + gap
                : selectionRect.minX - gap - size.width
            let centeredY = selectionRect.midY - size.height / 2
            let originY = min(
                max(centeredY, screenFrame.minY + verticalInset),
                screenFrame.maxY - size.height - verticalInset
            )
            let frame = CGRect(origin: CGPoint(x: originX, y: originY), size: size)
            guard screenFrame.contains(frame), !frame.intersects(selectionRect) else {
                continue
            }
            return Layout(frame: frame, size: size)
        }

        return nil
    }

    private static func screenFrame(containing selectionRect: CGRect) -> CGRect? {
        NSScreen.screens.max { firstScreen, secondScreen in
            firstScreen.frame.intersection(selectionRect).area
                < secondScreen.frame.intersection(selectionRect).area
        }?.frame ?? NSScreen.main?.frame
    }

    private static func statusColor(for status: ScrollingScreenshotPreviewStatus) -> NSColor {
        switch status {
        case .waiting:
            NSColor.white.withAlphaComponent(0.55)
        case .capturing:
            .systemGreen
        case .noNewContent:
            .systemOrange
        case .unreliableOverlap:
            .systemRed
        }
    }

    func panelSizeForTesting() -> CGSize? {
        panel?.frame.size
    }

    func panelIgnoresMouseEventsForTesting() -> Bool {
        panel?.ignoresMouseEvents ?? false
    }

    func previewImageForTesting() -> NSImage? {
        previewImageView?.image
    }

    func statusForTesting() -> ScrollingScreenshotPreviewStatus {
        status
    }

    func visibleFramesForTesting() -> (status: CGRect, preview: CGRect, panel: CGRect)? {
        guard let statusDotView,
              let previewImageView,
              let contentView = panel?.contentView else {
            return nil
        }
        contentView.layoutSubtreeIfNeeded()
        return (statusDotView.frame, previewImageView.frame, contentView.bounds)
    }

    private static let preferredSize = CGSize(width: 220, height: 320)
    private static let compactSize = CGSize(width: 160, height: 240)
}

final class ScrollingScreenshotPreviewImageView: NSView {
    var image: NSImage?

    override var isOpaque: Bool {
        false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.24).setFill()
        bounds.fill()
        guard let image,
              image.size.width > 0,
              image.size.height > 0
        else {
            return
        }

        image.draw(
            in: Self.destinationRect(imageSize: image.size, bounds: bounds),
            from: CGRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
    }

    static func destinationRect(imageSize: CGSize, bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.height > 0 else {
            return .zero
        }
        let scale = bounds.height / imageSize.height
        let scaledSize = CGSize(width: imageSize.width * scale, height: bounds.height)
        return CGRect(
            x: bounds.midX - scaledSize.width / 2,
            y: bounds.minY,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull else {
            return 0
        }
        return width * height
    }
}
