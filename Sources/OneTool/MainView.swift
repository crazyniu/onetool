// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import ServiceManagement

struct MainView: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                Image(nsImage: BrandGlyph.applicationIcon).resizable().scaledToFit()
                    .frame(width: 40, height: 40).accessibilityLabel("1Tool")
                    .padding(.horizontal, 12).padding(.top, 14)
                VStack(spacing: 5) {
                    ForEach(ToolPage.allCases.filter { $0 != .appearance }) { page in nav(page) }
                }
                Spacer()
                if model.awake.isActive {
                    Label("正在保持唤醒", systemImage: "circle.fill")
                        .font(.system(size: 12)).foregroundStyle(accent).padding(.horizontal, 14)
                }
                VStack(alignment: .leading, spacing: 14) {
                    nav(.appearance)
                }.padding(.bottom, 20)
            }
            .padding(.horizontal, 12).frame(width: 200)
            .background(Theme.canvas)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.page.title).font(.system(size: 24, weight: .semibold))
                        Text(model.page.subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.bottom, 2)
                    switch model.page {
                    case .awake: AwakePage(awake: model.awake)
                    case .finder: FinderPage(service: model.finder)
                    case .keyboard: KeyboardPage(keyboard: model.keyboard)
                    case .displays: DisplaysPage(displays: model.displays)
                    case .input: InputPage(input: model.input)
                    case .appearance: AppearancePage(model: model)
                    }
                }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
            }.background(Theme.canvas)
        }
        .frame(minWidth: 840, minHeight: 620)
    }
    private func nav(_ page: ToolPage) -> some View {
        Button { model.page = page } label: {
            HStack(spacing: 11) {
                Image(systemName: page.symbol).font(.system(size: 17)).frame(width: 23)
                Text(page.title).fontWeight(model.page == page ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .foregroundStyle(Color.primary)
            .background(model.page == page ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(model.page == page ? .isSelected : [])
    }
}

struct ToolSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !title.isEmpty { Text(title).font(.system(size: 13, weight: .semibold)).padding(.horizontal, 14) }
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}
struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
struct ErrorText: View {
    let error: String?
    var body: some View {
        if let error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
    }
}
struct SettingToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Bool
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if let subtitle { HelpText(subtitle) }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
        }
    }
}

struct AwakePage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var awake: KeepAwake
    @State private var duration = 60.0
    private let durations: [(String, Double)] = [("30 分钟", 30), ("1 小时", 60), ("2 小时", 120), ("4 小时", 240), ("8 小时", 480), ("无限", 0)]
    var body: some View {
        ToolSection(title: "") {
            HStack(spacing: 16) {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 32)).foregroundStyle(awake.isActive ? accent : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(awake.isActive ? "Mac 正在保持唤醒" : "按需唤醒，自在工作").font(.system(size: 16, weight: .semibold))
                    if let end = awake.endDate {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(end.timeIntervalSince(context.date)))
                            Text(String(format: "剩余 %02d:%02d", seconds / 60, seconds % 60)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    } else { HelpText(awake.isActive ? (awake.automatic ? "由电源规则自动开启" : "保持到你手动结束或退出 1Tool") : "计时结束后自动恢复正常休眠") }
                }
                Spacer(minLength: 8)
                Button(awake.isActive ? "结束" : "开始") {
                    if awake.isActive { awake.stop() } else { awake.start(minutes: duration == 0 ? nil : duration) }
                }.modifier(PrimaryAction()).controlSize(.large)
            }
            Divider()
            Picker("持续时间", selection: Binding(get: {
                awake.isActive ? (awake.durationMinutes ?? 0) : duration
            }, set: { duration = $0 })) {
                ForEach(durations, id: \.1) { item in
                    if item.1 == 0 { Image(systemName: "infinity").accessibilityLabel("无限防休眠").tag(item.1) }
                    else { Text(item.0).tag(item.1) }
                }
            }.pickerStyle(.segmented).labelsHidden().disabled(awake.isActive)
            ErrorText(error: awake.error)
        }
        ToolSection(title: "保持哪些状态") {
            SettingToggle(title: "防止系统空闲休眠", value: $awake.preventSystem)
            Divider()
            SettingToggle(title: "保持屏幕常亮", value: $awake.preventDisplay)
            Divider()
            SettingToggle(title: "防止磁盘空闲休眠", value: $awake.preventDisk)
            Divider()
            SettingToggle(title: "防止系统休眠", subtitle: "仅在连接电源时生效", value: $awake.preventForcedSleep)
        }
        ToolSection(title: "自动开启") {
            SettingToggle(title: "连接电源时", value: $awake.onAC)
            Divider()
            SettingToggle(title: "使用电池时", value: $awake.onBattery)
            HelpText("电源状态变化时应用规则。手动结束后，会等待下一次电源变化。合盖、关机和系统强制睡眠仍由 macOS 管理。")
        }
    }
}

