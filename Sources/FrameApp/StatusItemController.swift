import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onCaptureAction: () -> Void
    private let onCheckPermissionAction: () -> Void

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        onCapture: @escaping () -> Void,
        onCheckPermission: @escaping () -> Void
    ) {
        self.statusItem = statusItem
        self.onCaptureAction = onCapture
        self.onCheckPermissionAction = onCheckPermission

        super.init()

        configureStatusItem()
    }

    private func configureStatusItem() {
        statusItem.button?.title = "Frame"

        let menu = NSMenu()
        menu.addItem(menuItem(title: "截图", action: #selector(onCapture(_:))))
        menu.addItem(menuItem(title: "检查权限", action: #selector(onCheckPermission(_:))))
        menu.addItem(.separator())
        menu.addItem(menuItem(title: "退出", action: #selector(onQuit(_:))))

        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func onCapture(_ sender: NSMenuItem) {
        onCaptureAction()
    }

    @objc private func onCheckPermission(_ sender: NSMenuItem) {
        onCheckPermissionAction()
    }

    @objc private func onQuit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
