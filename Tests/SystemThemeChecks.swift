// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@MainActor private final class ThemeFixture: SystemThemeAccess {
    var canChange = true
    var state = SystemThemeState(mode: .light, isDark: false)
    var saved: SystemThemeMode = .light
    var writes: [SystemThemeMode] = []
    var ignoresDark = false
    var ignoresPersistence = false
    func read() -> SystemThemeState { state }
    func persistedMode() -> SystemThemeMode { saved }
    func write(_ mode: SystemThemeMode) {
        writes.append(mode)
        guard !(ignoresDark && mode == .dark) else { return }
        state = .init(mode: mode, isDark: mode == .automatic ? state.isDark : mode == .dark)
        if !ignoresPersistence { saved = mode }
    }
}

@main struct SystemThemeChecks {
    @MainActor static func main() async {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); count += 1; print("PASS: " + message)
        }
        let access = ThemeFixture()
        let theme = SystemTheme(access: access, monitorChanges: false)
        check(theme.state.mode == .light && access.writes.isEmpty, "startup reads the system without applying old app preferences")
        await theme.set(.dark)
        check(theme.state == .init(mode: .dark, isDark: true) && theme.error == nil && !theme.isChanging, "dark selection reflects verified live and persisted system state")
        await theme.set(.automatic)
        check(theme.state.mode == .automatic && theme.state.isDark && access.saved == .automatic, "automatic remains selected when the rendered appearance is dark")
        access.state = .init(mode: .automatic, isDark: false)
        theme.refresh()
        check(theme.state.mode == .automatic && !theme.state.isDark, "scheduled light transition preserves the automatic policy")
        access.state = .init(mode: .light, isDark: false); access.saved = .light
        let writeCount = access.writes.count
        theme.refresh()
        check(theme.state.mode == .light && access.writes.count == writeCount, "external settings changes refresh without writing back")
        access.canChange = false
        await theme.set(.dark)
        check(theme.error != nil && theme.state.mode == .light && access.writes.count == writeCount, "unavailable interface reports failure and never simulates success")
        access.canChange = true; access.ignoresDark = true
        await theme.set(.dark)
        check(theme.error != nil && theme.state.mode == .light && access.writes.suffix(2) == [.dark, .light], "rejected changes restore the prior policy and report failure")
        access.ignoresDark = false; access.ignoresPersistence = true
        await theme.set(.dark)
        check(theme.error != nil && theme.state.mode == .light && access.saved == .light, "live-only changes fail persisted-state verification and restore")
        access.ignoresPersistence = false
        await theme.set(.dark)
        check(theme.error == nil && theme.state.mode == .dark, "a successful explicit retry clears the error")
        access.ignoresPersistence = true
        let changing = Task { await theme.set(.light) }
        await Task.yield()
        while !theme.isChanging { await Task.yield() }
        let before = access.writes.count
        await theme.set(.automatic)
        check(access.writes.count == before, "overlapping requests cannot interleave system writes")
        await changing.value
        check(!theme.isChanging && theme.state.mode == .dark, "failed transition releases busy state after restoring the original mode")
        print("PASS: \(count) system appearance checks")
    }
}
