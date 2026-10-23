# 应用卸载验证记录

日期：2026-10-23（台北时间）。本次功能以 `Sources/OneTool/Uninstall.swift`、`UninstallEngine.swift` 为唯一实现，重复草稿保留在忽略的 `build/reference-drafts/`，不参与编译。

## 首轮版本验证（后续修复见末节）

- `CODE_SIGN_IDENTITY=- ./build.sh`：Apple Silicon / macOS 14 部署目标构建通过，宿主与 Finder 扩展完成本地 ad-hoc 签名及校验。该签名用于本地验证，不代表 Developer ID 签名或 Apple 公证。
- `./test.sh`：233 项通过，完整日志 `build/uninstall-validation/final-checks.log`。覆盖既有工具、缓存清理、包管理与卸载隔离测试。
- 卸载专项测试：29 项通过，日志 `build/uninstall-validation/engine-checks.log`，包含真实 macOS 废纸篓回收、恢复清单、运行应用/打开文件、取消、文件变更、越界伪造、应用副本和软链接保护。
- 使用 Codex 原生 macOS 操作接口启动隔离构建，实际打开“应用卸载”页，读到已安装应用列表和受保护提示；检查测试程序包，核对默认只选本体、关联缓存默认不选、勾选后数量和容量更新。
- 实际打开确认窗口，列出应用与缓存的精确路径。点击取消后，两个原路径均仍存在。重新确认后，两项测试内容移入 `~/.Trash/1Tool-Uninstall-<UUID>`，原路径消失，结果页显示已移动项目和恢复位置。
- 按 `1Tool-Uninstall-Recovery.json` 恢复两项测试内容，核对文本内容与原始值一致，随后仅移除本次创建的测试程序包、测试缓存与对应 UUID 恢复目录。现有已安装应用与用户数据未卸载。
- 已关闭独立验证进程，保留原有 `/Applications/1Tool.app` 进程。
- 八种语言的卸载显式文本及 String Catalog 已校验，`git diff --check` 通过。

## 证据位置

`build/uninstall-validation/` 保存构建和测试日志、原生列表/确认/结果截图（`list.jpeg`、`confirmation.jpeg`、`result.jpeg`）、UI 测试程序包标识、恢复清单及源码 SHA-256。独立验证源码与构建位于该目录的 `source/`，用于避开其他对话的共享打包目录写入；最终工作区构建位于 `build/1Tool.app`。

## 验证范围

本次证明本地 ARM64 构建、卸载引擎保护与真实窗口测试程序包的预览/勾选/取消/回收/恢复流程。Intel 原生执行、真实第三方软件卸载、系统受限目录授权、废纸篓不可用故障注入、窗口缩放及所有语言的原生视觉验收未运行。

已按用户指示通知“清理电脑缓存”对话暂停其卸载开发，保留其全局 UI 责任。本功能复用 `ToolSection`、`Theme`、`PrimaryAction` 等公共组件；后续 Figma 全组件盘点、全局可切换 Liquid Glass、减少透明度和增强对比度等全局外观最终验收由主窗口任务统一完成，本记录不将这些项计为 PASS。

## UI-13 至 UI-16 后续修复 · 2026-10-23

- 受保护程序包不再扫描/选中，说明、空复选框、零选择统计和禁用卸载按钮一致。源码为 `UninstallPlan.appItem` 及卸载页条件说明。
- 操作栏已使用公共 `ToolActionBar()`；正文和操作栏共用 `Layout.contentWidth` / `Layout.pagePadding`。在 1360×780pt 独立原生窗口检查卡片与操作栏左右边界一致。
- 搜索无匹配显示查询值和“清除搜索”，点击后恢复4个测试应用；空库存显示未找到应用与刷新入口，扫描受阻库存不会被归为正常空库存。
- 使用真实 POSIX `000` 测试目录触发拒绝读取，页面保留缓存根及实际失败子目录，禁用该缓存选择，显示清单不完整、权限入口、重扫及错误详情。恢复该测试目录 `0700` 后，主动重扫恢复该缓存的可选状态，仍不自动勾选数据或开始卸载。
- 超限独立显示未检查原因与路径；权限、文件变化、软链接保护、其他 I/O 失败采用结构化状态，不把它们都归为完全磁盘访问问题。
- 本轮 `build/uninstall-ui-review/engine-checks.log`：40项通过，包含本轮新增的真实不可读目录/应用库存及原因分类验证。它复测并保留首轮的卸载/恢复保护用例。
- 独立源码快照的全源 Swift typecheck 通过，空诊断日志 `build/uninstall-ui-review/typecheck.log`。对正在并发修改的工作区直接 typecheck 曾因他人文件在编译时变化退出，保留于 `live-typecheck-concurrent.log`；采用稳定快照后通过。
- 新增状态文字已补齐并静态检查八种语言。`git diff --check` 通过。

