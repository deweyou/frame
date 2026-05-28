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
    private let clipboardWriter = ClipboardWriter()
    private let settingsWindowController = SettingsWindowController()
    private var strings = AppStrings.current()

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

        let quickAccessAnchor = ActiveScreenResolver.preferredQuickAccessAnchor()

        selectionOverlayController.startSelection(strings: strings) { [weak self] selection in
            guard let self,
                  let selection else {
                return
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + overlayDismissalCaptureDelay) { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else {
                        return
                    }

                    do {
                        let screenshot = try await self.captureService.capture(selection: selection)
                        self.showQuickAccess(for: screenshot, anchor: quickAccessAnchor)
                        NSLog("Frame 截图选区类型：\(selection.kind)")
                    } catch {
                        self.showCaptureFailedAlert(error)
                    }
                }
            }
        }
    }

    private func showQuickAccess(for screenshot: CapturedScreenshot, anchor: CGRect?) {
        quickAccessPanelController.show(
            for: screenshot,
            preferredAnchor: anchor,
            strings: strings,
            copy: { [weak self] in
                self?.copyToClipboard(screenshot) ?? false
            },
            save: { [weak self] in
                self?.saveToDesktop(screenshot) ?? false
            },
            openWorkspace: { [weak self] in
                self?.openWorkspace(screenshot, kind: .temporaryPreview) ?? false
            },
            pin: { [weak self] in
                self?.openWorkspace(screenshot, kind: .pinned) ?? false
            },
            close: {
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
                return true
            },
            save: { [weak self] in
                guard let self,
                      self.saveToDesktop(screenshot) else {
                    return false
                }

                self.quickAccessPanelController.closePreview(for: screenshot, notify: false)
                return true
            }
        )
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
