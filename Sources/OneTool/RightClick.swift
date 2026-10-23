// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Observation
import Carbon.HIToolbox
import FinderSync

@Observable final class RightClick: NSObject {
    var configuration: SuperRightClickConfiguration
    private(set) var error: String?
    private(set) var detectedApplications: [SuperRightClickEntry] = []
    @ObservationIgnored private let token = UUID().uuidString
    @ObservationIgnored private let workQueue = DispatchQueue(label: "com.shopkivoo.onetool.super-right-click.actions")
    @ObservationIgnored private var busy = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var lastPublished: SuperRightClickConfiguration?

    @ObservationIgnored var openPermissions: (() -> Void)?
    private(set) var extensionEnabled = false
    @ObservationIgnored private let fileQueue = DispatchQueue(label: "com.shopkivoo.onetool.finder-files", qos: .userInitiated)

    override init() {
        configuration = SuperRightClickIPC.decode(
            SuperRightClickConfiguration.self,
            from: UserDefaults.standard.string(forKey: "finder.configuration"))
            ?? .initial(home: FileManager.default.homeDirectoryForCurrentUser)
        super.init()
        start()
        refreshStatus()
    }
    var availableApplications: [SuperRightClickEntry] {
        SuperRightClickApplications.available(custom: configuration.applications,
                                              detected: detectedApplications) {
            FileManager.default.fileExists(atPath: $0)
                && Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier != nil
        }
    }
    private var activeApplications: [SuperRightClickEntry] {
        availableApplications.filter { !configuration.disabledApplications.contains($0.id) }
    }
    func refreshApplications() {
        let installed = SuperRightClickApplications.supportedBundleIDs.compactMap { id -> SuperRightClickEntry? in
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
                  Bundle(url: url)?.bundleIdentifier == id else { return nil }
            return SuperRightClickEntry(id: "detected:" + id,
                                       name: FileManager.default.displayName(atPath: url.path), value: url.path)
        }
        if installed != detectedApplications { detectedApplications = installed }
        syncWithPreferences()
    }

