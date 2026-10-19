# 超级右键迁移范围

上游项目：https://github.com/vorssaint/vorssaint-utils，参考基准提交 `79165ad78566d0ea5f036fb38aed10e6ba08e595`。

| 原文件 | 新文件 | 适配 |
| --- | --- | --- |
| Sources/FinderExtension/FinderSync.swift | Sources/FinderExtension/FinderSync.swift | 仅 Objective-C 主类名称改为 OneToolFinderSync；比对一致 |
| Services/Finder/SuperRightClickSupport.swift | Sources/Shared/SuperRightClickSupport.swift | IPC 命名空间独立；中文默认值 |
| Services/Finder/SuperRightClickTemplates.swift | Sources/OneTool/SuperRightClickTemplates.swift | 原样移植，比对一致 |
| Services/Finder/SuperRightClickService.swift | Sources/OneTool/RightClick.swift | 原有配置发布、菜单动作校验、软件检测与禁用、路径复制、目录打开、文件创建、Terminal/iTerm AppleScript、其他软件目录打开完整保留；适配 Observation、独立设置和生命周期 |
| Services/QuickTools/QuickTogglesService.swift | RightClick.toggleHiddenFiles / restartFinder | 只移植隐藏文件路径：同一 Finder 偏好、已有授权时正常退出重开、killall 兜底 |
| Services/ShellSupport.swift | FinderAppleScript | 原进程内 AppleScript 执行和授权检测 |
| Resources/FileTemplates/Blank.docx / Blank.xlsx | Resources/FileTemplates/ | 二进制比对一致 |

文件写入放到后台队列，使系统文件授权期间设置窗口仍可响应；名称校验、O_EXCL 防覆盖和符号链接保护保留。新应用不依赖原应用的功能注册器、菜单栏、设置页或其他工具。

菜单保持原来四组、原顺序规则、彩色图标、模板与软件子菜单，以及 Finder 项目/容器的原作用域逻辑。设置页维持 1Tool 新界面，并保留原有可配置能力。
