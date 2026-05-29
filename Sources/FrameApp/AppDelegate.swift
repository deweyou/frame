import AppKit
import FrameCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let overlayDismissalCaptureDelay: DispatchTimeInterval = .milliseconds(80)

    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private let selectionOverlayController = SelectionOverlayController()
    private let captureService = CaptureService()
    private let quickAccessPanelController = QuickAccessPanelController()
    private let imageWorkspacePanelController = ImageWorkspacePanelController()
    private let ocrService = OCRService()
    private let ocrTextPanelController = OCRTextPanelController()
    private let clipboardWriter = ClipboardWriter()
    private let settingsWindowController = SettingsWindowController()
    private var strings = AppStrings.current()
    private var activeQuickAccessScreenshotIDs: Set<UUID> = []
    private var recognizingScreenshotIDs: Set<UUID> = []
    private var recognizedTextLayouts: [UUID: RecognizedTextLayout] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        strings = AppStrings.current()
        statusItemController = StatusItemController(
            strings: strings,
            onCapture: { [weak self] in
                self?.onCapture()
            },
            onSettings: { [weak self] in
                self?.onSettings()
            }
        )

        let hotKeyController = HotKeyController(shortcut: SettingsStore.screenshotShortcut())
        hotKeyController.onScreenshot = { [weak self] in
            self?.startCaptureFlow()
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
            }
        )
    }

    func startCaptureFlow() {
        guard ScreenRecordingPermission.hasAccess else {
            ScreenRecordingPermission.showMissingPermissionAlert()
            return
        }

        quickAccessPanelController.temporarilyHidePreviews()

        let quickAccessAnchor = ActiveScreenResolver.preferredQuickAccessAnchor()

        selectionOverlayController.startSelection(strings: strings) { [weak self] selection in
            guard let self else {
                return
            }

            guard let selection else {
                self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + overlayDismissalCaptureDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    do {
                        let screenshot = try await self.captureService.capture(selection: selection)
                        self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                        self.showQuickAccess(for: screenshot, anchor: quickAccessAnchor)
                        NSLog("Frame 截图选区类型：\(selection.kind)")
                    } catch {
                        self.quickAccessPanelController.restoreTemporarilyHiddenPreviews()
                        self.showCaptureFailedAlert(error)
                    }
                }
            }
        }
    }

    private func showQuickAccess(for screenshot: CapturedScreenshot, anchor: CGRect?) {
        activeQuickAccessScreenshotIDs.insert(screenshot.id)
        quickAccessPanelController.show(
            for: screenshot,
            preferredAnchor: anchor,
            strings: strings,
            copy: { [weak self] in
                guard let self else {
                    return false
                }

                let didCopy = self.copyToClipboard(screenshot)
                if didCopy {
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didCopy
            },
            save: { [weak self] in
                guard let self else {
                    return false
                }

                let didSave = self.saveToDesktop(screenshot)
                if didSave {
                    self.endQuickAccessLifecycle(for: screenshot)
                }

                return didSave
            },
            recognizeText: { [weak self] in
                self?.recognizeText(in: screenshot) ?? false
            },
            openWorkspace: { [weak self] in
                self?.openWorkspace(screenshot, kind: .temporaryPreview) ?? false
            },
            pin: { [weak self] in
                guard let self else {
                    return false
                }

                let didOpen = self.openWorkspace(screenshot, kind: .pinned)
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

    private func openWorkspace(_ screenshot: CapturedScreenshot, kind: ImageWorkspaceKind) -> Bool {
        imageWorkspacePanelController.show(
            screenshot: screenshot,
            kind: kind,
            copy: { [weak self] in
                guard let self,
                      self.copyToClipboard(screenshot) else {
                    return false
                }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            },
            save: { [weak self] in
                guard let self,
                      self.saveToDesktop(screenshot) else {
                    return false
                }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                self.endQuickAccessLifecycle(for: screenshot)
                return true
            }
        )
    }

    private func recognizeText(in screenshot: CapturedScreenshot) -> Bool {
        guard activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
            return false
        }

        if let layout = recognizedTextLayouts[screenshot.id] {
            showOCRPanel(layout, for: screenshot)
            return true
        }

        guard !recognizingScreenshotIDs.contains(screenshot.id) else {
            return true
        }

        recognizingScreenshotIDs.insert(screenshot.id)
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
                    self.showOCRNoTextFoundAlert()
                    return
                }

                self.recognizedTextLayouts[screenshot.id] = layout
                self.showOCRPanel(layout, for: screenshot)
            } catch {
                self.recognizingScreenshotIDs.remove(screenshot.id)
                guard self.activeQuickAccessScreenshotIDs.contains(screenshot.id) else {
                    return
                }

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
            copyAll: { [weak self] in
                self?.copyRecognizedText(layout.fullText) ?? false
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
        recognizingScreenshotIDs.remove(screenshot.id)
        recognizedTextLayouts.removeValue(forKey: screenshot.id)
        _ = ocrTextPanelController.closePanel(for: screenshot)
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

        do {
            try hotKeyController.register(shortcut: shortcut)
            SettingsStore.setScreenshotShortcut(shortcut)
            NSLog("Frame 截图快捷键已更新为 \(shortcut.keyboardShortcut.displayName)")
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
