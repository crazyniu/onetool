# 1Tool

轻量原生 macOS 工具，使用 SwiftUI 与 AppKit，无第三方包依赖。

[English](README.md) · [下载](https://github.com/natefox2017/onetool/releases) · [构建工作流](https://github.com/natefox2017/onetool/actions) · [隐私政策](PRIVACY.md)

- **防止休眠**：30 分钟、1/2/4/8 小时或无限会话，可按电源来源自动开启。
- **Finder 右键操作**：文件模板、常用目录、复制路径、打开终端或编辑器、显示隐藏文件。
- **键盘背光**：亮度、快捷百分比和环境光自动调节。
- **逐屏亮度**：内置屏幕、DDC/CI 外接显示器及软件调暗；退出时恢复原屏幕曲线。
- **默认输入法**：全局默认、应用专属规则及可选 Caps Lock 关闭，修改自动保存并在重启后恢复。
- **原生外观**：浅色／深色／自动主题、九种主色调、八种语言、四行排列的 32 个菜单栏图标和登录启动；防休眠开启时整枚图标变绿。

![防止休眠](docs/images/keep-awake.png)

需要 macOS 14+。正式 DMG 同时支持 Apple Silicon 与 Intel。

```sh
./build.sh
./test.sh
./build.sh --install
ARCHS="arm64 x86_64" ./build.sh
```

源码构建需要完整 Xcode 26+。首次使用 Finder 操作时需启用 Finder 扩展；输入法规则默认关闭；外接显示器需支持并开启 DDC/CI。硬件接口兼容性取决于 Mac、系统版本、显示器和连接方式。退出会结束防休眠并恢复软件调暗。

应用仅在菜单栏显示图标，Dock 中不显示。通过菜单栏面板或图标右键菜单打开设置，关闭设置窗口后继续运行。

GitHub 工作流会在 main 推送、版本标签或手动运行时自动生成通用 DMG，无需 Apple 证书或仓库 Secrets。main 构建提供 Actions 产物，版本标签同时创建带直接下载链接的 Release。应用与 Finder 扩展使用不依赖证书的临时签名，DMG 未经 Apple 签名或公证，首次启动可能需要在系统隐私与安全设置中允许。详见 [RELEASING.md](RELEASING.md)。

GPL-3.0-or-later；上游来源和版权见 [NOTICE.md](NOTICE.md)。欢迎提交问题和 Pull Request。

防休眠可直接在状态栏面板中开关和选择时长，右键菜单也保留直接控制。运行中更改时长会重新计时；自动启动和高级休眠选项收在设置页的折叠区域。
