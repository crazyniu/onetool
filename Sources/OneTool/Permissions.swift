// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Carbon
import ServiceManagement

/// Queries only on refresh. A request happens solely after the user presses Allow.
@MainActor @Observable final class PermissionsCenter {
    struct AutomationTarget: Identifiable {
        let id: String
        let name: String
        let state: AutomationState
    }
    enum AutomationState {
        case allowed, notRequested, denied, notRunning, notInstalled, unknown(OSStatus)
        var title: String {
            switch self {
            case .allowed: return L("Allowed")
            case .notRequested: return L("Not Requested")
            case .denied: return L("Not Allowed")
            case .notRunning: return L("Open the app to check")
            case .notInstalled: return L("Not Installed")
            case .unknown: return L("Could Not Determine")
            }
        }
    }
    private(set) var automation: [AutomationTarget] = []
    private(set) var checkedAt: Date?
    private(set) var opening: Set<String> = []
    private(set) var error: String?
    func refresh() {
        automation = [("com.apple.finder", "Finder"), ("com.apple.Terminal", "Terminal"), ("com.googlecode.iterm2", "iTerm2")].map { id, name in
            let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
            return .init(id: id, name: name, state: !installed ? .notInstalled : !running ? .notRunning : query(id, request: false))
        }
        checkedAt = .now
    }
    func request(_ id: String) { error = nil; _ = query(id, request: true); refresh() }
    func openAndCheck(_ target: AutomationTarget) {
        guard !opening.contains(target.id) else { return }
        error = nil
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target.id) else {
            error = LF("Could not open %@. The application is unavailable.", target.name)
            refresh()
            return
        }
        opening.insert(target.id)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, failure in
            Task { @MainActor in
                self.opening.remove(target.id)
                if let failure { self.error = LF("Could not open %@: %@", target.name, failure.localizedDescription) }
                self.refresh()
            }
        }
    }
    private func query(_ id: String, request: Bool) -> AutomationState {
        var descriptor = AEAddressDesc()
        let status = id.withCString { AECreateDesc(typeApplicationBundleID, $0, id.utf8.count, &descriptor) }
        guard status == noErr else { return .unknown(OSStatus(status)) }
        defer { AEDisposeDesc(&descriptor) }
        switch AEDeterminePermissionToAutomateTarget(&descriptor, typeWildCard, typeWildCard, request) {
        case OSStatus(noErr): return .allowed
        case OSStatus(errAEEventWouldRequireUserConsent): return .notRequested
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(procNotFound): return .notRunning
        case let value: return .unknown(value)
        }
    }
    static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }
}

struct PermissionsPage: View {
    @Bindable var model: AppModel
    var body: some View {
        HStack {
            HelpText(L("Access is checked without showing permission prompts. Choose an action when you need it."))
            Spacer()
            Button(L("Refresh"), systemImage: "arrow.clockwise") { model.refresh() }
        }
        ToolSection(title: L("Automation")) {
            HelpText(L("Finder actions may control Finder, Terminal or iTerm2. Permission is separate for each app."))
            ForEach(model.permissions.automation) { target in
                HStack(spacing: 12) {
                    Text(target.name)
                    Spacer()
                    Text(target.state.title).foregroundStyle(.secondary).font(.callout)
                    if case .notRequested = target.state {
                        Button(L("Allow…")) { model.permissions.request(target.id) }
                    } else if case .notRunning = target.state {
                        Button(L("Open and Check")) { model.permissions.openAndCheck(target) }
                            .disabled(model.permissions.opening.contains(target.id))
                    } else if case .notInstalled = target.state {
                        EmptyView()
                    } else {
                        Button(L("System Settings…")) { PermissionsCenter.openSettings("Privacy_Automation") }
                    }
                }
                if case .unknown(let code) = target.state { HelpText(LF("System response: %d", code)) }
                if target.id != model.permissions.automation.last?.id { Divider() }
            }
        }
        ErrorText(error: model.permissions.error)
        ToolSection(title: L("Files & Folders")) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Full Disk Access")).fontWeight(.medium)
                    HelpText(L("Manage in System Settings. macOS does not provide a reliable app-wide status query."))
                }
                Spacer()
                Button(L("System Settings…")) { PermissionsCenter.openSettings("Privacy_AllFiles") }
            }
            HelpText(L("Cleanup and uninstall show paths that could not be read. Access may be limited by privacy settings, ownership or file permissions. Grant only the access you need, then scan again."))
            Divider()
            HStack {
                Text(L("Files & Folders"))
                Spacer()
                Button(L("System Settings…")) { PermissionsCenter.openSettings("Privacy_FilesAndFolders") }
            }
        }
        ToolSection(title: L("System Integration")) {
            HStack {
                Text(L("System Appearance")); Spacer()
                Text(L(model.systemTheme.canChange ? "Available" : "Unavailable")).foregroundStyle(.secondary)
                Button(L("System Settings…")) { SystemTheme.openSettings() }
            }
            HelpText(L("System appearance uses a local system interface and does not request Automation or Accessibility. Unavailable controls open System Settings."))
            Divider()
            HStack {
                Text(L("Finder Extension")); Spacer()
                Text(L(model.finder.extensionEnabled ? "Enabled" : "Not Enabled")).foregroundStyle(.secondary)
                Button(L("Manage Extension…")) { model.finder.openExtensionSettings() }
            }
            Divider()
            HStack {
                Text(L("Launch at Login")); Spacer()
                Text(loginStatus).foregroundStyle(.secondary)
                Button(L("System Settings…")) { SMAppService.openSystemSettingsLoginItems() }
            }
        }
        ToolSection(title: L("Hardware & Command-Line Tools")) {
            HelpText(L("Brightness and keep-awake use system hardware APIs. Unsupported hardware is not a missing privacy permission."))
            HelpText(L("Input-source switching does not request Accessibility or Input Monitoring. Caps Lock errors report the failed hardware operation separately."))
            Divider()
            HelpText(L("Homebrew and npm may need writable package directories or an interactive administrator prompt. Follow the package page guidance; Full Disk Access does not replace these requirements."))
            HStack {
                Button("Homebrew") { model.page = .brew }
                Button("npm") { model.page = .npm }
            }
        }
        HelpText(L("Returning from System Settings refreshes these states. Changes never start cleanup, uninstall or package operations automatically."))
            .onAppear { model.refresh() }
    }
    private var loginStatus: String {
        switch model.loginStatus {
        case .enabled: return L("Enabled")
        case .requiresApproval: return L("Awaiting System Approval")
        case .notRegistered: return L("Not Enabled")
        case .notFound: return L("Unavailable")
        @unknown default: return L("Could Not Determine")
        }
    }
}
