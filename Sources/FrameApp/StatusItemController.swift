import AppKit

enum StatusItemRecordingState {
    case idle
    case recording
    case paused
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onCaptureAction: () -> Void
    private let onHistoryAction: () -> Void
    private let onSettingsAction: () -> Void
    private let onStopRecordingAction: () -> Void
    private var strings: AppStrings
    private var recordingState: StatusItemRecordingState = .idle

    init(
        statusItem: NSStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength),
        strings: AppStrings = AppStrings.current(),
        onCapture: @escaping () -> Void,
        onHistory: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onStopRecording: @escaping () -> Void = {}
    ) {
        self.statusItem = statusItem
        self.strings = strings
        self.onCaptureAction = onCapture
        self.onHistoryAction = onHistory
        self.onSettingsAction = onSettings
        self.onStopRecordingAction = onStopRecording

        super.init()

        configureStatusItem()
    }

    func reloadMenu(strings: AppStrings) {
        self.strings = strings
        configureStatusItem()
    }

    func setRecordingState(_ recordingState: StatusItemRecordingState) {
        self.recordingState = recordingState
        configureStatusItem()
    }

    private func configureStatusItem() {
        if let statusButton = statusItem.button {
            if recordingState != .idle {
                let image = makeRecordingIcon()
                image.size = NSSize(width: 18, height: 18)
                statusButton.image = image
                statusButton.imagePosition = .imageOnly
                statusButton.toolTip = "Frame"
            } else if let image = loadStatusIcon() {
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
        if recordingState != .idle {
            menu.addItem(menuItem(title: strings.menuStopRecording, action: #selector(onStopRecording(_:))))
            menu.addItem(.separator())
        }
        menu.addItem(menuItem(title: strings.menuCapture, action: #selector(onCapture(_:))))
        menu.addItem(menuItem(title: strings.menuCaptureHistory, action: #selector(onHistory(_:))))
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

    private func makeRecordingIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSBezierPath(ovalIn: CGRect(x: 4, y: 4, width: 10, height: 10)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func onCapture(_ sender: NSMenuItem) {
        onCaptureAction()
    }

    @objc private func onStopRecording(_ sender: NSMenuItem) {
        onStopRecordingAction()
    }

    @objc private func onHistory(_ sender: NSMenuItem) {
        onHistoryAction()
    }

    @objc private func onSettings(_ sender: NSMenuItem) {
        onSettingsAction()
    }

    @objc private func onQuit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}
