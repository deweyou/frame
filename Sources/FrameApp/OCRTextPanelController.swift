import AppKit
import FrameCore

@MainActor
final class OCRTextPanelController: NSObject {
    private var panelItems: [OCRTextPanelItem] = []

    func show(
        layout: RecognizedTextLayout,
        for screenshot: CapturedScreenshot,
        strings: AppStrings,
        copyAll: @escaping () -> Bool
    ) {
        if let existingItem = panelItem(for: screenshot) {
            existingItem.copyAll = copyAll
            update(existingItem, layout: layout)
            activatePanel(existingItem.panel)
            return
        }

        let panel = makePanel(title: strings.ocrPanelTitle)
        let item = OCRTextPanelItem(
            panel: panel,
            screenshotID: screenshot.id,
            copyAll: copyAll
        )
        panel.contentView = makeContentView(layout: layout, strings: strings)
        panelItems.append(item)
        installLifecycleCallbacks(for: item)
        activatePanel(panel)
    }

    func closePanel(for screenshot: CapturedScreenshot) -> Bool {
        guard let item = panelItem(for: screenshot) else {
            return false
        }

        item.panel.close()
        return true
    }

    private func activatePanel(_ panel: NSPanel) {
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func makePanel(title: String) -> OCRTextPanel {
        let visibleFrame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 900, height: 700)
        let contentSize = NSSize(
            width: min(520, max(360, visibleFrame.width * 0.42)),
            height: min(420, max(260, visibleFrame.height * 0.42))
        )
        let contentRect = NSRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        let panel = OCRTextPanel(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 320, height: 220)
        return panel
    }

    private func makeContentView(layout: RecognizedTextLayout, strings: AppStrings) -> NSView {
        let contentView = NSView()
        contentView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .bezelBorder
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.string = layout.fullText
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        scrollView.documentView = textView

        let copyButton = NSButton(title: strings.ocrCopyAll, target: self, action: #selector(copyAllButtonClicked))
        copyButton.translatesAutoresizingMaskIntoConstraints = false
        copyButton.bezelStyle = .rounded
        copyButton.setAccessibilityLabel(strings.ocrCopyAll)
        copyButton.setAccessibilityHelp(strings.ocrCopyAll)

        contentView.addSubview(scrollView)
        contentView.addSubview(copyButton)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -12),

            copyButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            copyButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])

        return contentView
    }

    private func update(_ item: OCRTextPanelItem, layout: RecognizedTextLayout) {
        guard let contentView = item.panel.contentView,
              let textView = findTextView(in: contentView) else {
            return
        }

        textView.string = layout.fullText
    }

    private func installLifecycleCallbacks(for item: OCRTextPanelItem) {
        item.panel.onClose = { [weak self, weak item] in
            guard let item else {
                return
            }

            self?.removePanel(item)
        }
    }

    private func removePanel(_ item: OCRTextPanelItem) {
        item.panel.onClose = nil
        panelItems.removeAll { $0 === item }
    }

    private func panelItem(for screenshot: CapturedScreenshot) -> OCRTextPanelItem? {
        panelItems.first {
            $0.screenshotID == screenshot.id
        }
    }

    private func panelItem(for window: NSWindow?) -> OCRTextPanelItem? {
        guard let window else {
            return nil
        }

        return panelItems.first { $0.panel === window }
    }

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        if let scrollView = view as? NSScrollView,
           let textView = scrollView.documentView as? NSTextView {
            return textView
        }

        return nil
    }

    @objc private func copyAllButtonClicked(_ sender: NSButton) {
        guard let item = panelItem(for: sender.window) else {
            return
        }

        _ = item.copyAll()
    }
}

@MainActor
private final class OCRTextPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func close() {
        let closeHandler = onClose
        onClose = nil
        closeHandler?()
        super.close()
    }
}

private final class OCRTextPanelItem {
    let panel: OCRTextPanel
    let screenshotID: UUID
    var copyAll: () -> Bool

    init(panel: OCRTextPanel, screenshotID: UUID, copyAll: @escaping () -> Bool) {
        self.panel = panel
        self.screenshotID = screenshotID
        self.copyAll = copyAll
    }
}
