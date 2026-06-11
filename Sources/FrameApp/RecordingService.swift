import AppKit
import ApplicationServices
import CoreMedia
import FrameCore
@preconcurrency import ScreenCaptureKit

struct CapturedRecording: Equatable, Identifiable, Sendable {
    let id: UUID
    let fileURL: URL
    let format: RecordingFormat
    let rect: CGRect
    let pixelSize: CGSize
    let byteSize: Int
    let duration: TimeInterval
}

struct RecordingRequest: Equatable, @unchecked Sendable {
    let selection: SelectionCapture
    let options: RecordingOptions
}

enum RecordingSessionState: Equatable, Sendable {
    case recording
    case paused
    case finishing
    case finished
    case failed(String)
}

protocol RecordingSessionControlling: AnyObject, Sendable {
    var state: RecordingSessionState { get }

    func pause() async throws
    func resume() async throws
    func stop() async throws -> CapturedRecording
    func cancel() async
    func recordKeyboardHint(_ label: String)
}

protocol RecordingServicing: Sendable {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling
}

struct RecordingDisplaySelection: Equatable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let selectionRect: CGRect
}

struct RecordingScreen: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
}

enum RecordingServiceError: LocalizedError {
    case invalidSelectionRect(CGRect)
    case selectionSpansMultipleDisplays
    case displayNotFound
    case outputFailed(String)

    var errorDescription: String? {
        switch self {
        case let .invalidSelectionRect(rect):
            "录屏区域无效：\(rect.debugDescription)"
        case .selectionSpansMultipleDisplays:
            "录屏区域只能位于一个显示器内。请重新选择一个屏幕上的区域。"
        case .displayNotFound:
            "无法找到要录制的显示器。"
        case let .outputFailed(message):
            message
        }
    }
}

enum RecordingDisplayResolver {
    static func resolve(selection: CGRect, screenFrames: [CGRect]) throws -> RecordingDisplaySelection {
        try resolve(
            selection: selection,
            screens: screenFrames.map { RecordingScreen(displayID: 0, frame: $0) }
        )
    }

    static func resolve(selection: CGRect, screens: [RecordingScreen]) throws -> RecordingDisplaySelection {
        guard !selection.isNull,
              !selection.isEmpty,
              selection.width > 0,
              selection.height > 0 else {
            throw RecordingServiceError.invalidSelectionRect(selection)
        }

        let intersectingScreens = screens.filter { screen in
            let intersection = screen.frame.intersection(selection)
            return !intersection.isNull && !intersection.isEmpty
        }

        guard intersectingScreens.count == 1,
              let screen = intersectingScreens.first else {
            throw intersectingScreens.isEmpty
                ? RecordingServiceError.displayNotFound
                : RecordingServiceError.selectionSpansMultipleDisplays
        }

        guard screen.frame.contains(selection) else {
            throw RecordingServiceError.selectionSpansMultipleDisplays
        }

        return RecordingDisplaySelection(displayID: screen.displayID, screenFrame: screen.frame, selectionRect: selection)
    }
}

enum RecordingPixelDimensions {
    static func normalizedForVideo(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(2, Int(size.width.rounded()).roundedDownToEven),
            height: max(2, Int(size.height.rounded()).roundedDownToEven)
        )
    }
}

final class ScreenCaptureRecordingService: RecordingServicing {
    func startRecording(_ request: RecordingRequest) async throws -> RecordingSessionControlling {
        let resolvedSelection = try RecordingDisplayResolver.resolve(
            selection: request.selection.rect,
            screens: NSScreen.screens.map { screen in
                RecordingScreen(displayID: displayID(for: screen), frame: screen.frame)
            }
        )
        let session = try await ScreenCaptureRecordingSession(
            request: request,
            resolvedSelection: resolvedSelection
        )
        try await session.start()
        return session
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) } ?? 0
    }
}

final class ScreenCaptureRecordingSession: NSObject, RecordingSessionControlling, @unchecked Sendable {
    private let request: RecordingRequest
    private let resolvedSelection: RecordingDisplaySelection
    private let sampleQueue = DispatchQueue(label: "dev.dewey.frame.recording.samples")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var encoder: RecordingFrameEncoding?
    private var outputURL: URL?
    private var overlayRenderer: RecordingOverlayRenderer?
    private var overlayEventStore: RecordingOverlayEventStore?
    private var overlayEventMonitors: [Any] = []
    private var keyboardEventTap: RecordingKeyboardEventTap?
    private var liveOverlayController: RecordingLiveOverlayController!
    private var startedAt = Date()
    private var isPaused = false
    private(set) var state: RecordingSessionState = .recording

