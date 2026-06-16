import AppKit
import FrameCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayDismissalCaptureDelay: DispatchTimeInterval = .milliseconds(80)

    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private let selectionOverlayController: SelectionOverlayControlling
    private let captureService = CaptureService()
    private let quickAccessPanelController = QuickAccessPanelController()
    private let videoPreviewWindowController = VideoPreviewWindowController()
    private let imageWorkspacePanelController = ImageWorkspacePanelController()
    private let captureHistoryStore = CaptureHistoryStore()
    private let ocrService = OCRService()
    private let ocrTextPanelController = OCRTextPanelController()
    private let clipboardWriter = ClipboardWriter()
    private let recordingService: RecordingServicing
    private let recordingFileWriter = RecordingFileWriter()
    private let keyboardHintOverlayController: KeyboardHintOverlayControlling
    private let hasScreenRecordingAccess: () -> Bool
    private let showMissingScreenRecordingPermission: () -> Void
    private let playInvalidActionFeedback: () -> Void
    private let activeRecordingHUDPanelController = ActiveRecordingHUDPanelController()
    private let recordingBoundaryOverlayController = RecordingBoundaryOverlayController()
    private let settingsWindowController = SettingsWindowController()
    private var captureHistoryWindowController: CaptureHistoryWindowController?
    private var strings = AppStrings.current()
    private var activeQuickAccessScreenshotIDs: Set<UUID> = []
    private var activeQuickAccessScreenshots: [UUID: CapturedScreenshot] = [:]
    private var recognizingScreenshotIDs: Set<UUID> = []
    private var recognizedTextLayouts: [UUID: RecognizedTextLayout] = [:]
    private var activeRecordingSession: RecordingSessionControlling?
    private var activeRecordingSelection: SelectionCapture?
    private var activeRecordingOptions = RecordingOptions.defaults
    private var activeRecordingClock: RecordingElapsedClock?
    private var activeRecordingElapsedTimer: Timer?
    private var activeRecordingQuickAccessAnchor: CGRect?
    private var pendingRecordingStartTask: Task<Void, Never>?
    private var isStoppingActiveRecording = false

    init(
        selectionOverlayController: SelectionOverlayControlling = SelectionOverlayController(),
        recordingService: RecordingServicing = ScreenCaptureRecordingService(),
        keyboardHintOverlayController: KeyboardHintOverlayControlling = KeyboardHintOverlayController(),
        hasScreenRecordingAccess: @escaping () -> Bool = { ScreenRecordingPermission.hasAccess },
        showMissingScreenRecordingPermission: @escaping () -> Void = { ScreenRecordingPermission.showMissingPermissionAlert() },
        playInvalidActionFeedback: @escaping () -> Void = { NSSound.beep() }
    ) {
        self.selectionOverlayController = selectionOverlayController
        self.recordingService = recordingService
        self.keyboardHintOverlayController = keyboardHintOverlayController
        self.hasScreenRecordingAccess = hasScreenRecordingAccess
        self.showMissingScreenRecordingPermission = showMissingScreenRecordingPermission
        self.playInvalidActionFeedback = playInvalidActionFeedback
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        strings = AppStrings.current()
        statusItemController = StatusItemController(
            strings: strings,
            onCapture: { [weak self] in
                self?.onCapture()
            },
            onHistory: { [weak self] in
                self?.onHistory()
            },
            onSettings: { [weak self] in
                self?.onSettings()
            },
            onStopRecording: { [weak self] in
                self?.stopActiveRecording()
            }
        )

        try? captureHistoryStore.cleanup()

        let hotKeyController = HotKeyController(
            shortcut: SettingsStore.screenshotShortcut(),
            recordingShortcut: SettingsStore.recordingShortcut()
        )
        hotKeyController.onScreenshot = { [weak self] in
            self?.startCaptureFlow()
        }
        hotKeyController.onRecording = { [weak self] in
            self?.startRecordingCaptureFlow()
        }

        do {
            try hotKeyController.register()
            self.hotKeyController = hotKeyController
        } catch {
            showHotKeyRegistrationFailedAlert(error)
            NSLog("Frame 快捷键注册失败: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyController?.unregister()
    }

    @objc func onCapture() {
        startCaptureFlow()
    }

    @objc func onCheckPermission() {
        if ScreenRecordingPermission.hasAccess {
            showPermissionReadyAlert()
        } else {
            ScreenRecordingPermission.showMissingPermissionAlert()
        }
    }

    @objc func onSettings() {
        settingsWindowController.show(
            strings: strings,
            onShortcutChange: { [weak self] shortcut in
                self?.changeScreenshotShortcut(to: shortcut) ?? false
            },
            onRecordingShortcutChange: { [weak self] shortcut in
                self?.changeRecordingShortcut(to: shortcut) ?? false
            },
            onShortcutRecordingChange: { [weak self] isRecording in
                self?.setScreenshotShortcutRecorderActive(isRecording)
            },
            onCheckPermission: { [weak self] in
                self?.onCheckPermission()
            },
            onLanguageChange: { [weak self] language in
                self?.changeLanguage(to: language)
            },
            onChooseScreenshotDirectory: { [weak self] in
                self?.chooseScreenshotDirectory()
            },
            onResetScreenshotDirectory: {
                SettingsStore.resetScreenshotDirectory()
            },
            onClearCaptureHistory: { [weak self] in
                try self?.captureHistoryStore.clear()
            }
        )
    }

    @objc func onHistory() {
        showCaptureHistory()
    }

    private var isCaptureFlowBusy: Bool {
        selectionOverlayController.isSelecting
            || pendingRecordingStartTask != nil
            || activeRecordingSession != nil
            || isStoppingActiveRecording
    }

    @discardableResult
    func startCaptureFlow() -> Bool {
        startCaptureFlow(initialMode: .screenshot)
    }

    @discardableResult
    private func startRecordingCaptureFlow() -> Bool {
        startCaptureFlow(initialMode: .recordingSetup)
    }

    @discardableResult
    private func startCaptureFlow(initialMode: SelectionOverlayInitialMode) -> Bool {
        guard !isCaptureFlowBusy else {
            recordScreenshotShortcutHintIfRecording()
            playInvalidActionFeedback()
            return false
        }

        guard hasScreenRecordingAccess() else {
            showMissingScreenRecordingPermission()
            return false
        }

        quickAccessPanelController.temporarilyHidePreviews()

        let quickAccessAnchor = ActiveScreenResolver.preferredQuickAccessAnchor()

        selectionOverlayController.startSelection(
            strings: strings,
            initialMode: initialMode,
            onStartRecording: { [weak self] overlayWindow, selection, options in
                self?.startRecording(
                    selection: selection,
                    options: options,
                    overlayWindow: overlayWindow,
                    anchor: quickAccessAnchor
                )
            }
        ) { [weak self] completion in
            guard let self else {
                return
            }

            guard let completion else {
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + overlayDismissalCaptureDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    switch completion {
                    case let .startRecording(selection, options):
                        self.startRecording(
                            selection: selection,
                            options: options,
                            overlayWindow: nil,
                            anchor: quickAccessAnchor
                        )
                    case .fullScreen:
                        do {
                            let screenshots = try self.captureService.captureFullScreens()
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            for screenshot in screenshots {
                                self.storeInCaptureHistory(screenshot)
                                self.showQuickAccess(for: screenshot, anchor: quickAccessAnchor)
                            }
                            NSLog("Frame 已捕获全屏截图：screens=\(screenshots.count)")
                        } catch {
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            self.showCaptureFailedAlert(error)
                        }
                    case let .capture(selection):
                        do {
                            let screenshot = try await self.captureService.capture(selection: selection)
                            self.storeInCaptureHistory(screenshot)
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            self.showQuickAccess(for: screenshot, anchor: quickAccessAnchor)
                            NSLog("Frame 截图选区类型：\(selection.kind)")
                        } catch {
                            self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                            self.showCaptureFailedAlert(error)
                        }
                    case let .recognizeText(selection):
                        await self.recognizeTextFromSelection(selection)
                    }
                }
            }
        }

        return true
    }

    private func recordScreenshotShortcutHintIfRecording() {
        guard let activeRecordingSession else {
            return
        }

        let shortcut = hotKeyController?.shortcut ?? SettingsStore.screenshotShortcut()
        activeRecordingSession.recordKeyboardHint(recordingHintLabel(for: shortcut))
    }

    private func recordingHintLabel(for shortcut: ScreenshotShortcut) -> String {
        shortcut.displayName
    }

    private func recognizeTextFromSelection(_ selection: SelectionCapture) async {
        let screenshot: CapturedScreenshot
        do {
            screenshot = try await captureService.capture(selection: selection)
        } catch {
            quickAccessPanelController.restoreTemporarilyHiddenPreviews()
            showCaptureFailedAlert(error)
            return
        }

        quickAccessPanelController.restoreTemporarilyHiddenPreviews()

        do {
            let layout = try await ocrService.recognizeText(in: screenshot)
            guard !layout.isEmpty else {
                showOCRNoTextFoundAlert()
                return
            }

            showOCRPanel(layout, for: screenshot)
            NSLog("Frame 已从截图 HUD 识别文字：选区类型=\(selection.kind)")
        } catch {
            showQuickAccessFailedAlert(title: strings.ocrFailedTitle, error: error)
        }
    }

    private func showQuickAccess(for screenshot: CapturedScreenshot, anchor: CGRect?) {
        activeQuickAccessScreenshotIDs.insert(screenshot.id)
        activeQuickAccessScreenshots[screenshot.id] = screenshot
        quickAccessPanelController.show(
            for: screenshot,
            preferredAnchor: anchor,
            strings: strings,
            copy: { [weak self] in
                guard let self else {
                    return false
                }

                let currentScreenshot = self.currentQuickAccessScreenshot(for: screenshot)
                let didCopy = self.copyToClipboard(currentScreenshot)
                if didCopy {
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didCopy
            },
            save: { [weak self] in
                guard let self else {
                    return false
                }

                let currentScreenshot = self.currentQuickAccessScreenshot(for: screenshot)
                let didSave = self.saveToDesktop(currentScreenshot)
                if didSave {
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didSave
            },
            recognizeText: { [weak self] in
                guard let self else {
                    return false
                }

                return self.recognizeText(in: self.currentQuickAccessScreenshot(for: screenshot))
            },
            openWorkspace: { [weak self] in
                guard let self else {
                    return false
                }

                return self.openWorkspace(self.currentQuickAccessScreenshot(for: screenshot), kind: .temporaryPreview)
            },
            pin: { [weak self] in
                guard let self else {
                    return false
                }

                let didOpen = self.openWorkspace(self.currentQuickAccessScreenshot(for: screenshot), kind: .pinned)
                if didOpen {
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didOpen
            },
            close: { [weak self] in
                self?.endQuickAccessLifecycle(for: screenshot)
                NSLog("Frame 快速操作已关闭")
            }
        )

        NSLog(
            "Frame 已捕获截图：rect=\(screenshot.rect.debugDescription), pngSize=\(screenshot.pngData.count) bytes"
        )
    }

    private func startRecording(
        selection: SelectionCapture,
        options: RecordingOptions,
        overlayWindow: SelectionOverlayWindow?,
        anchor: CGRect?
    ) {
        guard activeRecordingSession == nil,
              pendingRecordingStartTask == nil else {
            NSSound.beep()
            return
        }

        quickAccessPanelController.setPreviewRestorationSuppressed(true)
        quickAccessPanelController.closePreviewsForRecordingStart()
        keyboardHintOverlayController.hide()

        beginRecordingPreparation(
            selection: selection,
            options: options,
            overlayWindow: overlayWindow,
            anchor: anchor
        )
    }

    private func beginRecordingPreparation(
        selection: SelectionCapture,
        options: RecordingOptions,
        overlayWindow: SelectionOverlayWindow?,
        anchor: CGRect?
    ) {
        activeRecordingQuickAccessAnchor = anchor
        recordingBoundaryOverlayController.show(rect: selection.rect, preparationState: .loading)
        if overlayWindow != nil {
            selectionOverlayController.dismissSelectionForRecording()
        }

        pendingRecordingStartTask = Task { @MainActor [weak self, weak overlayWindow] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, !Task.isCancelled else {
                return
            }
            self.pendingRecordingStartTask = nil
            self.recordingBoundaryOverlayController.updatePreparationState(nil)
            beginRecordingNow(
                selection: selection,
                options: options,
                overlayWindow: overlayWindow,
                anchor: anchor
            )
        }
    }

    private func beginRecordingNow(
        selection: SelectionCapture,
        options: RecordingOptions,
        overlayWindow: SelectionOverlayWindow?,
        anchor: CGRect?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let session = try await self.recordingService.startRecording(
                    RecordingRequest(selection: selection, options: options)
                )
                let startedAt = Date()
                self.activeRecordingSession = session
                self.activeRecordingSelection = selection
                self.activeRecordingOptions = options
                self.activeRecordingClock = RecordingElapsedClock(startedAt: startedAt)
                self.activeRecordingQuickAccessAnchor = anchor
                self.isStoppingActiveRecording = false

                self.recordingBoundaryOverlayController.show(rect: selection.rect)
                self.activeRecordingHUDPanelController.show(
                    near: selection.rect,
                    elapsed: 0,
                    isPaused: false,
                    stop: { [weak self] in
                        self?.stopActiveRecording()
                    },
                    restart: { [weak self] in
                        self?.restartActiveRecording()
                    },
                    delete: { [weak self] in
                        self?.deleteActiveRecording()
                    }
                )
                self.statusItemController?.setRecordingState(.recording)
                self.startRecordingElapsedTimer()

                NSLog("Frame 已开始录屏：rect=\(selection.rect.debugDescription), format=\(options.format.rawValue)")
            } catch {
                self.quickAccessPanelController.setPreviewRestorationSuppressed(false)
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                self.recordingBoundaryOverlayController.close()
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func pauseActiveRecording() {
        guard let session = activeRecordingSession else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await session.pause()
                var clock = self.activeRecordingClock
                clock?.pause(at: Date())
                self.activeRecordingClock = clock
                let elapsed = self.currentRecordingElapsed()
                self.activeRecordingHUDPanelController.update(elapsed: elapsed, isPaused: true)
                self.statusItemController?.setRecordingState(.paused)
                NSLog("Frame 录屏已暂停")
            } catch {
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func resumeActiveRecording() {
        guard let session = activeRecordingSession else {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                try await session.resume()
                var clock = self.activeRecordingClock
                clock?.resume(at: Date())
                self.activeRecordingClock = clock
                let elapsed = self.currentRecordingElapsed()
                self.activeRecordingHUDPanelController.update(elapsed: elapsed, isPaused: false)
                self.statusItemController?.setRecordingState(.recording)
                NSLog("Frame 录屏已继续")
            } catch {
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func stopActiveRecording() {
        guard let session = activeRecordingSession,
              !isStoppingActiveRecording else {
            return
        }

        isStoppingActiveRecording = true
        let duration = currentRecordingElapsed()
        activeRecordingElapsedTimer?.invalidate()
        activeRecordingElapsedTimer = nil
        activeRecordingHUDPanelController.setStopping(true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let capturedRecording = try await session.stop()
                let recording = CapturedRecording(
                    id: capturedRecording.id,
                    fileURL: capturedRecording.fileURL,
                    format: capturedRecording.format,
                    rect: capturedRecording.rect,
                    pixelSize: capturedRecording.pixelSize,
                    byteSize: capturedRecording.byteSize,
                    duration: duration
                )
                let stableRecording = self.storeInCaptureHistory(recording)
                let anchor = self.activeRecordingQuickAccessAnchor
                self.finishActiveRecording()
                self.showVideoQuickAccess(for: stableRecording, anchor: anchor)
                NSLog(
                    "Frame 已停止录屏：url=\(stableRecording.fileURL.path), duration=\(stableRecording.duration)"
                )
            } catch {
                self.finishActiveRecording()
                self.showCaptureFailedAlert(error)
            }
        }
    }

    private func restartActiveRecording() {
        guard let session = activeRecordingSession,
              let selection = activeRecordingSelection else {
            return
        }
        let options = activeRecordingOptions
        let anchor = activeRecordingQuickAccessAnchor
        activeRecordingHUDPanelController.setStopping(true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await session.cancel()
            self.finishActiveRecording()
            self.startRecording(
                selection: selection,
                options: options,
                overlayWindow: nil,
                anchor: anchor
            )
            NSLog("Frame 录屏已重新开始")
        }
    }

    private func deleteActiveRecording() {
        guard let session = activeRecordingSession else {
            return
        }
        activeRecordingHUDPanelController.setStopping(true)

        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await session.cancel()
            self.finishActiveRecording()
            NSLog("Frame 录屏已删除")
        }
    }

    private func startRecordingElapsedTimer() {
        activeRecordingElapsedTimer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshRecordingElapsedHUD()
            }
        }
        activeRecordingElapsedTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshRecordingElapsedHUD() {
        let isPaused = activeRecordingSession?.state == .paused
        activeRecordingHUDPanelController.update(elapsed: currentRecordingElapsed(), isPaused: isPaused)
    }

    private func currentRecordingElapsed() -> TimeInterval {
        activeRecordingClock?.elapsed(at: Date()) ?? 0
    }

    private func finishActiveRecording() {
        pendingRecordingStartTask?.cancel()
        pendingRecordingStartTask = nil
        activeRecordingElapsedTimer?.invalidate()
        activeRecordingElapsedTimer = nil
        activeRecordingHUDPanelController.close()
        recordingBoundaryOverlayController.close()
        keyboardHintOverlayController.hide()
        statusItemController?.setRecordingState(.idle)
        activeRecordingSession = nil
        activeRecordingSelection = nil
        activeRecordingClock = nil
        activeRecordingQuickAccessAnchor = nil
        isStoppingActiveRecording = false
        quickAccessPanelController.setPreviewRestorationSuppressed(false)
    }

    func startRecordingForTesting(
        selection: SelectionCapture,
        options: RecordingOptions,
        anchor: CGRect? = nil
    ) {
        startRecording(
            selection: selection,
            options: options,
            overlayWindow: nil,
            anchor: anchor
        )
    }

    @discardableResult
    func startCaptureFlowForTesting() -> Bool {
        startCaptureFlow()
    }

    @discardableResult
    func startRecordingCaptureFlowForTesting() -> Bool {
        startRecordingCaptureFlow()
    }

    func finishActiveRecordingForTesting() {
        finishActiveRecording()
    }

    func stopActiveRecordingForTesting() {
        stopActiveRecording()
    }

    func restartActiveRecordingForTesting() {
        restartActiveRecording()
    }

    func deleteActiveRecordingForTesting() {
        deleteActiveRecording()
    }

    func activeRecordingElapsedTimerIsValidForTesting() -> Bool {
        activeRecordingElapsedTimer?.isValid == true
    }

    func hasActiveRecordingForTesting() -> Bool {
        activeRecordingSession != nil && activeRecordingSelection != nil
    }

    private func showVideoQuickAccess(for recording: CapturedRecording, anchor: CGRect?) {
        quickAccessPanelController.show(
            for: recording,
            preferredAnchor: anchor,
            strings: strings,
            download: { [weak self] in
                self?.downloadRecording(recording) ?? false
            },
            copy: { [weak self] in
                self?.copyRecordingToClipboard(recording) ?? false
            },
            preview: { [weak self] in
                self?.openVideoPreview(recording) ?? false
            },
            edit: { [weak self] in
                self?.openVideoPreview(recording, focusEditor: true) ?? false
            },
            close: {
                NSLog("Frame 录屏快速操作已关闭")
            }
        )
    }

    private func openVideoPreview(_ recording: CapturedRecording, focusEditor: Bool = false) -> Bool {
        videoPreviewWindowController.show(
            recording: recording,
            strings: strings,
            copy: { [weak self] in
                self?.copyRecordingToClipboard(recording) ?? false
            },
            download: { [weak self] in
                self?.downloadRecording(recording) ?? false
            },
            saveCurrent: { [weak self] recording, editingState, choice in
                self?.saveEditedRecording(recording, editingState: editingState, choice: choice) ?? false
            },
            focusEditor: focusEditor
        )
        return true
    }

    private func saveEditedRecording(
        _ recording: CapturedRecording,
        editingState: VideoEditingState,
        choice: VideoPreviewSaveChoice
    ) -> Bool {
        showQuickAccessFailedAlert(
            title: strings.saveFailedTitle,
            error: VideoEditingExportError.exportFailed("录屏编辑导出尚未连接。")
        )
        return false
    }

    private func showCaptureHistory() {
        let controller = captureHistoryWindowController ?? CaptureHistoryWindowController(
            store: captureHistoryStore,
            restore: { [weak self] record in
                self?.restoreHistoryRecord(record)
            },
            copy: { [weak self] record in
                self?.copyHistoryRecord(record)
            },
            save: { [weak self] record in
                self?.saveHistoryRecord(record)
            },
            delete: { [weak self] record in
                self?.deleteHistoryRecord(record)
            }
        )
        captureHistoryWindowController = controller
        controller.show(strings: strings)
    }

    private func storeInCaptureHistory(_ screenshot: CapturedScreenshot) {
        do {
            _ = try captureHistoryStore.addScreenshot(screenshot)
        } catch {
            NSLog("Frame 写入截图历史失败: \(error.localizedDescription)")
        }
    }

    private func storeInCaptureHistory(_ recording: CapturedRecording) -> CapturedRecording {
        do {
            let recordingData = try Data(contentsOf: recording.fileURL)
            guard let record = try captureHistoryStore.addRecording(
                data: recordingData,
                filenameExtension: recording.format.fileExtension,
                pixelSize: recording.pixelSize,
                rect: recording.rect
            ) else {
                return recording
            }

            return CapturedRecording(
                id: record.id,
                fileURL: captureHistoryStore.fileURL(for: record),
                format: recording.format,
                rect: record.rect,
                pixelSize: CGSize(width: CGFloat(record.pixelWidth), height: CGFloat(record.pixelHeight)),
                byteSize: record.byteSize,
                duration: recording.duration
            )
        } catch {
            NSLog("Frame 写入录屏历史失败: \(error.localizedDescription)")
            return recording
        }
    }

    private func screenshot(from record: CaptureHistoryRecord) throws -> CapturedScreenshot {
        let data = try captureHistoryStore.data(for: record)
        guard let image = NSImage(data: data) else {
            throw CaptureHistoryError.imageDecodeFailed
        }

        return CapturedScreenshot(pngData: data, image: image, rect: record.rect)
    }

    private func restoreHistoryRecord(_ record: CaptureHistoryRecord) {
        guard record.kind == .screenshot else {
            NSWorkspace.shared.open(captureHistoryStore.fileURL(for: record))
            return
        }

        do {
            showQuickAccess(
                for: try screenshot(from: record),
                anchor: ActiveScreenResolver.preferredQuickAccessFollowAnchor()
            )
        } catch {
            showQuickAccessFailedAlert(title: strings.captureFailedTitle, error: error)
        }
    }

    private func copyHistoryRecord(_ record: CaptureHistoryRecord) {
        guard record.kind == .screenshot else {
            do {
                try clipboardWriter.write(fileURL: captureHistoryStore.fileURL(for: record))
            } catch {
                showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            }
            return
        }

        do {
            _ = copyToClipboard(try screenshot(from: record))
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
        }
    }

    private func saveHistoryRecord(_ record: CaptureHistoryRecord) {
        guard record.kind == .screenshot else {
            guard let format = recordingFormat(for: record) else {
                return
            }

            do {
                _ = try recordingFileWriter.copyRecording(
                    from: captureHistoryStore.fileURL(for: record),
                    format: format,
                    date: record.createdAt
                )
            } catch {
                showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            }
            return
        }

        do {
            _ = saveToDesktop(try screenshot(from: record))
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
        }
    }

    private func deleteHistoryRecord(_ record: CaptureHistoryRecord) {
        do {
            try captureHistoryStore.delete(recordID: record.id)
        } catch {
            showQuickAccessFailedAlert(title: strings.captureHistoryDelete, error: error)
        }
    }

    private func openWorkspace(_ screenshot: CapturedScreenshot, kind: ImageWorkspaceKind) -> Bool {
        imageWorkspacePanelController.show(
            screenshot: screenshot,
            kind: kind,
            strings: strings,
            copy: { [weak self] editedScreenshot in
                guard let self,
                      self.copyToClipboard(editedScreenshot) else {
                    return false
                }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            },
            save: { [weak self] editedScreenshot in
                guard let self,
                      self.saveToDesktop(editedScreenshot) else {
                    return false
                }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            },
            recognizeText: { [weak self] screenshot in
                guard let self else {
                    throw OCRServiceError.cgImageUnavailable
                }

                return try await self.ocrService.recognizeText(in: screenshot)
            },
            copyRecognizedText: { [weak self] text in
                self?.copyRecognizedText(text) ?? false
            },
            replaceCurrent: { [weak self] editedScreenshot in
                guard let self else {
                    return
                }

                guard self.activeQuickAccessScreenshotIDs.contains(editedScreenshot.id) else {
                    return
                }

                self.activeQuickAccessScreenshots[editedScreenshot.id] = editedScreenshot
                self.quickAccessPanelController.updatePreview(for: editedScreenshot)
            },
            saveAsNew: { [weak self] editedScreenshot in
                guard let self else {
                    return false
                }

                self.showQuickAccess(for: editedScreenshot, anchor: editedScreenshot.rect)
                return true
            }
        )
    }

    private func recognizeText(in screenshot: CapturedScreenshot) -> Bool {
        guard activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
            return false
        }

        if let layout = recognizedTextLayouts[screenshot.id] {
            quickAccessPanelController.setOCRStatus(.idle(accessibilityLabel: strings.quickAccessOCR), for: screenshot)
            showOCRPanel(layout, for: screenshot)
            return true
        }

        guard !recognizingScreenshotIDs.contains(screenshot.id) else {
            return true
        }

        recognizingScreenshotIDs.insert(screenshot.id)
        quickAccessPanelController.setOCRStatus(.recognizing(strings.ocrRecognizing), for: screenshot)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let layout = try await self.ocrService.recognizeText(in: screenshot)
                self.recognizingScreenshotIDs.remove(screenshot.id)

                guard self.activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
                    return
                }

                guard !layout.isEmpty else {
                    self.quickAccessPanelController.setOCRStatus(
                        .message(self.strings.ocrNoTextFound, resetAfter: 2.2),
                        for: screenshot
                    )
                    return
                }

                self.recognizedTextLayouts[screenshot.id] = layout
                self.quickAccessPanelController.setOCRStatus(
                    .idle(accessibilityLabel: self.strings.quickAccessOCR),
                    for: screenshot
                )
                self.showOCRPanel(layout, for: screenshot)
            } catch {
                self.recognizingScreenshotIDs.remove(screenshot.id)
                guard self.activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
                    return
                }

                self.quickAccessPanelController.setOCRStatus(
                    .message(self.strings.ocrFailedTitle, resetAfter: 2.2),
                    for: screenshot
                )
                self.showQuickAccessFailedAlert(title: self.strings.ocrFailedTitle, error: error)
            }
        }

        return true
    }

    private func showOCRPanel(_ layout: RecognizedTextLayout, for screenshot: CapturedScreenshot) {
        ocrTextPanelController.show(
            layout: layout,
            for: screenshot,
            strings: strings,
            copyText: { [weak self] text in
                guard let self,
                      self.copyRecognizedText(text) else {
                    return false
                }

                self.quickAccessPanelController.setOCRStatus(
                    .message(self.strings.ocrCopied, resetAfter: 1.4),
                    for: screenshot
                )
                return true
            }
        )
    }

    private func copyRecognizedText(_ text: String) -> Bool {
        do {
            try clipboardWriter.write(text: text)
            NSLog("Frame 已复制识别文字到剪贴板")
            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            return false
        }
    }

    private func showOCRNoTextFoundAlert() {
        let alert = NSAlert()
        alert.messageText = strings.ocrNoTextFound
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func endQuickAccessLifecycle(for screenshot: CapturedScreenshot) {
        activeQuickAccessScreenshotIDs.remove(screenshot.id)
        activeQuickAccessScreenshots.removeValue(forKey: screenshot.id)
        recognizingScreenshotIDs.remove(screenshot.id)
        recognizedTextLayouts.removeValue(forKey: screenshot.id)
        _ = ocrTextPanelController.closePanel(for: screenshot)
    }

    private func currentQuickAccessScreenshot(for screenshot: CapturedScreenshot) -> CapturedScreenshot {
        activeQuickAccessScreenshots[screenshot.id] ?? screenshot
    }

    private func copyToClipboard(_ screenshot: CapturedScreenshot) -> Bool {
        do {
            try clipboardWriter.write(image: screenshot.image)
            NSLog("Frame 已复制截图到剪贴板")
            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            return false
        }
    }

    private func copyRecordingToClipboard(_ recording: CapturedRecording) -> Bool {
        do {
            try clipboardWriter.write(fileURL: recording.fileURL)
            NSLog("Frame 已复制录屏文件到剪贴板")
            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.copyFailedTitle, error: error)
            return false
        }
    }

    private func saveToDesktop(_ screenshot: CapturedScreenshot) -> Bool {
        do {
            let saveURL = try ScreenshotFileWriter(strings: strings).write(pngData: screenshot.pngData)
            NSLog("Frame 已保存截图：\(saveURL.path)")
            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            return false
        }
    }

    private func downloadRecording(_ recording: CapturedRecording) -> Bool {
        do {
            let saveURL = try recordingFileWriter.copyRecording(
                from: recording.fileURL,
                format: recording.format
            )
            NSLog("Frame 已保存录屏：\(saveURL.path)")
            return true
        } catch {
            showQuickAccessFailedAlert(title: strings.saveFailedTitle, error: error)
            return false
        }
    }

    private func recordingFormat(for record: CaptureHistoryRecord) -> RecordingFormat? {
        RecordingFormat(rawValue: (record.filename as NSString).pathExtension)
    }

    private func chooseScreenshotDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.title = strings.settingsSaveLocation
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK,
              let directory = panel.url else {
            return nil
        }

        return directory
    }

    private func changeLanguage(to language: AppLanguage) {
        SettingsStore.setAppLanguage(language)
        strings = AppStrings.current()
        statusItemController?.reloadMenu(strings: strings)
        settingsWindowController.update(strings: strings)
    }

    private func changeScreenshotShortcut(to shortcut: ScreenshotShortcut) -> Bool {
        guard let hotKeyController else {
            SettingsStore.setScreenshotShortcut(shortcut)
            return true
        }

        let previousShortcut = hotKeyController.shortcut
        let recordingShortcut = hotKeyController.recordingShortcut

        do {
            try hotKeyController.register(shortcut: shortcut, recordingShortcut: recordingShortcut)
            SettingsStore.setScreenshotShortcut(shortcut)
            NSLog("Frame 截图快捷键已更新为 \(shortcut.displayName)")
            return true
        } catch {
            do {
                try hotKeyController.register(shortcut: previousShortcut)
            } catch {
                NSLog("Frame 恢复原快捷键失败: \(error.localizedDescription)")
            }

            showHotKeyRegistrationFailedAlert(error)
            return false
        }
    }

    private func changeRecordingShortcut(to shortcut: ScreenshotShortcut) -> Bool {
        guard let hotKeyController else {
            SettingsStore.setRecordingShortcut(shortcut)
            return true
        }

        let screenshotShortcut = hotKeyController.shortcut
        let previousShortcut = hotKeyController.recordingShortcut

        do {
            try hotKeyController.register(shortcut: screenshotShortcut, recordingShortcut: shortcut)
            SettingsStore.setRecordingShortcut(shortcut)
            NSLog("Frame 录屏快捷键已更新为 \(shortcut.displayName)")
            return true
        } catch {
            do {
                try hotKeyController.register(shortcut: screenshotShortcut, recordingShortcut: previousShortcut)
            } catch {
                NSLog("Frame 恢复原录屏快捷键失败: \(error.localizedDescription)")
            }

            showHotKeyRegistrationFailedAlert(error)
            return false
        }
    }

    private func setScreenshotShortcutRecorderActive(_ isRecording: Bool) {
        guard let hotKeyController else {
            return
        }

        if isRecording {
            hotKeyController.unregister()
            return
        }

        do {
            try hotKeyController.register()
        } catch {
            showHotKeyRegistrationFailedAlert(error)
        }
    }

    private func showHotKeyRegistrationFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = strings.hotKeyRegistrationFailedTitle
        alert.informativeText = strings.hotKeyRegistrationFailedMessage(errorDescription: error.localizedDescription)
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showCaptureFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = strings.captureFailedTitle
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showPermissionReadyAlert() {
        let alert = NSAlert()
        alert.messageText = strings.permissionReadyTitle
        let shortcut = SettingsStore.screenshotShortcut().keyboardShortcut.displayName
        alert.informativeText = strings.permissionReadyMessage(shortcut: shortcut)
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }

    private func showQuickAccessFailedAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: strings.ok)
        alert.runModal()
    }
}

private enum CaptureHistoryError: Error, LocalizedError {
    case imageDecodeFailed

    var errorDescription: String? {
        switch self {
        case .imageDecodeFailed:
            "Could not decode the cached capture image."
        }
    }
}
