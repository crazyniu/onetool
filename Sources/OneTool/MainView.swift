// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import ServiceManagement

struct MainView: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var model: AppModel
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                BrandLogo(size: 48)
                    .frame(maxWidth: .infinity).padding(.top, 18).padding(.bottom, 4)
                VStack(spacing: 4) {
                    ForEach(ToolPage.allCases.filter { $0 != .appearance }) { page in nav(page) }
                }
                Spacer()
                if model.awake.isActive {
                    Label(L("Keeping Awake"), systemImage: "circle.fill")
                        .font(.system(size: 12)).foregroundStyle(accent).padding(.horizontal, 14)
                }
                VStack(alignment: .leading, spacing: 14) {
                    nav(.appearance)
                }.padding(.bottom, 20)
            }
            .padding(.horizontal, 10).frame(width: 208)
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
            HStack(spacing: 10) {
                Image(systemName: page.symbol).symbolRenderingMode(.monochrome)
                    .font(.system(size: 16, weight: .regular)).frame(width: 22, height: 22)
                    .foregroundStyle(model.page == page ? accent : Color.secondary)
                Text(page.title).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 9)
            .foregroundStyle(model.page == page ? accent : Color.primary)
            .background(model.page == page ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
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
    private let durations: [(String, Double)] = [(L("30 min"), 30), (L("1 hr"), 60), (L("2 hr"), 120), (L("4 hr"), 240), (L("8 hr"), 480), (L("Indefinitely"), 0)]
    var body: some View {
        ToolSection(title: "") {
            HStack(spacing: 16) {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 32)).foregroundStyle(awake.isActive ? accent : .secondary)
                VStack(alignment: .leading, spacing: 5) {
                    Text(awake.isActive ? L("Your Mac is staying awake") : L("Ready when you are")).font(.system(size: 16, weight: .semibold))
                    if let end = awake.endDate {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let seconds = max(0, Int(end.timeIntervalSince(context.date)))
                            Text(String(format: L("Time remaining %02d:%02d"), seconds / 60, seconds % 60)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    } else { HelpText(awake.isActive ? (awake.automatic ? L("Started by a power rule") : L("Until you stop the session or quit")) : L("Normal sleep resumes when the timer ends")) }
                }
                Spacer(minLength: 8)
                Button(awake.isActive ? L("Stop") : L("Start")) {
                    if awake.isActive { awake.stop() } else { awake.start(minutes: duration == 0 ? nil : duration) }
                }.modifier(PrimaryAction()).controlSize(.large)
            }
            Divider()
            Picker(L("Duration"), selection: Binding(get: {
                awake.isActive ? (awake.durationMinutes ?? 0) : duration
            }, set: { duration = $0 })) {
                ForEach(durations, id: \.1) { item in
                    if item.1 == 0 { Image(systemName: "infinity").accessibilityLabel(L("Keep Awake Indefinitely")).tag(item.1) }
                    else { Text(item.0).tag(item.1) }
                }
            }.pickerStyle(.segmented).labelsHidden().disabled(awake.isActive)
            ErrorText(error: awake.error)
        }
        ToolSection(title: L("Sleep Prevention")) {
            SettingToggle(title: L("Prevent Idle System Sleep"), value: $awake.preventSystem)
            Divider()
            SettingToggle(title: L("Keep Display On"), value: $awake.preventDisplay)
            Divider()
            SettingToggle(title: L("Prevent Idle Disk Sleep"), value: $awake.preventDisk)
            Divider()
            SettingToggle(title: L("Prevent System Sleep"), subtitle: L("Available when connected to power"), value: $awake.preventForcedSleep)
        }
        ToolSection(title: L("Start Automatically")) {
            SettingToggle(title: L("On Power Adapter"), value: $awake.onAC)
            Divider()
            SettingToggle(title: L("On Battery"), value: $awake.onBattery)
            HelpText(L("Rules run when the power source changes. After a manual stop, they wait for the next change. macOS still manages lid closure, shutdown, and forced sleep."))
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
        ToolSection(title: L("Built-in Keyboard")) {
            HStack(spacing: 16) {
                Image(systemName: "keyboard").font(.system(size: 28)).foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(keyboard.supported ? L("Backlight Brightness") : L("No adjustable keyboard backlight detected")).fontWeight(.medium)
                    HelpText(keyboard.supported ? L("Drag the slider to adjust immediately") : L("Requires a Mac with a built-in backlit keyboard."))
                }
            }.padding(.vertical, 4)
            if keyboard.supported {
                LevelSlider(title: L("Keyboard Backlight"), value: Binding(get: { keyboard.level }, set: { keyboard.set($0) }))
                HStack {
                    ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { value in
                        Button(value == 0 ? L("Off") : "\(Int(value * 100))%") { keyboard.set(value) }
                    }
                    Spacer()
                }
                if keyboard.autoSupported {
                    SettingToggle(title: L("Adjust to Ambient Light"), value: Binding(get: { keyboard.automatic }, set: { keyboard.setAutomatic($0) }))
                }
                HelpText(L("Manual changes turn off automatic adjustment. You can turn it back on anytime."))
            }
            HStack {
                Button(L("Detect Again"), systemImage: "arrow.clockwise") { keyboard.refresh() }
                Spacer()
                Button(L("Keyboard Settings…")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
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
            Text(L("Connected Displays")).foregroundStyle(.secondary)
            Text(displays.screens.count, format: .number).monospacedDigit().foregroundStyle(.secondary)
            Spacer()
            if displays.scanning { ProgressView().controlSize(.small) }
            Button(L("Refresh"), systemImage: "arrow.clockwise") { displays.refresh() }.disabled(displays.scanning)
        }
        ForEach(displays.screens) { screen in
            ToolSection(title: "") {
                HStack(spacing: 12) {
                    Image(systemName: screen.builtIn ? "laptopcomputer" : "display").font(.system(size: 28)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(screen.title).fontWeight(.semibold)
                        HelpText(LF(screen.builtIn ? "Built-in · %@" : "External · %@", screen.method.title))
                    }
                    Spacer()
                    if screen.id == CGMainDisplayID() { Text(L("Main Display")).font(.caption).foregroundStyle(.secondary) }
                }
                LevelSlider(title: LF("%@ Brightness", screen.title), value: Binding(get: {
                    displays.screens.first(where: { $0.id == screen.id })?.level ?? screen.level
                }, set: { displays.set(screen.id, level: $0) }), disabled: displays.scanning || screen.method == .unavailable)
                if screen.method == .software {
                    HelpText(L("Software dimming changes the image, not the backlight. It restores on quit and keeps at least 12% brightness."))
                } else if !screen.readable && screen.method == .ddc {
                    HelpText(L("The display accepts DDC commands but does not report brightness. The percentage shows the requested level. If nothing changes, try software dimming."))
                }
                Toggle(L("Use Software Dimming"), isOn: Binding(get: { displays.softwarePreferred(screen.key) }, set: {
                    displays.preferSoftware(screen.key, enabled: $0)
                })).toggleStyle(.checkbox).disabled(displays.scanning)
                ErrorText(error: screen.error)
            }
        }
        if displays.screens.isEmpty && !displays.scanning {
            ContentUnavailableView(L("No Displays Detected"), systemImage: "display", description: Text(L("Connect a display, then click Refresh.")))
        }
        Button(L("Reset Software Dimming"), systemImage: "sun.max") { displays.restoreAllSoftware() }.disabled(displays.scanning)
        HelpText(L("Enable DDC/CI on external displays. Some docks, HDMI adapters, and virtual displays only support software dimming."))
    }
}

struct InputPage: View {
    @Bindable var input: InputSources
    var body: some View {
        ToolSection(title: "") {
            SettingToggle(title: L("Enable Input Source Rules"), subtitle: L("Apply on app switch; you can still change the input source manually"), value: $input.enabled)
            Divider()
            HStack {
                Text(L("Current Input Source")); Spacer(); Text(input.currentName).foregroundStyle(.secondary)
            }
            HStack {
                Text(L("Default Input Source")); Spacer()
                sourcePicker(L("Default Input Source"), value: $input.fallback)
            }
            SettingToggle(title: L("Turn Off Caps Lock on Switch"), value: $input.clearCapsLock)
        }
        ToolSection(title: L("Per-App Rules")) {
            if input.rules.isEmpty { HelpText(L("Choose an input source for each app. Per-app rules override the default.")) }
            ForEach($input.rules) { $rule in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: rule.path)).resizable().frame(width: 24, height: 24)
                    Text(rule.name).lineLimit(1)
                    Spacer(minLength: 8)
                    sourcePicker(LF("%@ Input Source", rule.name), value: $rule.sourceID)
                    Button { [id = rule.id] in input.rules.removeAll { $0.id == id } } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless).help(LF("Remove %@", rule.name)).accessibilityLabel(LF("Remove %@", rule.name))
                }
                if rule.id != input.rules.last?.id { Divider() }
            }
            Button(L("Add App…"), systemImage: "plus") { input.addApplication() }
        }
        HStack {
            Button(L("Refresh Input Sources"), systemImage: "arrow.clockwise") { input.refresh() }
            Spacer()
            Button(L("Input Source Settings…")) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!) }
        }
        HelpText(L("Follow System keeps the current input source. If a source becomes unavailable, choose another one."))
        ErrorText(error: input.error)
    }
    private func sourcePicker(_ title: String, value: Binding<String>) -> some View {
        Picker(title, selection: value) {
            Text(L("Follow System")).tag("")
            if !value.wrappedValue.isEmpty && !input.sources.contains(where: { $0.id == value.wrappedValue }) {
                Text(L("Input Source Unavailable")).tag(value.wrappedValue)
            }
            ForEach(input.sources, id: \.id) { source in Text(source.name).tag(source.id) }
        }.labelsHidden().frame(width: 180).accessibilityLabel(title)
    }
}

