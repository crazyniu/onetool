// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Observation
import ServiceManagement

enum ToolPage: String, CaseIterable, Identifiable {
    case awake, finder, keyboard, displays, input, appearance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .awake: return "防止休眠"
        case .finder: return "超级右键"
        case .keyboard: return "键盘背光"
        case .displays: return "屏幕亮度"
        case .input: return "默认输入法"
        case .appearance: return "外观与启动"
        }
    }
    var symbol: String {
        switch self {
        case .awake: return "cup.and.saucer"
        case .finder: return "cursorarrow.click.2"
        case .keyboard: return "light.max"
        case .displays: return "display.2"
        case .input: return "character.cursor.ibeam"
        case .appearance: return "slider.horizontal.3"
        }
    }
    var subtitle: String {
        switch self {
        case .awake: return "让 Mac 在需要的时候保持清醒。"
        case .finder: return "把常用文件操作放进 Finder 右键菜单。"
        case .keyboard: return "找到适合当前环境的键盘背光。"
        case .displays: return "分别调节每一块屏幕，保持舒适的工作亮度。"
        case .input: return "切换应用时，自动使用你习惯的输入法。"
        case .appearance: return "让 1Tool 以你喜欢的方式待在状态栏。"
        }
    }
}

struct StatusIcon: Identifiable {
    let id: String
    let name: String
    static let all: [Self] = [
        .init(id: "switch.2", name: "开关"), .init(id: "1.circle", name: "一"),
        .init(id: "cup.and.saucer", name: "咖啡"), .init(id: "bolt", name: "闪电"),
        .init(id: "sun.max", name: "太阳"), .init(id: "moon", name: "月亮"),
        .init(id: "leaf", name: "叶子"), .init(id: "sparkle", name: "星光"),
        .init(id: "command", name: "Command"), .init(id: "keyboard", name: "键盘"),
        .init(id: "display", name: "屏幕"), .init(id: "circle.hexagongrid", name: "蜂巢")
    ]
}

@Observable final class AppModel {
    static let shared = AppModel()
    var page: ToolPage = .awake
    let awake = KeepAwake()
    let finder = RightClick()
    let keyboard = KeyboardLight()
    let displays = Displays()
    let input = InputSources()
    var loginStatus = SMAppService.mainApp.status
    var loginError: String?

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch { loginError = error.localizedDescription }
        loginStatus = SMAppService.mainApp.status
    }
    func refresh() {
        finder.refreshStatus(); keyboard.refresh(); input.refresh(); awake.checkExpiry()
        loginStatus = SMAppService.mainApp.status
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.finder.stop()
        AppModel.shared.awake.stop()
        AppModel.shared.displays.stop()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if let window = sender.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "1Tool" }) {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@main struct OneToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared
    @AppStorage("appearance.icon") private var icon = "switch.2"
    @AppStorage("appearance.scheme") private var scheme = "system"
    @AppStorage("appearance.activeDot") private var activeDot = true

    var body: some Scene {
        Window("1Tool", id: "main") {
            MainView(model: model)
                .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
                .tint(Theme.accent)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        }
        .defaultSize(width: 940, height: 710)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenMainButton(title: "1Tool 设置…", page: .appearance).keyboardShortcut(",") }
        }
        MenuBarExtra {
            QuickPanel(model: model).tint(Theme.accent)
                .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: StatusIcon.all.contains(where: { $0.id == icon }) ? icon : "switch.2")
                if model.awake.isActive && activeDot { Image(systemName: "circle.fill").font(.system(size: 5)) }
            }
            .accessibilityLabel(model.awake.isActive ? "1Tool，防休眠已开启" : "1Tool")
        }
        .menuBarExtraStyle(.window)
    }
}

struct OpenMainButton: View {
    let title: String
    let page: ToolPage
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(title) {
            AppModel.shared.page = page
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
