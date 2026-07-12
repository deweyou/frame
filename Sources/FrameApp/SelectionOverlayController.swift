import AppKit
import FrameCore

struct RememberedSelection: Codable, Equatable {
    static let lifetime: TimeInterval = 10 * 60

    let windowID: UInt32?
    let bounds: CGRect
    let recordedAt: Date

    private enum CodingKeys: String, CodingKey {
        case windowID
        case originX
        case originY
        case width
        case height
        case recordedAt
    }

    init(windowID: UInt32, bounds: CGRect, recordedAt: Date) {
        self.windowID = windowID
        self.bounds = bounds
        self.recordedAt = recordedAt
    }

    init(bounds: CGRect, recordedAt: Date) {
        self.windowID = nil
        self.bounds = bounds
        self.recordedAt = recordedAt
    }

    init(selection: SelectionCapture, recordedAt: Date) {
        switch selection.kind {
        case let .window(id):
            self.init(windowID: id, bounds: selection.rect, recordedAt: recordedAt)
        case .region:
            self.init(bounds: selection.rect, recordedAt: recordedAt)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        windowID = try container.decodeIfPresent(UInt32.self, forKey: .windowID)
        bounds = CGRect(
            x: try container.decode(CGFloat.self, forKey: .originX),
            y: try container.decode(CGFloat.self, forKey: .originY),
            width: try container.decode(CGFloat.self, forKey: .width),
            height: try container.decode(CGFloat.self, forKey: .height)
        )
        recordedAt = try container.decode(Date.self, forKey: .recordedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(windowID, forKey: .windowID)
        try container.encode(bounds.origin.x, forKey: .originX)
        try container.encode(bounds.origin.y, forKey: .originY)
        try container.encode(bounds.width, forKey: .width)
        try container.encode(bounds.height, forKey: .height)
        try container.encode(recordedAt, forKey: .recordedAt)
    }

    func isValid(at date: Date) -> Bool {
        date.timeIntervalSince(recordedAt) < Self.lifetime
    }
}

@MainActor
protocol SelectionOverlayControlling: AnyObject {
    var isSelecting: Bool { get }

    func startSelection(
        strings: AppStrings,
        initialMode: SelectionOverlayInitialMode,
        onStartRecording: @escaping (SelectionOverlayWindow, SelectionCapture, RecordingOptions) -> Void,
        completion: @escaping (SelectionOverlayCompletion?) -> Void
    )

    func dismissSelectionForRecording()
}

enum SelectionOverlayInitialMode: Equatable {
    case screenshot
    case recordingSetup
}

@MainActor
final class SelectionOverlayController: SelectionOverlayControlling {
    private var overlayWindows: [SelectionOverlayWindow] = []
    private var completion: ((SelectionOverlayCompletion?) -> Void)?
    private var keyMonitor: Any?
    private let windowCandidateProvider: WindowCandidateProvider
    private let resetCursor: () -> Void
    private let currentDate: () -> Date
    private let rememberedSelectionProvider: (Date) -> RememberedSelection?
    private let persistRememberedSelection: (RememberedSelection?) -> Void
    var isSelecting: Bool {
        !overlayWindows.isEmpty || completion != nil
    }

    init(
        windowCandidateProvider: WindowCandidateProvider = WindowCandidateProvider(),
        currentDate: @escaping () -> Date = Date.init,
        rememberedSelectionProvider: @escaping (Date) -> RememberedSelection? = { date in
            SettingsStore.rememberedSelection(currentDate: date)
        },
        persistRememberedSelection: @escaping (RememberedSelection?) -> Void = { selection in
            SettingsStore.setRememberedSelection(selection)
        },
        resetCursor: @escaping () -> Void = { NSCursor.arrow.set() }
    ) {
        self.windowCandidateProvider = windowCandidateProvider
        self.currentDate = currentDate
        self.rememberedSelectionProvider = rememberedSelectionProvider
        self.persistRememberedSelection = persistRememberedSelection
        self.resetCursor = resetCursor
    }

    func startSelection(
        strings: AppStrings = AppStrings.current(),
        initialMode: SelectionOverlayInitialMode = .screenshot,
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
        let rememberedSelection = resolvedRememberedSelection()
        var createdWindows: [SelectionOverlayWindow] = []
        for screen in screens {
            let initialSelection = rememberedSelection.flatMap { selection in
                screen.frame.contains(selection.rect.center) ? selection : nil
            }
            var createdWindow: SelectionOverlayWindow?
            let window = SelectionOverlayWindow(
                screen: screen,
                initialGlobalRect: initialSelection?.rect,
                initialWindowCandidate: initialSelection?.windowCandidate,
                initialMode: initialMode,
                showsCenteredHUDWhenEmpty: screen === activeScreen,
                placeholderText: strings.capturePlaceholder,
                scrollingActionText: strings.scrollingScreenshotAction,
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

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        completion = nil
        resetCursor()
    }

    private func activeScreen(from screens: [NSScreen]) -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? screens[0]
    }

    private func finishSelection(with completionResult: SelectionOverlayCompletion?) {
        guard let completion else {
            return
        }

        self.completion = nil
        updateRememberedSelection(from: completionResult)
        removeKeyMonitor()

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        resetCursor()

        completion(completionResult)
    }

    private func resolvedRememberedSelection() -> (rect: CGRect, windowCandidate: WindowCandidate?)? {
        guard let rememberedSelection = rememberedSelectionProvider(currentDate()) else {
            return nil
        }

        guard rememberedSelection.isValid(at: currentDate()) else {
            persistRememberedSelection(nil)
            return nil
        }

        guard let windowID = rememberedSelection.windowID else {
            return (rememberedSelection.bounds, nil)
        }

        guard let candidate = windowCandidateProvider.candidate(id: windowID) else {
            persistRememberedSelection(nil)
            return nil
        }

        return (candidate.bounds, candidate)
    }

    private func updateRememberedSelection(from completionResult: SelectionOverlayCompletion?) {
        guard let completionResult else {
            return
        }

        guard let selection = completionResult.selection else {
            persistRememberedSelection(nil)
            return
        }

        persistRememberedSelection(RememberedSelection(
            selection: selection,
            recordedAt: currentDate()
        ))
    }

    func cancelSelection() {
        finishSelection(with: nil)
    }

    func dismissSelectionForRecording() {
        guard completion != nil else {
            return
        }

        completion = nil
        removeKeyMonitor()

        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
        resetCursor()
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