struct AppearancePage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var model: AppModel
    @AppStorage("appearance.icon") private var icon = ""
    var body: some View {
        LanguageControls()
        AppearanceControls()
        ToolSection(title: L("Menu Bar Icon")) {
            HStack {
                Text(L("Icon")).fontWeight(.medium)
                Spacer()
                Image(nsImage: BrandGlyph.mark() ?? NSImage()).renderingMode(.template).frame(width: 40, height: 28)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), alignment: .leading, spacing: 8) {
                ForEach(StatusIconSelection.gallery, id: \.self) { name in
                    iconCell(name: name, title: name.isEmpty ? L("Default Icon") : name)
                }
            }
            HelpText(L("Icons are sized for the menu bar. Green means Keep Awake is on."))
        }
        ToolSection(title: L("Startup")) {
            SettingToggle(title: L("Launch at Login"), value: Binding(get: { model.loginStatus == .enabled || model.loginStatus == .requiresApproval }, set: { model.setLogin($0) }))
            if model.loginStatus == .requiresApproval {
                HStack { HelpText(L("Allow launch at login in System Settings.")); Button(L("Open Settings")) { SMAppService.openSystemSettingsLoginItems() } }
            }
            ErrorText(error: model.loginError)
            HelpText(L("Closing the window keeps the app in the menu bar. Quitting ends keep-awake sessions and resets software dimming."))
        }
        HStack {
            Spacer()
            Button(L("Open Source Licenses")) {
                if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
            }
            Button(L("Quit 1Tool")) { NSApp.terminate(nil) }
        }.font(.callout)
    }
    private func iconCell(name: String, title: String) -> some View {
        Button { icon = name } label: {
            VStack(spacing: 7) {
                Image(nsImage: BrandGlyph.mark(symbolName: name) ?? NSImage())
                    .renderingMode(.template).frame(height: 25)
            }.frame(maxWidth: .infinity).frame(height: 44)
                .foregroundStyle(icon == name ? accent : .primary)
                .background(icon == name ? accent.opacity(0.12) : Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) {
                    if icon == name { Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(accent).padding(4) }
                }
        }.buttonStyle(.plain).help(title).accessibilityLabel(title).accessibilityAddTraits(icon == name ? .isSelected : [])

    }

}