struct LevelSlider: View {
    let title: String
    @Binding var value: Double
    var disabled = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sun.min").foregroundStyle(.secondary)
            Slider(value: $value, in: 0...1).accessibilityLabel(title)
            Image(systemName: "sun.max").foregroundStyle(.secondary)
            Text("\(Int((value * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary).frame(width: 42, alignment: .trailing)
        }.disabled(disabled)
    }
}

struct KeyboardPage: View {
    @Environment(\.toolAccent) private var accent
    let keyboard: KeyboardLight
    var body: some View {
        ToolSection(title: "内置键盘") {
            HStack(spacing: 16) {
                Image(systemName: "keyboard").font(.system(size: 28)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(keyboard.supported ? "键盘背光亮度" : "未检测到可调节的键盘背光").fontWeight(.medium)
                    HelpText(keyboard.supported ? "拖动滑块立即调节" : "此功能需要支持背光的 Mac 内置键盘。")
                }
            }.padding(.vertical, 4)
            if keyboard.supported {
                LevelSlider(title: "键盘背光", value: Binding(get: { keyboard.level }, set: { keyboard.set($0) }))
                HStack {
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                        Button(value == 0 ? "关闭" : "\(Int(value * 100))%") { keyboard.set(value) }
                    }
                    Spacer()
                }
                if keyboard.autoSupported {
                    SettingToggle(title: "根据环境光自动调节", value: Binding(get: { keyboard.automatic }, set: { keyboard.setAutomatic($0) }))
                }
                HelpText("手动调节会关闭环境光自动调节，可随时重新开启。")
            }
            HStack {
                Button("重新检测", systemImage: "arrow.clockwise") { keyboard.refresh() }
                Spacer()
                Button("键盘设置…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
            }
            ErrorText(error: keyboard.error)
        }.onAppear { keyboard.refresh() }
    }
}

struct DisplaysPage: View {
    @Environment(\.toolAccent) private var accent
    let displays: Displays
    var body: some View {
        HStack {
            Text("\(displays.screens.count) 块屏幕").foregroundStyle(.secondary)
            Spacer()
            if displays.scanning { ProgressView().controlSize(.small) }
            Button("刷新", systemImage: "arrow.clockwise") { displays.refresh() }.disabled(displays.scanning)
        }
        ForEach(displays.screens) { screen in
            ToolSection(title: "") {
                HStack(spacing: 12) {
                    Image(systemName: screen.builtIn ? "laptopcomputer" : "display").font(.system(size: 28)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(screen.name).fontWeight(.semibold)
                        HelpText((screen.builtIn ? "内置显示器 · " : "外接显示器 · ") + screen.method.rawValue)
                    }
                    Spacer()
                    if screen.id == CGMainDisplayID() { Text("主屏幕").font(.caption).foregroundStyle(.secondary) }
                }
                LevelSlider(title: screen.name + "亮度", value: Binding(get: {
                    displays.screens.first(where: { $0.id == screen.id })?.level ?? screen.level
                }, set: { displays.set(screen.id, level: $0) }), disabled: displays.scanning || screen.method == .unavailable)
                if screen.method == .software {
                    HelpText("软件调暗改变画面亮度，不改变背光。退出时自动恢复；最低保留 12% 画面亮度。")
                } else if !screen.readable && screen.method == .ddc {
                    HelpText("显示器接受 DDC 写入，但未返回亮度。百分比表示本次设置值，请观察屏幕确认；无变化时可改用软件调暗。")
                }
                Toggle("使用软件调暗", isOn: Binding(get: { displays.softwarePreferred(screen.key) }, set: {
                    displays.preferSoftware(screen.key, enabled: $0)
                })).toggleStyle(.checkbox).disabled(displays.scanning)
                ErrorText(error: screen.error)
            }
        }
        if displays.screens.isEmpty && !displays.scanning {
            ContentUnavailableView("没有检测到屏幕", systemImage: "display", description: Text("连接显示器后点按刷新。"))
        }
        Button("恢复软件调暗的屏幕", systemImage: "sun.max") { displays.restoreAllSoftware() }.disabled(displays.scanning)
        HelpText("外接显示器需开启 DDC/CI。部分扩展坞、HDMI 转接器或虚拟屏幕可能只支持软件调暗。")
    }
}

