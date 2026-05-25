import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var hotKeyController: HotKeyController?
    private let selectionOverlayController = SelectionOverlayController()
    private let captureService = CaptureService()
    private let quickAccessPanelController = QuickAccessPanelController()
    private let clipboardWriter = ClipboardWriter()
    private let screenshotFileWriter = ScreenshotFileWriter()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItemController = StatusItemController(
            onCapture: { [weak self] in
                self?.onCapture()
            },
            onCheckPermission: { [weak self] in
                self?.onCheckPermission()
            }
        )

        let hotKeyController = HotKeyController()
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

    func startCaptureFlow() {
        guard ScreenRecordingPermission.hasAccess else {
            ScreenRecordingPermission.showMissingPermissionAlert()
            return
        }

        let quickAccessAnchor = ActiveScreenResolver.preferredQuickAccessAnchor()

        selectionOverlayController.startSelection { [weak self] selectedRect in
            guard let self,
                  let selectedRect else {
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let screenshot = try captureService.capture(rect: selectedRect)
                    showQuickAccess(for: screenshot, anchor: quickAccessAnchor)
                } catch {
                    showCaptureFailedAlert(error)
                }
            }
        }
    }

    private func showQuickAccess(for screenshot: CapturedScreenshot, anchor: CGRect?) {
        quickAccessPanelController.show(
            for: screenshot,
            preferredAnchor: anchor,
            copy: { [weak self] in
                self?.copyToClipboard(screenshot) ?? false
            },
            save: { [weak self] in
                self?.saveToDesktop(screenshot) ?? false
            },
            close: {
                NSLog("Frame 快速操作已关闭")
            }
        )

        NSLog(
            "Frame 已捕获截图：rect=\(screenshot.rect.debugDescription), pngSize=\(screenshot.pngData.count) bytes"
        )
    }

    private func copyToClipboard(_ screenshot: CapturedScreenshot) -> Bool {
        do {
            try clipboardWriter.write(image: screenshot.image)
            NSLog("Frame 已复制截图到剪贴板")
            return true
        } catch {
            showQuickAccessFailedAlert(title: "Frame 复制失败", error: error)
            return false
        }
    }

    private func saveToDesktop(_ screenshot: CapturedScreenshot) -> Bool {
        do {
            let saveURL = try screenshotFileWriter.write(pngData: screenshot.pngData)
            NSLog("Frame 已保存截图：\(saveURL.path)")
            return true
        } catch {
            showQuickAccessFailedAlert(title: "Frame 保存失败", error: error)
            return false
        }
    }

    private func showHotKeyRegistrationFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Frame 快捷键注册失败"
        alert.informativeText = "Command+Shift+A 暂时无法使用。你仍然可以通过菜单栏使用截图功能。\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showCaptureFailedAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Frame 截图失败"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showPermissionReadyAlert() {
        let alert = NSAlert()
        alert.messageText = "Frame 屏幕录制权限已开启"
        alert.informativeText = "你可以使用 Command+Shift+A 或菜单栏截图入口开始区域截图。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func showQuickAccessFailedAlert(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