    init(request: RecordingRequest, resolvedSelection: RecordingDisplaySelection) async throws {
        self.request = request
        self.resolvedSelection = resolvedSelection
        super.init()
        self.liveOverlayController = await MainActor.run {
            RecordingLiveOverlayController()
        }
    }

    func start() async throws {
        let pixelSize = normalizedRecordingPixelSize(for: resolvedSelection.selectionRect)
        let overlayConfiguration = RecordingOverlayConfiguration(options: request.options)
        let overlayEventStore: RecordingOverlayEventStore?
        let liveOverlayWindowNumber: Int?
        if overlayConfiguration.isEnabled {
            let eventStore = RecordingOverlayEventStore()
            overlayEventStore = eventStore
            self.overlayEventStore = eventStore
            overlayRenderer = RecordingOverlayRenderer(
                eventStore: eventStore,
                pixelSize: pixelSize,
                mouseHintColor: overlayConfiguration.mouseHintColor
            )
            liveOverlayWindowNumber = await MainActor.run {
                liveOverlayController.show(
                    screenFrame: resolvedSelection.screenFrame,
                    selectionRect: resolvedSelection.selectionRect,
                    pixelSize: pixelSize,
                    eventStore: eventStore,
                    mouseHintColor: overlayConfiguration.mouseHintColor
                )
                return liveOverlayController.windowNumber
            }
        } else {
            overlayEventStore = nil
            self.overlayEventStore = nil
            overlayRenderer = nil
            liveOverlayWindowNumber = nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == resolvedSelection.displayID && resolvedSelection.displayID != 0 })
                ?? content.displays.first(where: { $0.frame.equalTo(resolvedSelection.screenFrame) })
                ?? content.displays.first(where: { !$0.frame.intersection(resolvedSelection.screenFrame).isNull })
                ?? content.displays.first else {
                throw RecordingServiceError.displayNotFound
            }

            let outputURL = makeTemporaryOutputURL(format: request.options.format)
            let encoder: RecordingFrameEncoding = switch request.options.format {
            case .mp4:
                try MP4RecordingFrameEncoder(outputURL: outputURL, pixelSize: pixelSize)
            case .gif:
                try GIFRecordingFrameEncoder(outputURL: outputURL)
            }

            let configuration = SCStreamConfiguration()
            configuration.width = Int(pixelSize.width)
            configuration.height = Int(pixelSize.height)
            configuration.sourceRect = sourceRect(for: resolvedSelection)
            configuration.queueDepth = 6
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            configuration.showsCursor = request.options.showsCursor
            configuration.capturesAudio = false
            configuration.pixelFormat = kCVPixelFormatType_32BGRA

            let excludedWindows = content.windows.filter { window in
                RecordingOverlayCaptureExclusion.shouldExclude(
                    windowID: window.windowID,
                    liveOverlayWindowNumber: liveOverlayWindowNumber
                )
            }
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            try await stream.startCapture()

