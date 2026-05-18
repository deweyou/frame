import AppKit

@MainActor
final class SelectionOverlayController {
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((CGRect?) -> Void)?
    private var escapeKeyMonitor: Any?

    func startSelection(completion: @escaping (CGRect?) -> Void) {
        finishSelection(with: nil)

        self.completion = completion

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finishSelection(with: nil)
            return
        }

        installEscapeKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)

        overlayWindows = screens.map { screen in
            SelectionOverlayWindow(screen: screen) { [weak self] selectedRect in
                self?.finishSelection(with: selectedRect)
            }
        }

        for window in overlayWindows {
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func finishSelection(with selectedRect: CGRect?) {
        guard let completion else {
            return
        }

        self.completion = nil
        removeEscapeKeyMonitor()

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()

        completion(selectedRect)
    }

    private func installEscapeKeyMonitor() {
        removeEscapeKeyMonitor()

        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == escapeKeyCode else {
                return event
            }

            self?.finishSelection(with: nil)
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        guard let escapeKeyMonitor else {
            return
        }

        NSEvent.removeMonitor(escapeKeyMonitor)
        self.escapeKeyMonitor = nil
    }
}

private let escapeKeyCode: UInt16 = 53
