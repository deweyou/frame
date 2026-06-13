# Frame

[English](README.md)

Frame 是一个原生 macOS 捕获工具，专注于更快的本地截图与录屏流：按下快捷键，框选屏幕区域，然后在本机复制、保存、预览或找回结果。

它刻意保持小而安静。Frame 不是完整的截图工作台，不是云端素材库，也不是标注套件。它首先要做好的，是让日常截图这一步足够短、可靠、不打扰。

## 为什么做 Frame

截图常常只是更大工作流里的一小步：解释想法、反馈问题、保存视觉状态，或把上下文发给别人。Frame 希望这一步尽量不占空间：

- 不打开主窗口，常驻菜单栏。
- 默认使用 `Command+Shift+A` 开始区域截图，使用 `Command+Shift+R`
  直接进入录屏设置；两个快捷键都可在设置中自定义。
- 支持多显示器。
- 截图和录屏完成后显示一个小型 Quick Access 预览，短暂停留后可查看更大的悬浮预览。
- 通过悬浮操作复制、保存或关闭。
- 保留本地捕获历史，方便找回最近的截图和录屏。

## 已有能力

- 区域截图：拖拽选择屏幕上的一块区域，按 Enter 确认。
- 窗口截图：双击可捕获的应用窗口，输出带样式的窗口截图，并可在设置中选择样式。
- PNG 输出：保存文件使用 `Frame yyyy-MM-dd HH.mm.ss.png` 命名。
- 复制到剪贴板：把截图直接粘贴到聊天、文档或其他应用。
- 保存位置：把 PNG 文件写入当前截图保存目录，默认是 Desktop。
- 选区录屏：使用录屏快捷键或把选区 HUD 切换到录屏模式，选择 MP4 或 GIF，统一显示或隐藏鼠标指针与点击提示，并可在设置中自定义鼠标提示颜色；录入按住中的键盘提示，并从录屏 HUD 或红色菜单栏录制状态停止、重新开始或删除。
- 录屏输出：复制录屏文件，下载到当前保存目录，或打开可播放预览。编辑入口可见但暂未启用。
- 本地捕获历史：从菜单栏找回最近的截图和录屏；录屏会尽量显示首帧缩略图。历史默认开启，默认保留 7 天，并使用 2 GB 本地缓存上限。
- 多显示器选择：在所有连接的显示器上显示选择覆盖层，并处理 Retina 缩放与屏幕坐标。
- 窗口截图样式：窗口截图可选择柔和背景、画布光影或透明投影。
- 权限引导：缺少 Screen Recording 权限时给出说明，并打开对应系统设置。

## 隐私与权限

Frame 使用 macOS 屏幕捕获能力，因此需要 Screen Recording 权限。

截图和录屏流程完全在本机完成。Frame 不上传截图或录屏，不需要账号，也不会把捕获内容同步到云端。捕获历史只保存在 Frame 自己的本地 Application Support 缓存中，可以在设置里关闭或清空。保存或下载动作只会在你选择保存时额外写入文件；复制动作只会把图片内容或录屏文件 URL 写入系统剪贴板。

如果 macOS 提示 Frame 可以直接访问屏幕内容，这是截图类应用的标准系统权限描述。更多细节见 [macOS Permissions](docs/permissions.md)。

## 暂未包含

Frame 当前不包含：

- 音频录制
- 标注工具
- 云同步或分享链接
- 滚动截图

这些能力会在核心本地捕获体验稳定后再考虑。

## 项目状态

Frame 处于 MVP 开发阶段。当前优先验证菜单栏生命周期、全局快捷键、Screen Recording 权限处理、单显示器选区录屏、PNG/MP4/GIF 输出和 Quick Access 交互的可靠性。

## 开发者入口

README 只保留产品概览。开发、架构和验证细节请查看：

- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [macOS Permissions](docs/permissions.md)
- [Design](DESIGN.md)
- [Local Screenshot Loop Spec](docs/superpowers/specs/2026-05-18-local-screenshot-loop-design.md)
- [Local Screenshot Loop Implementation Plan](docs/superpowers/plans/2026-05-18-local-screenshot-loop.md)
