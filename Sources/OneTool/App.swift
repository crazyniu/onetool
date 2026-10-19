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
    @ObservationIgnored var openMainWindow: ((ToolPage) -> Void)?
    @ObservationIgnored var dismissQuickPanel: (() -> Void)?

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

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusBarController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        status = StatusBarController(model: AppModel.shared)
    }
    @objc func showQuickPanel() {
        DispatchQueue.main.async { [weak self] in self?.status?.togglePanel() }
    }
    @objc func showStatusMenu() {
        // Finish tracking the application menu before opening a second native menu.
        DispatchQueue.main.async { [weak self] in self?.status?.showMenu() }
    }
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
    @AppStorage("appearance.scheme") private var scheme = "system"
    @AppStorage("appearance.accent") private var accent = "blue"

    var body: some Scene {
        Window("1Tool", id: "main") {
            AppRoot(model: model)
                .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
                .environment(\.toolAccent, AppAccent.resolve(accent).color)
                .tint(AppAccent.resolve(accent).color)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        }
        .defaultSize(width: 940, height: 710)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenMainButton(title: "1Tool 设置…", page: .appearance).keyboardShortcut(",") }
            CommandGroup(after: .appSettings) {
                Button("打开快捷面板") { delegate.showQuickPanel() }
                Button("显示状态栏菜单") { delegate.showStatusMenu() }
            }
        }

    }
}

struct OpenMainButton: View {
    let title: String
    let page: ToolPage
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(title) {
            AppModel.shared.dismissQuickPanel?()
            if let open = AppModel.shared.openMainWindow { open(page) }
            else { AppModel.shared.page = page; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        }
    }
}

struct AppRoot: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MainView(model: model).background(WindowTitleHider()).onAppear {
            model.openMainWindow = { page in
                model.page = page
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
