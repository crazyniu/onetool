# 验证记录

日期：2026-10-19，Asia/Taipei。环境：Apple Silicon、macOS 27.0.1、Xcode 27.1。

状态仅对应以下证据；构建与源码对齐不替代设备验证。

| 项目 | 状态 | 实际证据 |
| --- | --- | --- |
| 主应用和 Finder 扩展构建 | PASS | build.sh；本机 Apple Development 签名；codesign --verify --deep --strict |
| Swift Package 开发入口 | PASS | swift build，主应用开发编译通过 |
| 应用身份 | PASS | 已安装 /Applications/1Tool.app；CFBundleIdentifier=com.shopkivoo.onetool；窗口/菜单/显示名称 1Tool |
| 核心检查 | PASS | test.sh：36 项，含路径/文件名、独占创建、符号链接防覆盖、模板、Office 真文档、IPC、转义、输入规则、DDC 报文/校验/路由和真实 IOPM 定时释放 |
| 硬件补充检查 | PASS | test.sh --hardware：累计 40 项；ABC 实际切换及恢复；键盘实际写入0.04并读回；逐屏 gamma 调暗、另一屏不变、精确恢复 |
| 防止休眠界面主流程 | PASS | 原生界面开始/结束、倒计时、配置禁用状态；pmset 显示该进程的系统/屏幕断言；结束后消失 |
| 内置屏幕亮度 | PASS | 界面100%→96%，刷新实际读回0.9599999785；恢复100% |
| GX400WQR 外接屏幕 | PASS | DDC 界面29%→31%，刷新仍31%；内置屏幕保持100%；恢复29% |
| 键盘背光界面 | PASS | 环境光自动调节开启时写入受抑制；手动调节关闭自动调节后25%写入并刷新读回25%；恢复0%和自动调节 |
| 默认输入法 | PASS | 全局/专属/跟随系统/不可用规则检查；真实延迟切换到ABC并恢复；新应用默认未启用，避免与其他自动切换工具冲突 |
| 右键代码迁移 | PASS | FinderSync.swift 仅类名适配后与参考原文件一致；模板实现一致；Office 模板二进制一致；服务/软件检测/禁用与隐藏文件路径直接移植，见PORTING.md |
| Finder 菜单展示 | PASS | 当前 Finder 真实菜单显示四组、TXT/Markdown/JSON、常用目录、Terminal/iTerm2/Visual Studio Code/Xcode与隐藏文件；菜单文件与原项目一致 |
| 文件创建动作 | PASS | 最终服务通过真实主应用IPC弹出原版Untitled.json对话框；原生界面创建 /tmp/onetool-finder-smoke/ported.json 与 Lexar 测试目录 external-port.json；内容均为 {} 加换行。迁移前另验证过真实Finder菜单到文件创建全流程 |
| 复制路径动作 | PASS | 真实主应用IPC执行，剪贴板内容精确等于测试目录；检查后恢复原剪贴板 |
| 终端目录打开动作 | PASS | 系统设置确认1Tool→终端自动化开启；真实主应用IPC执行；Terminal子shell工作目录分别为本机测试目录和包含空格、单引号的Lexar目录。终端窗口自动读取受工具限制，以进程工作目录核验 |
| 隐藏文件动作 | PASS | 真实主应用IPC调用原项目逻辑，AppleShowAllFiles由未设置/false→true→false；Finder重启；恢复原显示状态。该路径不需System Events或辅助功能 |
| 外观/图标 | PASS | 原生页面12个选项；选择咖啡后实时预览更新；偏好保存；退出重开保留；浅色/深色页面实际检查 |
| 登录启动、真实重启、拔插屏幕 | NOT RUN | 实现使用SMAppService；未为了验收更改登录启动或进行实际关机、拔插 |
| 其他显示器、Intel、macOS14–26 | NOT RUN | 当前设备之外的兼容性未作真机验证 |
| 发布/公证/App Store | NOT RUN | 用户要求本机独立项目；未进行对外发布 |

UI：五个工具和外观页面均已打开检查，关键滑块、开关、菜单与文件对话框通过原生工具验证。设置保持独立设计；Finder菜单使用原代码。

系统权限：可移动宗卷访问和终端自动化在系统设置中确认开启。系统通知中心与终端窗口不允许桌面工具自动读取，未绕过该限制。原项目的隐藏文件实现已移植，因此无需增加辅助功能或System Events权限。

测试仅在新项目build目录和独立/tmp目录创建文件；原项目代码保持未改动。旧工具的输入法配置未更改。
