# 权限生命周期验收 · 2026-10-23

## 本轮范围与身份

用户要求继续验收权限申请、拒绝、撤销和重新授权，并把问题直接发送给开发对话修复。本轮执行原生系统设置与正式安装应用的状态核对，另建立独立身份检查首次请求。没有执行清理、卸载、包安装或终端命令。

- 正式应用：`/Applications/1Tool.app`，Bundle ID `com.shopkivoo.onetool`，开发签名团队 `WT475Q2P69`。测试时二进制 SHA-256 为 `fd3cf9f29405528fce504f38b9d6988b856a0eb2671b46c35dac5980768f3704`；之后重建安装需要复核受影响项。
- 隔离身份：`org.onetool.permissions-review.20261023`。使用未经修改的生产 `Permissions.swift`；宿主为独立 AppKit 测试窗口，其他功能服务为最小测试宿主，不把其权限当作正式应用权限。
- 源码快照、宿主和记录位于 `build/permission-validation/`，身份与哈希记录见 `session-result.json`、`source/manifest.json`。

## 实测结果

| 流程 | 结论 | 实际证据与边界 |
| --- | --- | --- |
| 正式安装版授权基线 | PASS | 原生系统设置中 1Tool 的终端、访达、iTerm 开关均为 on；权限页三项目标均显示已允许。 |
| 撤销终端授权 | PASS | 仅关闭 1Tool → 终端，系统设置返回 off；权限页点击刷新后显示 Terminal 未允许，其余两项仍已允许。 |
| 拒绝/撤销后的设置入口 | PASS（导航） | 未允许行的系统设置按钮正确打开“自动化”；该页可找到 1Tool → 终端开关。 |
| 重新授权 | PASS（原有授权恢复与手动刷新） | 用户明确确认恢复原权限后，将该开关恢复 on；权限页手动刷新回到已允许。未自动执行终端命令或其他操作。 |
| 隔离身份首次只读查询 | PASS（实际系统 API） | 原样生产 PermissionsCenter.refresh() 返回 Finder/Terminal/iTerm2 均 Not Requested；记录 `isolated-first-read.txt`。 |
| 隔离身份首次申请 | PARTIAL | 显式测试调用原样 request(Terminal) 后返回 Allowed，`isolated-first-request-result.txt`；系统设置新增独立测试应用，终端开关 on。工具未取得弹窗和点击过程证据，不声称已验收按钮/弹窗交互全过程。 |
| 首次弹窗选择拒绝 | NOT RUN | 测试窗口的原生连接持续报 `Sky Computer Use native pipe closed before response`；不能用已有拒绝状态代替“第一次点拒绝”的交互验证。 |
| 返回前台自动刷新 | NOT RUN | AX 点击与 Raise 没有可靠建立真实前台切换；坐标输入返回 `noWindowsAvailable`。本轮只确认手动刷新，不据此报告自动刷新失败或成功。 |
| 完全磁盘访问、文件与文件夹 | PARTIAL | 页面提供独立入口并明确无法可靠查询全局 FDA 状态。未新增此类广泛授权，也未把普通文件权限夹具当作 TCC 授权验证。首次拒绝、授予、撤销后的实际受保护路径访问仍待验收。 |
| Finder 扩展与登录项 | 状态读取通过，生命周期 NOT RUN | 正式应用显示已启用，本轮未停用扩展或登录项；它们属于独立系统集成状态，不并入 Apple Events 授权结论。 |
| Homebrew/npm 权限错误恢复 | 28 项自动化夹具通过 | 本轮重编译并运行现有 PackageStateChecks，覆盖目录权限/管理员交互/仓库认证错误分类与用户确认后重试；没有在真实 CLI 中变更权限或安装包。 |

主要证据：`installed-automation-baseline.png`、`installed-after-revoke-refresh.png/.txt`、`installed-reauthorized.png/.txt`。系统设置截图读取后来出现不可用，后续判断优先使用当次明确返回的 AX 开关状态；不得把失败截图文件作为有效视觉证据。

## 已发给“清理电脑缓存”修复

- [ ] **PERM-01 / P2：目标未运行时缺少直接恢复动作。** `Permissions.swift` 的 `.notRunning` 文案为“打开应用后检查”，操作却仍是“系统设置”。首次未请求时，用户应能主动打开对应目标应用并重新检测；查询不能自动变成授权请求，启动失败应明确反馈。
- [ ] **PERM-02 / P1：实际 Finder 动作被拒绝时缺少权限恢复入口。** `RightClick.openApplication` 执行 Terminal/iTerm AppleScript 后只传递 `result.message` 到普通 `NSAlert`，虽然底层保留 `errorNumber`，调用方没有识别 -1743。应显示具体目标和操作未完成原因，提供“查看权限”动作；区分自动化拒绝与 FDA/辅助功能权限，并保留原始错误详情。重新授权后必须由用户重新执行，不能自动重放命令。这是源码确认的问题，当前未把实际终端动作执行标为原生 PASS。

以上两项已经发送主对话，修复后需补相应验证，不能仅以代码提交关闭待办。

### 修复后的源码复核

主对话随后已实现两项修复，本对话只读确认：`openAndCheck` 只在用户点击时启动指定目标，完成后调用只读 `refresh`，启动错误可见；`automationFailureTarget` 仅把 Terminal/iTerm2 的 -1743 识别为自动化拒绝，弹窗给出“查看权限”与“取消”，回调打开本应用权限页，不执行原命令。新增三项错误分类检查已进入测试源码，执行结果由主对话统一构建记录。本轮正式安装版尚未包含这两项修复，所以保持 TODO，等待最终安装版原生验证。

## 结束状态与剩余验收

正式版的终端权限已恢复到测试前的 on；访达与 iTerm 授权、完全磁盘访问、Finder 扩展和登录项未被本轮修改。独立测试身份已通过系统命令 `tccutil reset AppleEvents org.onetool.permissions-review.20261023` 撤销测试授权并退出，仅重置这一个测试身份，没有重置正式应用或其他应用。

主对话亦只读复现了测试宿主连接故障，确认坐标/前台键盘路径不稳定。首次弹窗拒绝、真正前台切回，以及 FDA/文件访问的完整授权生命周期保持待验收；避免为工具故障反复重置正式用户权限。最终安装版须承接这份清单，按证据补验。

参考：[Apple 自动化权限设置](https://support.apple.com/en-hk/guide/mac-help/mchl108e1718/mac)、[Apple 授权查询接口](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)。
