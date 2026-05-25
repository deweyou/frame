import AppKit
import FrameCore

@MainActor
final class SelectionOverlayController {
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((SelectionCapture?) -> Void)?
    private var keyMonitor: Any?
    private var lastSelectedRect: CGRect?
    private let windowCandidateProvider = WindowCandidateProvider()

    func startSelection(completion: @escaping (SelectionCapture?) -> Void) {
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
        let activeScreen = activeScreen(from: screens)
        var createdWindows: [SelectionOverlayWindow] = []
        for screen in screens {
            var createdWindow: SelectionOverlayWindow?
            let window = SelectionOverlayWindow(
                screen: screen,
                initialGlobalRect: initialRect,
                showsCenteredHUDWhenEmpty: screen === activeScreen,
                onInteraction: { [weak self] in
                    guard let createdWindow else {
                        return
                    }

                    self?.activate(createdWindow)
                },
                onWindowSelectionRequested: { [weak self] globalPoint in
                    self?.windowCandidateProvider.candidate(at: globalPoint)
                },
                onComplete: { [weak self] selection in
                    self?.finishSelection(with: selection)
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
            window.setShowsCenteredHUDWhenEmpty(false)
        }

        activeWindow.setShowsCenteredHUDWhenEmpty(true)
        activeWindow.makeKey()
    }

    private func activeScreen(from screens: [NSScreen]) -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? screens[0]
    }

    private func finishSelection(with selection: SelectionCapture?) {
        guard let completion else {
            return
        }

        self.completion = nil
        removeKeyMonitor()

        if let selection {
            lastSelectedRect = selection.rect
        }

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()

        completion(selection)
    }

    private func confirmCurrentSelection() {
        guard let selection = overlayWindows.first(where: { $0.activeSelection != nil })?.activeSelection else {
            NSSound.beep()
            return
        }

        guard SelectionGeometry.isValidSelection(selection.rect) else {
            NSSound.beep()
            return
        }

        finishSelection(with: selection)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            if self.overlayWindows.contains(where: \.isEditingSize) {
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
