// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Observation
import ServiceManagement

enum ToolPage: String, CaseIterable, Identifiable {
    case awake, finder, keyboard, displays, input, appearance
    var id: String { rawValue }
    var title: String {
        switch self {
        case .awake: return L("Keep Awake")
        case .finder: return L("Finder Actions")
        case .keyboard: return L("Keyboard Backlight")
        case .displays: return L("Display Brightness")
        case .input: return L("Input Sources")
        case .appearance: return L("General")
        }
    }
    var symbol: String {
        switch self {
        case .awake: return "cup.and.saucer"
        case .finder: return "cursorarrow.click.2"
        case .keyboard: return "keyboard"
        case .displays: return "display"
        case .input: return "globe"
        case .appearance: return "gearshape"
        }
    }
    var subtitle: String {
        switch self {
        case .awake: return L("Keep your Mac awake when you need it.")
        case .finder: return L("Your everyday file actions, right in Finder.")
        case .keyboard: return L("Set a comfortable keyboard backlight level.")
        case .displays: return L("Adjust each display independently.")
        case .input: return L("Use your preferred input source in each app.")
        case .appearance: return L("Personalize appearance, language, and startup.")
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
        NSApp.applicationIconImage = BrandGlyph.applicationIcon
        NSApp.setActivationPolicy(.accessory)
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
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"

    var body: some Scene {
        Window("1Tool", id: "main") {
            AppRoot(model: model)
                .id(language)
                .environment(\.locale, Locale(identifier: AppLanguage.resolve(language)))
                .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
                .environment(\.toolAccent, AppAccent.resolve(accent).color)
                .tint(AppAccent.resolve(accent).color)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        }
        .defaultSize(width: 940, height: 710)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenMainButton(title: L("Settings…"), page: .appearance).keyboardShortcut(",") }
            CommandGroup(after: .appSettings) {
                Button(L("Show Quick Panel")) { delegate.showQuickPanel() }
                Button(L("Show Status Menu")) { delegate.showStatusMenu() }
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
