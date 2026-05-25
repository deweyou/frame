import AppKit
import FrameCore

@MainActor
final class SelectionOverlayController {
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((CGRect?) -> Void)?
    private var keyMonitor: Any?
    private var lastSelectedRect: CGRect?

    func startSelection(completion: @escaping (CGRect?) -> Void) {
        finishSelection(with: nil)

        self.completion = completion

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finishSelection(with: nil)
            return
        }

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)

        let initialRect = lastSelectedRect
        var createdWindows: [SelectionOverlayWindow] = []
        for screen in screens {
            var createdWindow: SelectionOverlayWindow?
            let window = SelectionOverlayWindow(
                screen: screen,
                initialGlobalRect: initialRect,
                onInteraction: { [weak self] in
                    guard let createdWindow else {
                        return
                    }

                    self?.activate(createdWindow)
                },
                onComplete: { [weak self] selectedRect in
                    self?.finishSelection(with: selectedRect)
                }
            )
            createdWindow = window
            createdWindows.append(window)
        }
        overlayWindows = createdWindows

        for window in overlayWindows {
            window.orderFrontRegardless()
        }

        (overlayWindows.first { $0.hasSelection } ?? overlayWindows.first)?.makeKey()
    }

    private func activate(_ activeWindow: SelectionOverlayWindow) {
        for window in overlayWindows where window !== activeWindow {
            window.clearSelection()
        }

        activeWindow.makeKey()
    }

    private func finishSelection(with selectedRect: CGRect?) {
        guard let completion else {
            return
        }

        self.completion = nil
        removeKeyMonitor()

        if let selectedRect {
            lastSelectedRect = selectedRect
        }

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()

        completion(selectedRect)
    }

    private func confirmCurrentSelection() {
        guard let selectedRect = overlayWindows.first(where: { $0.hasSelection })?.selectedGlobalRect else {
            NSSound.beep()
            return
        }

        guard SelectionGeometry.isValidSelection(selectedRect) else {
            NSSound.beep()
            return
        }

        finishSelection(with: selectedRect)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            switch event.keyCode {
            case escapeKeyCode:
                self.finishSelection(with: nil)
                return nil
            case returnKeyCode, keypadEnterKeyCode:
                self.confirmCurrentSelection()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        guard let keyMonitor else {
            return
        }

        NSEvent.removeMonitor(keyMonitor)
        self.keyMonitor = nil
    }
}

private let escapeKeyCode: UInt16 = 53
private let returnKeyCode: UInt16 = 36
private let keypadEnterKeyCode: UInt16 = 76