struct InputPage: View {
    @Bindable var input: InputSources
    var body: some View {
        ToolSection(title: "") {
            SettingToggle(title: "启用默认输入法", subtitle: "切换应用时应用规则，随后仍可手动切换", value: $input.enabled)
            Divider()
            HStack {
                Text("当前输入法"); Spacer(); Text(input.currentName).foregroundStyle(.secondary)
            }
            HStack {
                Text("全局默认"); Spacer()
                sourcePicker("全局默认输入法", value: $input.fallback)
            }
            SettingToggle(title: "切换时关闭大写锁定", value: $input.clearCapsLock)
        }
        ToolSection(title: "应用专属规则") {
            if input.rules.isEmpty { HelpText("为终端选择 ABC，为聊天软件选择中文输入法。应用专属规则优先于全局默认。") }
            ForEach($input.rules) { $rule in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: rule.path)).resizable().frame(width: 24, height: 24)
                    Text(rule.name).lineLimit(1)
                    Spacer(minLength: 8)
                    sourcePicker(rule.name + "输入法", value: $rule.sourceID)
                    Button { input.rules.removeAll { $0.id == rule.id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help("移除 " + rule.name).accessibilityLabel("移除 " + rule.name)
                }
                if rule.id != input.rules.last?.id { Divider() }
            }
            Button("添加应用…", systemImage: "plus") { input.addApplication() }
        }
        HStack {
            Button("刷新输入法", systemImage: "arrow.clockwise") { input.refresh() }
            Spacer()
            Button("输入法设置…") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
        }
        HelpText("“跟随系统”会保留当前输入法。选择停用或移除的输入法时，1Tool 会提示你重新选择。")
        ErrorText(error: input.error)
    }
    private func sourcePicker(_ title: String, value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            Text("跟随系统").tag("")
            if !value.wrappedValue.isEmpty && !input.sources.contains(where: { $0.id == value.wrappedValue }) {
                Text("输入法不可用").tag(value.wrappedValue)
            }
            ForEach(input.sources, id: \.id) { source in Text(source.name).tag(source.id) }
        }.labelsHidden().frame(width: 180).accessibilityLabel(title)
    }
}

struct AppearancePage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var model: AppModel
    @AppStorage("appearance.icon") private var icon = ""
    @State private var editingIconName = false
    @AppStorage("appearance.activeDot") private var activeDot = true
    var body: some View {
        AppearanceControls()
        ToolSection(title: "状态栏图标") {
            HStack {
                Text("图标").fontWeight(.medium)
                Spacer()
                Image(nsImage: BrandGlyph.mark() ?? NSImage()).renderingMode(.template).frame(width: 40, height: 28)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 48), spacing: 8)], alignment: .leading, spacing: 8) {
                iconCell(name: "", title: "默认 Logo")
                ForEach(StatusIconSelection.gallery.filter { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }, id: \.self) { name in
                    iconCell(name: name, title: name)
                }
            }
            Button("其他图标…") { editingIconName = true }.font(.callout)
            HelpText("默认使用 1Tool 扳手 Logo。可选择图库图标，或输入其他符号名称；留空恢复默认。")
            Divider()
            SettingToggle(title: "防休眠开启时显示状态圆点", value: $activeDot)
        }
        .popover(isPresented: $editingIconName) { IconNameEditor() }
        ToolSection(title: "启动与运行") {
            SettingToggle(title: "登录时启动 1Tool", value: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval }, set: { model.setLogin($0) }))
            if model.loginStatus == .requiresApproval {
                HStack { HelpText("请在系统设置中允许 1Tool 登录启动。"); Button("打开设置") { SMAppService.openSystemSettingsLoginItems() } }
            }
            ErrorText(error: model.loginError)
            HelpText("关闭窗口后，1Tool 会继续在状态栏运行。退出应用会结束防休眠并恢复软件调暗。")
        }
        HStack {
            Spacer()
            Button("开源许可") {
                if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
            }
            Button("退出 1Tool") { NSApp.terminate(nil) }
        }.font(.callout)
    }
    private func iconCell(name: String, title: String) -> some View {
        Button { icon = name } label: {
            VStack(spacing: 7) {
                Image(nsImage: BrandGlyph.mark(symbolName: name) ?? NSImage())
                    .renderingMode(.template).frame(height: 25)
            }.frame(maxWidth: .infinity).frame(height: 42)
                .foregroundStyle(icon == name ? accent : .primary)
                .background(icon == name ? accent.opacity(0.12) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if icon == name { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent).padding(4) }
                }
        }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(icon == name ? .isSelected : [])

    }

}

private struct IconNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance.icon") private var savedName = ""
    @State private var draft = ""
    @State private var openingName = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("其他图标").font(.headline)
            TextField("图标名称，例如 bolt.fill", text: $draft).textFieldStyle(.roundedBorder)
                .onSubmit { dismiss() }
            HelpText("留空恢复默认 Logo；无效名称会恢复打开前的选择。")
            HStack { Spacer(); Button("完成") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 300)
            .onAppear { openingName = savedName; draft = savedName }
            .onChange(of: draft) {
                savedName = StatusIconSelection.toSave(typed: draft, opening: openingName) {
                    NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
                }
            }
    }
}
