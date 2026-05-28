# Frame

[English](README.md)

Frame 是一个原生 macOS 截图工具，专注于更快的本地截图流：按下快捷键，框选屏幕区域，然后复制或保存为 PNG。

它刻意保持小而安静。Frame 不是完整的截图工作台，不是云端素材库，也不是标注套件。它首先要做好的，是让日常截图这一步足够短、可靠、不打扰。

## 为什么做 Frame

截图常常只是更大工作流里的一小步：解释想法、反馈问题、保存视觉状态，或把上下文发给别人。Frame 希望这一步尽量不占空间：

- 不打开主窗口，常驻菜单栏。
- 使用 `Command+Shift+A` 开始区域截图。
- 支持多显示器。
- 截图完成后显示一个小型 Quick Access 预览。
- 通过悬浮操作复制、保存或关闭。

## 已有能力

- 区域截图：拖拽选择屏幕上的一块区域，按 Enter 确认。
- PNG 输出：保存文件使用 `Frame yyyy-MM-dd HH.mm.ss.png` 命名。
- 复制到剪贴板：把截图直接粘贴到聊天、文档或其他应用。
- 保存到桌面：把 PNG 文件写入当前用户的 Desktop。
- 多显示器选择：在所有连接的显示器上显示选择覆盖层，并处理 Retina 缩放与屏幕坐标。
- 权限引导：缺少 Screen Recording 权限时给出说明，并打开对应系统设置。

## 隐私与权限

Frame 使用 macOS 屏幕捕获能力，因此需要 Screen Recording 权限。

截图流程完全在本机完成。Frame 不上传截图，不保存截图历史，不需要账号，也不会把截图同步到云端。保存动作只会在你选择保存时写入 PNG；复制动作只会写入系统剪贴板。

如果 macOS 提示 Frame 可以直接访问屏幕内容，这是截图类应用的标准系统权限描述。更多细节见 [macOS Permissions](docs/permissions.md)。

## 暂未包含

Frame 当前不包含：

- 录屏
- 标注工具
- OCR
- 截图历史
- 云同步或分享链接
- 滚动截图

这些能力会在核心本地截图体验稳定后再考虑。

## 项目状态

Frame 处于 MVP 开发阶段。当前优先验证菜单栏生命周期、全局快捷键、Screen Recording 权限处理、多显示器坐标、PNG 输出和 Quick Access 交互的可靠性。

## 开发者入口

README 只保留产品概览。开发、架构和验证细节请查看：

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [macOS Permissions](docs/permissions.md)
- [Design](DESIGN.md)
- [Local Screenshot Loop Spec](docs/superpowers/specs/2026-05-18-local-screenshot-loop-design.md)
- [Local Screenshot Loop Implementation Plan](docs/superpowers/plans/2026-05-18-local-screenshot-loop.md)