            self.stream = stream
            self.encoder = encoder
            self.outputURL = outputURL
            startedAt = Date()
            if let overlayEventStore {
                await MainActor.run {
                    installOverlayEventMonitors(
                        configuration: overlayConfiguration,
                        eventStore: overlayEventStore,
                        pixelSize: pixelSize
                    )
                }
            }
            setState(.recording)
        } catch {
            await MainActor.run {
                removeOverlayEventMonitors()
                liveOverlayController.close()
            }
            overlayRenderer = nil
            self.overlayEventStore = nil
            throw error
        }
    }

    func pause() async throws {
        stateLock.withLock {
            isPaused = true
            state = .paused
        }
    }

    func resume() async throws {
        stateLock.withLock {
            isPaused = false
            state = .recording
        }
    }

    func stop() async throws -> CapturedRecording {
        setState(.finishing)
        await MainActor.run {
            removeOverlayEventMonitors()
            liveOverlayController.close()
        }
        if let stream {
            try await stream.stopCapture()
        }
        guard let encoder else {
            throw RecordingServiceError.outputFailed("录屏会话没有可写入的输出。")
        }

        let finalizedURL = try await encoder.finish()
        let byteSize = (try? FileManager.default.attributesOfItem(atPath: finalizedURL.path)[.size] as? NSNumber)?.intValue ?? 0
        setState(.finished)
        overlayEventStore = nil
        return CapturedRecording(
            id: UUID(),
            fileURL: finalizedURL,
            format: request.options.format,
            rect: request.selection.rect,
            pixelSize: normalizedRecordingPixelSize(for: resolvedSelection.selectionRect),
            byteSize: byteSize,
            duration: max(0, Date().timeIntervalSince(startedAt))
        )
    }

    func cancel() async {
        await MainActor.run {
            removeOverlayEventMonitors()
            liveOverlayController.close()
        }
        try? await stream?.stopCapture()
        overlayEventStore = nil
        setState(.finished)
    }

    func recordKeyboardHint(_ label: String) {
        guard request.options.showsKeyboardHints else {
            return
        }

        overlayEventStore?.recordTransientKey(
            label: label,
            time: ProcessInfo.processInfo.systemUptime
        )
    }

    private func setState(_ state: RecordingSessionState) {
        stateLock.withLock {
            self.state = state
        }
    }

    private func makeTemporaryOutputURL(format: RecordingFormat) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Frame-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension(format.fileExtension)
    }

    private func sourceRect(for selection: RecordingDisplaySelection) -> CGRect {
        CGRect(
            x: selection.selectionRect.minX - selection.screenFrame.minX,
            y: selection.screenFrame.maxY - selection.selectionRect.maxY,
            width: selection.selectionRect.width,
            height: selection.selectionRect.height
        )
    }

    private func recordingPixelSize(for rect: CGRect) -> CGSize {
        let scale = NSScreen.screens.first { $0.frame.intersects(rect) }?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        return CGSize(width: rect.width * scale, height: rect.height * scale)
    }

    private func normalizedRecordingPixelSize(for rect: CGRect) -> CGSize {
        RecordingPixelDimensions.normalizedForVideo(recordingPixelSize(for: rect))
    }

    @MainActor
    private func installOverlayEventMonitors(
        configuration: RecordingOverlayConfiguration,
        eventStore: RecordingOverlayEventStore,
        pixelSize: CGSize
    ) {
        removeOverlayEventMonitors()

        if configuration.recordsMouseClicks {
            let mouseMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self, weak eventStore] event in
                guard let self, let eventStore else {
                    return
                }

                let screenPoint = NSEvent.mouseLocation
                guard self.resolvedSelection.selectionRect.contains(screenPoint) else {
                    return
                }

                eventStore.recordClick(
                    at: RecordingOverlayCoordinateMapper.pixelPoint(
                        screenPoint: screenPoint,
                        selectionRect: self.resolvedSelection.selectionRect,
                        pixelSize: pixelSize
                    ),
                    time: event.timestamp
                )
            }
            if let mouseMonitor {
                overlayEventMonitors.append(mouseMonitor)
            }
        }

        if configuration.recordsKeyboardHints {
            let keyboardEventTap = RecordingKeyboardEventTap(eventStore: eventStore)
            if keyboardEventTap.start() {
                self.keyboardEventTap = keyboardEventTap
                return
            }

            let flagsHandler: (NSEvent) -> Void = { [weak eventStore] event in
                eventStore?.updateKeyboardModifierFlags(event.modifierFlags, time: event.timestamp)
            }
            let keyDownHandler: (NSEvent) -> Void = { [weak eventStore] event in
                eventStore?.recordKeyDown(
                    keyCode: event.keyCode,
                    label: RecordingOverlayKeyFormatter.label(
                        charactersIgnoringModifiers: event.charactersIgnoringModifiers,
                        keyCode: event.keyCode,
                        modifierFlags: []
                    ),
                    modifierFlags: event.modifierFlags,
                    time: event.timestamp
                )
            }
            let keyUpHandler: (NSEvent) -> Void = { [weak eventStore] event in
                eventStore?.recordKeyUp(
                    keyCode: event.keyCode,
                    modifierFlags: event.modifierFlags,
                    time: event.timestamp
                )
            }
            if let globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flagsHandler) {
                overlayEventMonitors.append(globalFlagsMonitor)
            }
            if let globalKeyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keyDownHandler) {
                overlayEventMonitors.append(globalKeyDownMonitor)
            }
            if let globalKeyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: keyUpHandler) {
                overlayEventMonitors.append(globalKeyUpMonitor)
            }
            if let localFlagsMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .flagsChanged,
                handler: { event in
                    flagsHandler(event)
                    return event
                }
            ) {
                overlayEventMonitors.append(localFlagsMonitor)
            }
            if let localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyDown,
                handler: { event in
                    keyDownHandler(event)
                    return event
                }
            ) {
                overlayEventMonitors.append(localKeyDownMonitor)
            }
            if let localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(
                matching: .keyUp,
                handler: { event in
                    keyUpHandler(event)
                    return event
                }
            ) {
                overlayEventMonitors.append(localKeyUpMonitor)
            }
        }
    }

    @MainActor
    private func removeOverlayEventMonitors() {
        keyboardEventTap?.stop()
        keyboardEventTap = nil
        for monitor in overlayEventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        overlayEventMonitors.removeAll()
    }
}