    func start() {
        guard !started else { return }
        started = true
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(requestConfiguration(_:)), name: SuperRightClickIPC.request, object: nil)
        center.addObserver(self, selector: #selector(receiveAction(_:)), name: SuperRightClickIPC.action, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(preferencesChanged(_:)),
                                               name: UserDefaults.didChangeNotification, object: nil)
        refreshApplications()
    }
    func stop() {
        guard started else { return }
        var disabled = configuration
        disabled.enabled = false
        publish(disabled)
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        started = false
    }
    func save() {
        if let raw = SuperRightClickIPC.encode(configuration) {
            guard raw.utf8.count <= 256 * 1024 else {
                error = L("Template content is too large. Shorten it to save.")
                return
            }
            UserDefaults.standard.set(raw, forKey: "finder.configuration")
            error = nil
        }
        syncWithPreferences()
    }
    func syncWithPreferences(force: Bool = false) {
        guard started else { start(); return }
        var value = configuration
        value.enabled = configuration.enabled
        value.language = AppLanguage.current
        value.token = token
        value.applications = activeApplications
        publish(value, force: force)
    }
    private func publish(_ value: SuperRightClickConfiguration, force: Bool = false) {
        guard force || value != lastPublished else { return }
        guard let raw = SuperRightClickIPC.encode(value) else { return }
        lastPublished = value
        DistributedNotificationCenter.default().postNotificationName(
            SuperRightClickIPC.configuration, object: raw, userInfo: nil, deliverImmediately: true)
    }
    @objc private func requestConfiguration(_ notification: Notification) {
        refreshApplications()
        syncWithPreferences(force: true)
    }
    @objc private func preferencesChanged(_ notification: Notification) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.preferencesChanged(notification) }
            return
        }
        if let saved = SuperRightClickIPC.decode(SuperRightClickConfiguration.self,
               from: UserDefaults.standard.string(forKey: "finder.configuration")),
           saved != configuration {
            configuration = saved
        }
        syncWithPreferences()
    }

    @objc private func receiveAction(_ notification: Notification) {
        guard let request = SuperRightClickIPC.decode(SuperRightClickRequest.self, from: notification.object),
              request.token == token, configuration.enabled,
              request.selection.count <= 1000,
              request.selection.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }),
              let directory = SuperRightClickFiles.insertionDirectory(target: request.directory,
                                                                       selection: request.selection) else { return }
        let config = configuration
        let group: SuperRightClickGroup
        switch request.action {
        case "newFile": group = .newFile
        case "directory": group = .directories
        case "copyPath": group = .copyPath
        case "application", "hiddenFiles": group = .openWith
        default: return
        }
        guard config.visibleGroups.contains(group) else { return }
        switch request.action {
        case "copyPath":
            let paths = request.selection.isEmpty ? [directory.path] : request.selection
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        case "newFile":
            guard !busy else { return }
            let template = config.templates.first { $0.id == request.entryID }
            guard request.entryID == nil || template != nil else { return }
            createFile(in: directory, template: template)
        case "directory":
            guard let entry = config.directories.first(where: { $0.id == request.entryID }),
                  let folder = SuperRightClickFiles.directory(entry.value) else {
                fail(L("The favorite folder is missing or inaccessible.")); return
            }
            if !NSWorkspace.shared.open(folder) { fail(L("Could not open the folder.")) }
        case "application":
            guard let entry = activeApplications.first(where: { $0.id == request.entryID }) else { return }
            openApplication(entry, directory: directory)
        case "hiddenFiles":
            guard config.showHiddenToggle else { return }
            toggleHiddenFiles()
        default: break
        }
    }

    private func createFile(in directory: URL, template: SuperRightClickEntry?) {
        busy = true
        let alert = NSAlert()
        alert.messageText = L("New File")
        alert.informativeText = directory.path
        let field = NSTextField(string: SuperRightClickFiles.suggestedName(template.map { "Untitled." + $0.value } ?? "Untitled.txt", in: directory))
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: L("Create"))
        alert.addButton(withTitle: L("Cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { busy = false; return }
        let name = field.stringValue
        fileQueue.async { [self] in
        do {
            let url = try SuperRightClickFiles.create(name: name, in: directory,
                                                     content: try SuperRightClickTemplates.data(
                                                        for: template,
                                                        resourceDirectory: Bundle.main.resourceURL?
                                                            .appendingPathComponent("FileTemplates")))
            DispatchQueue.main.async { self.busy = false; NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } catch { DispatchQueue.main.async { self.busy = false; self.fail((error as? POSIXError)?.code == .EEXIST ? L("A file with this name already exists. Choose another name.") : error.localizedDescription) } }
        }
    }

    private func openApplication(_ entry: SuperRightClickEntry, directory: URL) {
        let app = URL(fileURLWithPath: entry.value)
        guard app.pathExtension == "app", let bundle = Bundle(url: app) else {
            fail(L("The app is missing. Choose it again.")); return
        }
        let id = bundle.bundleIdentifier
        if id == "com.apple.Terminal" || id == "com.googlecode.iterm2" {
            // Shell quoting and AppleScript quoting are separate trust boundaries.
            let command = "cd -- " + Self.shellQuote(directory.path)
            let literal = "\"" + command.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r") + "\""
            let source: String
            if id == "com.apple.Terminal" {
                source = "tell application id \"com.apple.Terminal\"\nactivate\ndo script \(literal)\nend tell"
            } else {
                source = """
                tell application id "com.googlecode.iterm2"
                    activate
                    set newWindow to (create window with default profile)
                    tell current session of newWindow to write text \(literal)
                end tell
                """
            }
            workQueue.async {
                let result = FinderAppleScript.runDetailed(source)
                if !result.ok {
                    DispatchQueue.main.async {
                        if let target = Self.automationFailureTarget(errorNumber: result.errorNumber, bundleID: id) {
                            self.showAutomationDenied(target)
                        } else { self.fail(result.message) }
                    }
                }
            }
        } else {
            NSWorkspace.shared.open([directory], withApplicationAt: app,
                                    configuration: NSWorkspace.OpenConfiguration()) { _, error in
                if let error { DispatchQueue.main.async { self.fail(error.localizedDescription) } }
            }
        }
    }
    static func automationFailureTarget(errorNumber: Int?, bundleID: String?) -> String? {
        guard errorNumber == Int(errAEEventNotPermitted) else { return nil }
        switch bundleID {
        case "com.apple.Terminal": return "Terminal"
        case "com.googlecode.iterm2": return "iTerm2"
        default: return nil
        }
    }
    private func showAutomationDenied(_ target: String) {
        let alert = NSAlert()
        alert.messageText = L("Automation Permission Required")
        alert.informativeText = LF("1Tool is not allowed to control %@. The terminal command was not sent. Open Permissions, enable Automation for this app, then retry the Finder action yourself.", target)
        alert.addButton(withTitle: L("View Permissions"))
        alert.addButton(withTitle: L("Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let openPermissions { openPermissions() }
            else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    private func fail(_ message: String) {
        // Action failures belong to their modal, not a persistent settings-page error.
        let alert = NSAlert()
        alert.messageText = L("Finder Actions")
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    func refreshStatus() { extensionEnabled = FIFinderSyncController.isExtensionEnabled }
    func openExtensionSettings() { FIFinderSyncController.showExtensionManagementInterface() }
    func addFolder() { choosePath(application: false) }
    func addApplication() { choosePath(application: true) }
    private func choosePath(application: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = application; panel.canChooseDirectories = !application
        panel.allowsMultipleSelection = true
        if application { panel.allowedContentTypes = [.applicationBundle] }
        panel.message = application ? L("Choose apps for Finder actions") : L("Choose favorite folders")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let entry = SuperRightClickEntry(name: FileManager.default.displayName(atPath: url.path), value: url.path)
            if application {
                if configuration.applications.count < 32, !configuration.applications.contains(where: { $0.value == url.path }) {
                    configuration.applications.append(entry)
                }
            } else if configuration.directories.count < 32, !configuration.directories.contains(where: { $0.value == url.path }) {
                configuration.directories.append(entry)
            }
        }
        save()
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n").replacingOccurrences(of: "\r", with: "\\r") + "\""
    }
    // Port of QuickTogglesService's Finder flag path: same preference, polite quit if already authorized, killall fallback.
    private func toggleHiddenFiles() {
        guard !busy else { return }; busy = true
        workQueue.async { [self] in
            let domain = "com.apple.finder" as CFString
            let key = "AppleShowAllFiles" as CFString
            let value = CFPreferencesCopyAppValue(key, domain)
            let shown: Bool
            if let flag = value as? NSNumber { shown = flag.boolValue }
            else if let string = value as? String { shown = ["yes", "true", "1"].contains(string.lowercased()) }
            else { shown = false }
            CFPreferencesSetAppValue(key, (!shown) as CFBoolean, domain)
            CFPreferencesAppSynchronize(domain)
            let ok = restartFinder()
            DispatchQueue.main.async { self.busy = false; if !ok { self.fail(L("Could not refresh Finder. Reopen Finder manually.")) } }
        }
    }
    private func restartFinder() -> Bool {
        if FinderAppleScript.automationGranted(bundleID: "com.apple.finder"),
           FinderAppleScript.runDetailed("tell application \"Finder\" to quit").ok {
            for _ in 0..<30 {
                if Self.runProcess("/usr/bin/pgrep", ["-x", "Finder"]) != 0 {
                    let configuration = NSWorkspace.OpenConfiguration(); configuration.activates = false
                    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"), configuration: configuration)
                    return true
                }
                usleep(100_000)
            }
        }
        return Self.runProcess("/usr/bin/killall", ["Finder"]) == 0
    }
    private static func runProcess(_ path: String, _ arguments: [String]) -> Int32 {
        let process = Process(); process.executableURL = URL(fileURLWithPath: path); process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus } catch { return -1 }
    }
}

// The original in-process AppleScript runner keeps Automation attribution on 1Tool.
private enum FinderAppleScript {
    static func automationGranted(bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let created = bundleID.withCString { AECreateDesc(typeApplicationBundleID, $0, bundleID.utf8.count, &target) }
        guard created == noErr else { return false }; defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false) == noErr
    }
    static func runDetailed(_ source: String) -> (ok: Bool, errorNumber: Int?, message: String, output: String) {
        guard let script = NSAppleScript(source: source) else { return (false, nil, "", "") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (false, error[NSAppleScript.errorNumber] as? Int,
                    (error[NSAppleScript.errorMessage] as? String) ?? "", "")
        }
        return (true, nil, "", result.stringValue ?? "")
    }
}