原生证据在 `build/uninstall-ui-review/screenshots/`：`protected.jpeg`、`wide-aligned.jpeg`、`no-matches.jpeg`、`empty-inventory.jpeg`、`denied-path.jpeg`、`permissions-route.jpeg`、`rescanned.jpeg`、`scan-limit.jpeg`。当前模块源码与共享样式哈希记录在同目录上级 `source-hashes.json`。

边界：此次为独立原生组件验收，使用生产卸载页、真实后端与公共样式/权限按钮，顶部仅为测试场景控件。权限按钮确实触发 `.permissions` 导航；独立宿主用接收页验证导航，没有替代主窗口的真实权限管理页面、系统设置往返或 TCC 授权测试。没有再次执行真实第三方应用卸载。主窗口最终集成、安装包、多主题/窗口尺寸和系统权限往返验收仍由主对话集中完成；原始清单 UI-13 至 UI-16 的最终集成勾选保留待验收状态。

独立宿主进程已关闭，测试目录权限已恢复为0700，未改变用户隐私授权或安装应用。此轮未运行共享构建/安装；首轮233项整包回归记录属于前一版，本轮的新证据是40项专项检查、全源快照typecheck与上述原生交互。

## 未启动应用被误报运行 · 2026-10-23

用户报告 CCBaga Local B 未启动，但卸载时提示先退出。实机只读复现确认 `ai.local.ccbaga.custom.browser` 不在运行的 bundle ID 或程序包路径中，目标程序包内可执行进程为0；系统 NotificationCenter（观测 PID70013）保留其 Chromium Helper Alerts 的 `Resources/base.lproj/InfoPlist.strings` 映射。旧规则因任一已选路径出现在打开文件表就统一报 running，导致误报。

修复将运行进程与文件占用分开。lsof 保留 PID/命令/描述符/访问模式，真实进程可执行路径通过 `proc_pidpath` 核对。已确认的外部只读程序包资源映射不阻止可恢复移动；真实运行进程（含嵌套后台辅助程序）、写入/未知访问和关联数据读取继续阻止。文件占用显示实际路径与持有进程，不伪装为目标应用运行。

- `build/uninstall-running-fix/live-probe.log`：同一份 CCBaga 实时状态中，旧规则 blocked=true，新规则 block=none。该检查没有卸载 CCBaga、没有更改其文件、没有结束通知中心或浏览器进程。
- `build/uninstall-running-fix/engine-checks.log`：48项通过，新增只读资源、真实后台可执行进程、写入/未知访问、数据读取、NUL路径解析等回归检查。
- 使用真实只读文件句柄与真实 lsof 验证：保持该句柄打开，隔离测试程序包仍能移到 macOS 废纸篓；移动后该句柄读取内容与原数据一致。仅使用测试程序包，延续原有恢复清单检查。
- 稳定快照全源 Swift typecheck 通过，日志 `build/uninstall-running-fix/typecheck.log`；生产源码冻结哈希为 `source-hashes.txt`。新增两条文本已补八种语言，`git diff --check` 通过。

新文件占用提示的独立原生宿主已编译，但当前 Sky 原生管道返回“native pipe closed before response”，该额外提示的真实窗口验收记 NOT RUN，不将编译代替界面验证。该宿主已关闭。实机 CCBaga 阻塞判断和真实lsof/废纸篓后端路径已取得上述证据。

主窗口对话要求正式 `/Applications/1Tool.app` 暂不重装，继续统一通用构建与权限验收；本轮未覆盖正式安装。已通知其采用冻结修复源码，因此已安装旧版在最终统一更新前仍可能显示旧提示。