private extension Int {
    var roundedDownToEven: Int {
        self - (self % 2)
    }
}

final class RecordingKeyboardEventTap: @unchecked Sendable {
    private weak var eventStore: RecordingOverlayEventStore?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var notificationObservers: [NSObjectProtocol] = []

    init(eventStore: RecordingOverlayEventStore) {
        self.eventStore = eventStore
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        stop()
        promptForAccessibilityIfNeeded()

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: Self.handleEvent,
            userInfo: userInfo
        ) else {
            NSLog("Frame 录屏键盘提示无法创建 CGEvent tap；可能需要在系统设置中允许 Accessibility/输入监听权限。")
            return false
        }

        guard let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0) else {
            CFMachPortInvalidate(eventTap)
            return false
        }

        self.eventTap = eventTap
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        installRecoveryObservers()
        return true
    }

    func stop() {
        removeRecoveryObservers()
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        guard let eventStore else {
            return
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifierFlags = Self.modifierFlags(from: event.flags)
        let time = event.timestamp > 0
            ? TimeInterval(event.timestamp) / 1_000_000_000
            : ProcessInfo.processInfo.systemUptime

        switch type {
        case .flagsChanged:
            if keyCode == 57 {
                eventStore.recordTransientKey(label: "⇪", time: time)
            } else if RecordingOverlayKeyFormatter.isModifierKeyCode(keyCode) {
                eventStore.updateKeyboardModifierFlags(modifierFlags, time: time)
            }
        case .keyDown:
            eventStore.recordKeyDown(
                keyCode: keyCode,
                label: RecordingOverlayKeyFormatter.label(
                    charactersIgnoringModifiers: nil,
                    keyCode: keyCode,
                    modifierFlags: []
                ),
                modifierFlags: modifierFlags,
                time: time
            )
        case .keyUp:
            eventStore.recordKeyUp(keyCode: keyCode, modifierFlags: modifierFlags, time: time)
        default:
            break
        }
    }

    static func modifierFlags(from flags: CGEventFlags) -> NSEvent.ModifierFlags {
        var modifierFlags: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) {
            modifierFlags.insert(.command)
        }
        if flags.contains(.maskShift) {
            modifierFlags.insert(.shift)
        }
        if flags.contains(.maskAlternate) {
            modifierFlags.insert(.option)
        }
        if flags.contains(.maskControl) {
            modifierFlags.insert(.control)
        }
        if flags.contains(.maskAlphaShift) {
            modifierFlags.insert(.capsLock)
        }
        if flags.contains(.maskSecondaryFn) {
            modifierFlags.insert(.function)
        }
        return modifierFlags
    }

    private func installRecoveryObservers() {
        removeRecoveryObservers()
        let workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reenableAfterSystemTransition()
        }
        let applicationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reenableAfterSystemTransition()
        }
        notificationObservers = [workspaceObserver, applicationObserver]
    }

    private func removeRecoveryObservers() {
        for observer in notificationObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func reenableAfterSystemTransition() {
        guard let eventTap else {
            return
        }

        if CFMachPortIsValid(eventTap) {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            _ = start()
        }
    }

    private func promptForAccessibilityIfNeeded() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private static let handleEvent: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let owner = Unmanaged<RecordingKeyboardEventTap>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        owner.handle(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }
}

extension ScreenCaptureRecordingSession: SCStreamOutput, SCStreamDelegate {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else {
            return
        }

        let shouldAppend = stateLock.withLock {
            !isPaused && state == .recording
        }
        guard shouldAppend else {
            return
        }

        do {
            try encoder?.append(sampleBuffer, overlayRenderer: overlayRenderer)
        } catch {
            setState(.failed(error.localizedDescription))
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.removeOverlayEventMonitors()
            self?.liveOverlayController.close()
        }
        setState(.failed(error.localizedDescription))
    }
}
