import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onCaptureAction: () -> Void
    private let onSettingsAction: () -> Void
    private var strings: AppStrings

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        strings: AppStrings = AppStrings.current(),
        onCapture: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) {
        self.statusItem = statusItem
        self.strings = strings
        self.onCaptureAction = onCapture
        self.onSettingsAction = onSettings

        super.init()

        configureStatusItem()
    }

    func reloadMenu(strings: AppStrings) {
        self.strings = strings
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let statusButton = statusItem.button {
            if let image = loadStatusIcon() {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                statusButton.image = image
                statusButton.imagePosition = .imageOnly
                statusButton.toolTip = "Frame"
            } else {
                statusButton.title = "Frame"
            }
        }

        let menu = NSMenu()
        menu.addItem(menuItem(title: strings.menuCapture, action: #selector(onCapture(_:))))
        menu.addItem(menuItem(title: strings.menuSettings, action: #selector(onSettings(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: strings.menuQuit, action: #selector(onQuit(_:))))

        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func loadStatusIcon() -> NSImage? {
        if let image = NSImage(named: "FrameStatusIconTemplate") {
            return image
        }

        guard let imageURL = Bundle.main.url(
            forResource: "FrameStatusIconTemplate",
            withExtension: "png",
            subdirectory: "menubar"
        ) else {
            return nil
        }

        return NSImage(contentsOf: imageURL)
    }

    @objc private func onCapture(_ sender: NSMenuItem) {
        onCaptureAction()
    }

    @objc private func onSettings(_ sender: NSMenuItem) {
        onSettingsAction()
    }

    @objc private func onQuit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
