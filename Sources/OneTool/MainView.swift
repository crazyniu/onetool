// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import ServiceManagement

struct MainView: View {
    @Environment(\.toolAccent) private var accent
    @Environment(\.toolGlassEnabled) private var glass
    @Environment(\.controlActiveState) private var activeState
    @Bindable var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                BrandLogo(size: 48).frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
                List {
                    Section(L("Everyday Tools")) {
                        ForEach([ToolPage.awake, .finder, .keyboard, .displays, .input]) { nav($0) }
                    }
                    Section(L("Storage & Apps")) {
                        ForEach([ToolPage.cleanup, .uninstall, .brew, .npm]) { nav($0) }
                    }
                    Section(L("Settings")) {
                        ForEach([ToolPage.appearance, .permissions, .about]) { nav($0) }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                    .onMoveCommand { direction in
                        let pages = ToolPage.allCases
                        guard let current = pages.firstIndex(of: model.page) else { return }
                        if direction == .down { model.page = pages[min(current + 1, pages.count - 1)] }
                        if direction == .up { model.page = pages[max(current - 1, 0)] }
                    }
            }
            .background { if !glass { Theme.sidebar } }
            .navigationSplitViewColumnWidth(min: 190, ideal: Layout.sidebarWidth, max: 280)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                    Text(model.page.subtitle).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.bottom, 4)
                    Group {
                        switch model.page {
                        case .awake: AwakePage(awake: model.awake)
                        case .finder: FinderPage(service: model.finder)
                        case .keyboard: KeyboardPage(keyboard: model.keyboard)
                        case .displays: DisplaysPage(displays: model.displays)
                        case .input: InputPage(input: model.input)
                        case .cleanup: CleanupPage(cleanup: model.cleanup)
                        case .uninstall: UninstallPage(uninstaller: model.uninstaller)
                        case .brew: PackageManagementPage(manager: model.brew).id(PackageProvider.brew)
                        case .npm: PackageManagementPage(manager: model.npm).id(PackageProvider.npm)
                        case .appearance: AppearancePage(model: model)
                        case .permissions: PermissionsPage(model: model)
                        case .about: AboutPage()
                        }
                    }
                }.padding(Layout.pagePadding).frame(maxWidth: Layout.contentWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .id(model.page)
            .background(Theme.canvas)
            .navigationTitle(model.page.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { model.page = .appearance } label: { Image(systemName: "gearshape") }
                        .help(L("Open Settings")).accessibilityLabel(L("Open Settings"))
                }
            }
            .modifier(ToolToolbarAppearance())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if model.page == .cleanup && model.cleanup.scan != nil { CleanupActions(cleanup: model.cleanup) }
                if model.page == .uninstall && model.uninstaller.plan != nil { UninstallActions(uninstaller: model.uninstaller) }
                if model.page == .brew && model.brew.hasStatus { PackageOperationStatus(manager: model.brew).modifier(ToolActionBar()) }
                if model.page == .npm && model.npm.hasStatus { PackageOperationStatus(manager: model.npm).modifier(ToolActionBar()) }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 880, minHeight: 660)
    }
    private func nav(_ page: ToolPage) -> some View {
        SidebarNavigationRow(page: page, selected: model.page == page) { model.page = page }
            .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
            .selectionDisabled()
    }
}

