# 系统外观

外观页与状态栏右键菜单中的「系统外观」修改 macOS 的浅色、深色、自动模式。1Tool 主窗口和快捷面板跟随系统；旧 `appearance.scheme` 偏好不再覆盖窗口，也不会在启动时写入系统设置。应用主色和 Liquid Glass 开关仍仅控制 1Tool。

`SystemTheme` 是两个入口的共同状态源。自动模式与当前有效深浅色分开记录；监听系统通知、回到前台以及低频读取以同步外部变化。切换后核对实时状态和持久化偏好；未确认的变更尝试恢复前一模式，并显示实际状态与恢复指引。菜单失败会打开外观页，不静默显示成功。

该功能通过运行时检查的 **私有 SkyLight 接口** 实现，当前 macOS 已验证，不构成未来 macOS 或 Mac App Store 兼容承诺。缺少接口时禁用直接切换并提供系统设置入口；不使用 Apple Events、辅助功能自动点击或直接改写系统偏好。权限页将接口可用性与隐私授权区分显示。

实现为本项目独立代码。接口签名和行为研究参考 [Morphic SkyLight 声明](https://github.com/raisingthefloor/morphic-macos/blob/6dba8901399a1e49fa3525f9ced93d95bf210f8d/MorphicSettings/MorphicSettings/Display/include/SkyLight.h)、[Morphic 外观控制](https://github.com/raisingthefloor/morphic-macos/blob/6dba8901399a1e49fa3525f9ced93d95bf210f8d/MorphicSettings/MorphicSettings/Display/MorphicDisplayAppearance.swift) 和 [MacTools 系统外观控制](https://github.com/mactools-app/MacTools/blob/08754ad4509533682dfc19d6ea1326e6441a8d4e/Plugins/Appearance/Sources/SystemAppearanceController.swift)。未复制这些项目的源码或资源。

## 2026-10-23 原生验证

独立开发签名宿主 `org.onetool.theme-review.20261023` 使用原样生产服务、外观页、侧栏和样式。窗口截图 1840×1520 像素（2×，920×760 pt），证据位于 `build/theme-validation/`。

| 验证 | 结果 |
| --- | --- |
| 逻辑检查 | 11 PASS：启动只读；浅/深/自动；自动保留策略；外部变化；接口缺失；系统拒绝；持久化不一致；恢复；重试；并发防重入 |
| 宿主点击深色 | PASS：UI 选中深色、窗口深色，独立 SkyLight getter=1，系统全局 AppleInterfaceStyle=Dark |
| 宿主点击自动 | PASS：UI 选中自动，getter automatic=1，持久化 automatic=1；系统设置重新进入外观后自动被选中，见 system-auto.txt/png |
| 系统设置改回浅色 | PASS：系统 getter dark=0/auto=0，宿主自动选中浅色并恢复浅色窗口；见 external-light-sync.txt 与 light-active.png |
| 活动窗口颜色 | PASS：auto-active.png 显示系统蓝开关、控件与蓝底白字选中行；dark-yellow.png 显示黄主色的独立深色选中背景与可读白字 |
| 旧 app-local 模式 | 源码移除全部 preferredColorScheme 和 appearance.scheme 读取；启动不应用旧偏好 |
| 状态栏菜单实际选择 | NOT RUN：菜单事件跟踪已启动，但原生工具只捕获主窗口，未取得子菜单点击证据；Escape 结束跟踪。主集成与独立审查两次遇到相同捕获限制；源码接入与编译通过，不能代替实际菜单交互 PASS |
| 测试结束 | 系统恢复原始浅色（dark=0/auto=0）；独立宿主已退出；正式应用与用户主色偏好未在本次宿主测试中修改 |

系统设置已打开的外观页可能保留旧选择，重新进入该页后反映系统真实策略。原生菜单展开期间系统会延后窗口外观变化；本次确认关闭菜单后同步恢复，没有以更快轮询掩盖该状态。跨越日落/日出调度、老版本 macOS 和 Intel 实机尚未验证。
