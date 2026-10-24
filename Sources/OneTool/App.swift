// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Observation
import ServiceManagement

enum ToolPage: String, CaseIterable, Identifiable {
    case awake, finder, keyboard, displays, input, network, cleanup, uninstall, brew, npm, appearance, permissions, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .awake: return L("Keep Awake")
        case .finder: return L("Finder Actions")
        case .keyboard: return L("Keyboard Backlight")
        case .displays: return L("Display Brightness")
        case .input: return L("Input Sources")
        case .network: return L("DNS & Router")
        case .cleanup: return L("Storage Cleanup")
        case .uninstall: return L("App Uninstaller")
        case .brew: return "Homebrew"
        case .npm: return L("npm Packages")
        case .permissions: return L("Permissions")
        case .about: return L("About")
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
        case .network: return "network"
        case .cleanup: return "internaldrive"
        case .uninstall: return "trash"
        case .brew: return "shippingbox"
        case .npm: return "shippingbox.circle"
        case .permissions: return "lock.shield"
        case .about: return "info.circle"
        case .appearance: return "gearshape"
        }
    }
    var iconColor: Color {
        // Opaque artwork colors stay consistent in both appearances; semantic
        // foreground colors become too bright for white symbols in dark mode.
        let rgb: (Double, Double, Double)
        switch self {
        case .awake, .brew: rgb = (230, 126, 0)
        case .finder, .about: rgb = (0, 122, 255)
        case .keyboard, .appearance: rgb = (155, 81, 216)
        case .displays: rgb = (0, 149, 199)
        case .network: rgb = (0, 143, 156)
        case .input: rgb = (88, 86, 214)
        case .cleanup: rgb = (0, 143, 156)
        case .uninstall, .npm: rgb = (240, 64, 72)
        case .permissions: rgb = (40, 167, 69)
        }
        return Color(.sRGB, red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, opacity: 1)
    }
    var subtitle: String {
        switch self {
        case .awake: return L("Keep your Mac awake when you need it.")
        case .finder: return L("Your everyday file actions, right in Finder.")
        case .keyboard: return L("Set a comfortable keyboard backlight level.")
        case .displays: return L("Adjust each display independently.")
        case .input: return L("Use your preferred input source in each app.")
        case .network: return L("Switch DNS and router together using your saved addresses.")
        case .cleanup: return L("Find what can go. Keep what matters.")
        case .uninstall: return L("Remove apps and review the files they leave behind.")
        case .brew: return L("Install, uninstall and upgrade Homebrew tools and apps.")
        case .npm: return L("Install, uninstall and upgrade global npm packages.")
        case .permissions: return L("Review access and system capabilities in one place.")
        case .about: return L("A little more control over your Mac.")
        case .appearance: return L("Personalize appearance, language, and startup.")
        }
    }
}

@MainActor @Observable final class AppModel {
    static let shared = AppModel()
    var page: ToolPage = .awake
    let awake = KeepAwake()
    let finder = RightClick()
    let keyboard = KeyboardLight()
    let displays = Displays()
    let input = InputSources()
    let cleanup = Cleanup()
    let permissions = PermissionsCenter()
    let systemTheme = SystemTheme()
    let network = NetworkSettings()
    let uninstaller = AppUninstaller()
    let brew = PackageManager(.brew)
    let npm = PackageManager(.npm)
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
        finder.refreshStatus(); keyboard.refresh(); input.refresh(); awake.checkExpiry(); permissions.refresh(); systemTheme.refresh(); network.refresh()
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
    @AppStorage("appearance.accent") private var accent = "blue"
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"

    var body: some Scene {
        Window("1Tool", id: "main") {
            AppRoot(model: model)
                .id(language)
                .environment(\.locale, Locale(identifier: AppLanguage.resolve(language)))
                .environment(\.toolAccent, AppAccent.resolve(accent).readableColor)
                .tint(AppAccent.resolve(accent).color)
                .modifier(ToolAppearance())
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        }
        .defaultSize(width: 920, height: 760)
        .windowResizability(.contentMinSize)
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
    var symbol: String? = nil
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button {
            AppModel.shared.dismissQuickPanel?()
            if let open = AppModel.shared.openMainWindow { open(page) }
            else { AppModel.shared.page = page; openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        } label: {
            if let symbol { Image(systemName: symbol).frame(width: 28, height: 28) }
            else { Text(title) }
        }.help(title).accessibilityLabel(title)
    }
}

struct AppRoot: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        MainView(model: model).onAppear {
            model.finder.openPermissions = { model.openMainWindow?(.permissions) }
            model.openMainWindow = { page in
                model.page = page
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