private struct SidebarNavigationRow: View {
    let page: ToolPage
    let selected: Bool
    let action: () -> Void
    @AppStorage("appearance.accent") private var accentName = "blue"
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: page.symbol)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(page.iconColor, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .accessibilityHidden(true)
                Text(page.title).font(.body).foregroundStyle(selected ? Color.white : Color.primary).lineLimit(1)
                Spacer(minLength: 0)
            }.padding(.horizontal, 8).padding(.vertical, 4)
                .background(selected ? AppAccent.resolve(accentName).selectionColor : hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).help(page.title).onHover { hovering = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct AwakePage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var awake: KeepAwake
    var body: some View {
        ToolSection(title: "") {
            HStack(spacing: 16) {
                Image(systemName: awake.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .font(.system(size: 24)).foregroundStyle(awake.isActive ? accent : .secondary)
                    .frame(width: 48, height: 48).background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
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
                    if awake.isActive { awake.stop() } else { awake.startPreferredSession() }
                }.modifier(PrimaryAction()).controlSize(.large)
            }
            Divider()
            AwakeDurationPicker(awake: awake)
            ErrorText(error: awake.error)
        }
        ToolSection(title: "") {
            SettingToggle(title: L("Keep Display On"), value: $awake.preventDisplay)
        }
        ToolSection(title: "") {
            DisclosureGroup(L("Start Automatically")) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingToggle(title: L("On Power Adapter"), value: $awake.onAC)
                    Divider()
                    SettingToggle(title: L("On Battery"), value: $awake.onBattery)
                    HelpText(L("Rules run when the power source changes. After a manual stop, they wait for the next change. macOS still manages lid closure, shutdown, and forced sleep."))
                }.padding(.top, 8)
            }
            Divider()
            DisclosureGroup(L("Advanced Sleep Options")) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingToggle(title: L("Prevent Idle System Sleep"), subtitle: L("Prevent automatic sleep when your Mac is idle."), value: $awake.preventSystem)
                    Divider()
                    SettingToggle(title: L("Prevent Idle Disk Sleep"), value: $awake.preventDisk)
                    Divider()
                    SettingToggle(title: L("Prevent System Sleep"), subtitle: L("Available when connected to power"), value: $awake.preventForcedSleep)
                    HelpText(L("macOS still controls lid closure, shutdown, and forced sleep."))
                }.padding(.top, 8)
            }
        }
    }
}

struct AwakeDurationPicker: View {
    @Bindable var awake: KeepAwake
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L("Duration"))
                Spacer(minLength: 8)
                ChoiceMenu(title: L("Duration"), value: awake.selectedDuration == 0 ? L("Indefinitely") : awake.selectedDuration < 60 ? LF("%d min", Int(awake.selectedDuration)) : LF("%d hr", Int(awake.selectedDuration / 60)), width: 150) {
                    ForEach(KeepAwake.durations, id: \.self) { minutes in
                        Button { awake.changeDuration(minutes) } label: {
                            Label(minutes == 0 ? L("Indefinitely") : minutes < 60 ? LF("%d min", Int(minutes)) : LF("%d hr", Int(minutes / 60)), systemImage: awake.selectedDuration == minutes ? "checkmark" : "")
                        }
                    }
                }
            }
            if awake.isActive { HelpText(L("Changing the duration restarts the timer.")) }
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
                        HelpText(screen.builtIn ? screen.method.title : LF("External · %@", screen.method.title))
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
                if screen.method == .software {
                    HStack {
                        Text(L("Software Dimming")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Try Hardware Control")) { displays.preferSoftware(screen.key, enabled: false) }
                            .controlSize(.small).disabled(displays.scanning)
                    }
                }
                ErrorText(error: screen.error)
            }
        }
        if displays.screens.isEmpty && !displays.scanning {
            ContentUnavailableView(L("No Displays Detected"), systemImage: "display", description: Text(L("Connect a display, then click Refresh.")))
        }
        if displays.screens.contains(where: { $0.method == .software }) {
            Button(L("Reset Software Dimming"), systemImage: "sun.max") { displays.restoreAllSoftware() }.disabled(displays.scanning)
        }
    }
}

struct InputPage: View {
    @Bindable var input: InputSources
    var body: some View {
        ToolSection(title: "") {
            SettingToggle(title: L("Enable Input Source Rules"), subtitle: L("Apply on app switch; you can still change the input source manually"), value: $input.enabled)
            Divider()
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
                    HStack(spacing: 8) {
                        sourcePicker(LF("%@ Input Source", rule.name), value: $rule.sourceID)
                        Button { [id = rule.id] in input.rules.removeAll { $0.id == id } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help(LF("Remove %@", rule.name)).accessibilityLabel(LF("Remove %@", rule.name))
                    }.fixedSize(horizontal: true, vertical: false)
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
        ChoiceMenu(title: title, value: value.wrappedValue.isEmpty ? L("Follow System") : input.sources.first(where: { $0.id == value.wrappedValue })?.name ?? L("Input Source Unavailable"), width: 180) {
            Button(L("Follow System")) { value.wrappedValue = "" }
            Divider()
            ForEach(input.sources, id: \.id) { source in
                Button { value.wrappedValue = source.id } label: {
                    Label(source.name, systemImage: value.wrappedValue == source.id ? "checkmark" : "")
                }
            }
        }
    }
}

struct AppearancePage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var model: AppModel
    @AppStorage("appearance.icon") private var icon = ""
    var body: some View {
        LanguageControls()
        AppearanceControls(systemTheme: model.systemTheme)
        ToolSection(title: L("Menu Bar Icon")) {
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
