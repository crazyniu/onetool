// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import Darwin

enum SystemThemeMode: String, CaseIterable, Identifiable {
    case light, dark, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .light: return L("Light")
        case .dark: return L("Dark")
        case .automatic: return L("Automatic")
        }
    }
}

struct SystemThemeState: Equatable {
    let mode: SystemThemeMode
    let isDark: Bool
}

@MainActor protocol SystemThemeAccess {
    var canChange: Bool { get }
    func read() -> SystemThemeState
    func write(_ mode: SystemThemeMode)
    func persistedMode() -> SystemThemeMode
}

/// SkyLight owns the system's automatic schedule. Resolve its optional entry points
/// at runtime so a future macOS can fall back to System Settings without crashing.
/// No Apple Events, Accessibility permission or private preference writes are used.
@MainActor final class MacSystemThemeAccess: SystemThemeAccess {
    private typealias GetFlag = @convention(c) () -> UInt64
    private typealias SetDark = @convention(c) (UInt8) -> Void
    private typealias SetAutomatic = @convention(c) (UInt32) -> Void
    private let library: UnsafeMutableRawPointer?
    private let getDark: GetFlag?
    private let getAutomatic: GetFlag?
    private let setDark: SetDark?
    private let setAutomatic: SetAutomatic?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
        library = handle
        func symbol<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let address = dlsym(handle, name) else { return nil }
            return unsafeBitCast(address, to: type)
        }
        getDark = symbol("SLSGetAppearanceThemeLegacy", as: GetFlag.self)
        getAutomatic = symbol("SLSGetAppearanceThemeSwitchesAutomatically", as: GetFlag.self)
        setDark = symbol("SLSSetAppearanceThemeLegacy", as: SetDark.self)
        setAutomatic = symbol("SLSSetAppearanceThemeSwitchesAutomatically", as: SetAutomatic.self)
    }
    deinit { if let library { dlclose(library) } }
    var canChange: Bool { getDark != nil && getAutomatic != nil && setDark != nil && setAutomatic != nil }
    func read() -> SystemThemeState {
        guard let getDark, let getAutomatic else { return preferences() }
        let dark = getDark() != 0
        return SystemThemeState(mode: getAutomatic() != 0 ? .automatic : dark ? .dark : .light, isDark: dark)
    }
    func write(_ mode: SystemThemeMode) {
        guard canChange else { return }
        setAutomatic?(mode == .automatic ? 1 : 0)
        if mode != .automatic { setDark?(mode == .dark ? 1 : 0) }
    }
    func persistedMode() -> SystemThemeMode { preferences().mode }
    private func preferences() -> SystemThemeState {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        func value(_ key: String) -> Any? {
            CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        }
        let dark = value("AppleInterfaceStyle") as? String == "Dark"
        let automatic = (value("AppleInterfaceStyleSwitchesAutomatically") as? NSNumber)?.boolValue == true
        return SystemThemeState(mode: automatic ? .automatic : dark ? .dark : .light, isDark: dark)
    }
}

@MainActor @Observable final class SystemTheme {
    private(set) var state: SystemThemeState
    private(set) var isChanging = false
    private(set) var error: String?
    var canChange: Bool { access.canChange }
    @ObservationIgnored private let access: any SystemThemeAccess
    @ObservationIgnored private var monitor: Timer?
    @ObservationIgnored private var changeObserver: NSObjectProtocol?
    @ObservationIgnored private var activeObserver: NSObjectProtocol?

    init(access: (any SystemThemeAccess)? = nil, monitorChanges: Bool = true) {
        let access = access ?? MacSystemThemeAccess()
        self.access = access
        state = access.read()
        guard monitorChanges else { return }
        changeObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
        // Auto can change policy without changing the rendered colors, so its
        // notification alone is insufficient while both settings windows are open.
        monitor = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        monitor?.tolerance = 0.5
    }
    deinit {
        monitor?.invalidate()
        if let changeObserver { DistributedNotificationCenter.default().removeObserver(changeObserver) }
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
    }
    func refresh() { state = access.read() }

    func set(_ mode: SystemThemeMode) async {
        guard !isChanging else { return }
        error = nil
        guard canChange else {
            refresh()
            error = L("System appearance cannot be changed on this macOS version. Use System Settings.")
            return
        }
        let previous = access.read()
        isChanging = true
        defer { refresh(); isChanging = false }
        access.write(mode)
        if await verify(mode) { return }
        // The setter has no error result. Verify both live state and preferences,
        // then restore the previous policy if macOS did not accept the change.
        access.write(previous.mode)
        let restored = await verify(previous.mode)
        error = L(restored
            ? "macOS did not confirm the appearance change. The previous mode was restored."
            : "macOS did not confirm the appearance change. Check the current mode in System Settings.")
    }
    private func verify(_ mode: SystemThemeMode) async -> Bool {
        for attempt in 0..<6 {
            refresh()
            if state.mode == mode && access.persistedMode() == mode { return true }
            if attempt < 5 { try? await Task.sleep(for: .milliseconds(100)) }
        }
        return false
    }
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
