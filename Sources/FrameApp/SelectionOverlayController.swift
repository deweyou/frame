import AppKit
import FrameCore

@MainActor
final class SelectionOverlayController {
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((SelectionOverlayCompletion?) -> Void)?
    private var keyMonitor: Any?
    private var lastSelectionHistory: SelectionHistory?
    private let windowCandidateProvider = WindowCandidateProvider()
    private let resetCursor: () -> Void

    init(resetCursor: @escaping () -> Void = { NSCursor.arrow.set() }) {
        self.resetCursor = resetCursor
    }

    func startSelection(
        strings: AppStrings = AppStrings.current(),
        onStartRecording: @escaping (SelectionOverlayWindow, SelectionCapture, RecordingOptions) -> Void = { _, _, _ in },
        completion: @escaping (SelectionOverlayCompletion?) -> Void
    ) {
        finishSelection(with: nil)

        self.completion = completion

        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            finishSelection(with: nil)
            return
        }

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)

        let activeScreen = activeScreen(from: screens)
        let initialRect = lastSelectionHistory?.rectForRestore(
            activeDisplayID: displayID(for: activeScreen)
        )
        var createdWindows: [SelectionOverlayWindow] = []
        for screen in screens {
            var createdWindow: SelectionOverlayWindow?
            let window = SelectionOverlayWindow(
                screen: screen,
                initialGlobalRect: initialRect,
                showsCenteredHUDWhenEmpty: screen === activeScreen,
                placeholderText: strings.capturePlaceholder,
                ocrActionText: strings.quickAccessOCR,
                onInteraction: { [weak self] in
                    guard let createdWindow else {
                        return
                    }

                    self?.activate(createdWindow)
                },
                onWindowSelectionRequested: { [weak self] globalPoint, overlayWindowNumber in
                    self?.windowCandidateProvider.candidate(
                        at: globalPoint,
                        belowWindowNumber: overlayWindowNumber
                    )
                },
                onStartRecording: { [weak self] selection, options in
                    guard let self, let createdWindow else {
                        return
                    }

                    self.prepareForRecording(on: createdWindow, selection: selection)
                    onStartRecording(createdWindow, selection, options)
                },
                onComplete: { [weak self] completion in
                    self?.finishSelection(with: completion)
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

    private func prepareForRecording(on activeWindow: SelectionOverlayWindow, selection: SelectionCapture) {
        removeKeyMonitor()
        lastSelectionHistory = SelectionHistory(
            rect: selection.rect,
            displayID: displayID(for: screen(containing: selection.rect))
        )

        for window in overlayWindows where window !== activeWindow {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows = [activeWindow]
        activeWindow.enterActiveRecordingMode(elapsed: 0, isPaused: false)
        activeWindow.makeKey()
    }

    private func activeScreen(from screens: [NSScreen]) -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? screens[0]
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        NSScreen.screens.max { firstScreen, secondScreen in
            intersectionArea(firstScreen.frame, rect) < intersectionArea(secondScreen.frame, rect)
        }
    }

    private func displayID(for screen: NSScreen?) -> CGDirectDisplayID? {
        guard let screen,
              let displayNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(displayNumber.uint32Value)
    }

    private func intersectionArea(_ firstRect: CGRect, _ secondRect: CGRect) -> CGFloat {
        let intersection = firstRect.intersection(secondRect)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private func finishSelection(with completionResult: SelectionOverlayCompletion?) {
        guard let completion else {
            return
        }

        self.completion = nil
        removeKeyMonitor()

        if let selection = completionResult?.selection {
            lastSelectionHistory = SelectionHistory(
                rect: selection.rect,
                displayID: displayID(for: screen(containing: selection.rect))
            )
        }

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        resetCursor()

        completion(completionResult)
    }

    func cancelSelection() {
        finishSelection(with: nil)
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

        finishSelection(with: .capture(selection))
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
