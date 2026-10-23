// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Darwin

struct UninstallApp: Identifiable, Sendable, Equatable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    let version: String
}

struct UninstallStamp: Sendable, Equatable {
    let path: String
    let device: Int32
    let inode: UInt64
    let mode: UInt16
    let size: Int64
    let modified: Int64
    let modifiedNanos: Int64
    let changed: Int64
    let changedNanos: Int64
}

/// Observable scan failures; none of these implies a particular TCC permission was denied.
struct UninstallProblem: Error, LocalizedError, Sendable, Identifiable {
    enum Kind: Sendable { case protected, permission, limit, changed, linked, unsupported, unavailable, running, inUse }
    let kind: Kind
    let url: URL
    let detail: String
    var id: String { url.path + ":" + String(describing: kind) }
    var errorDescription: String? { message }
    var message: String {
        switch kind {
        case .protected: return L(detail)
        case .permission: return L("Access was denied. Check this path’s file permissions and macOS privacy settings.")
        case .limit: return L("The scan limit was reached. This path was not fully inspected.")
        case .changed: return L("Files changed or disappeared. Scan the app again.")
        case .linked: return L("Symbolic links in this path are protected.")
        case .unsupported: return L("This path contains an unsupported file type and is protected.")
        case .unavailable: return L("This path could not be inspected. Review the error details and try again.")
        case .running: return L("Quit this app and its background processes before uninstalling.")
        case .inUse: return L("A selected file is in use by another process. Close the file or stop the operation, then try again.")
        }
    }
    static func capture(_ error: Error, at url: URL) -> Self {
        if let problem = error as? Self { return problem }
        if let failure = error as? UninstallError {
            return .init(kind: failure == .changed ? .changed : .running, url: url, detail: failure.localizedDescription)
        }
        let ns = error as NSError
        let code = (ns.userInfo[NSUnderlyingErrorKey] as? NSError) ?? ns
        let kind: Kind
        if (code.domain == NSPOSIXErrorDomain && [Int(EACCES), Int(EPERM)].contains(code.code))
            || (ns.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(ns.code)) { kind = .permission }
        else if code.domain == NSPOSIXErrorDomain && [Int(ENOENT), Int(ESTALE)].contains(code.code) { kind = .changed }
        else if ns.domain == NSCocoaErrorDomain && ns.code == NSFileReadTooLargeError { kind = .limit }
        else { kind = .unavailable }
        return .init(kind: kind, url: url, detail: "\(ns.domain) (\(ns.code)): " + ns.localizedDescription)
    }
    static func posix(at url: URL, code: Int32 = errno) -> Self {
        capture(POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO), at: url)
    }
}

struct UninstallInventory: Sendable {
    var apps: [UninstallApp] = []
    var problems: [UninstallProblem] = []
}

struct UninstallItem: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let category: String
    let nameMatch: Bool
    let stamps: [UninstallStamp]
    let bytes: Int64
    let issue: String?
    var problem: UninstallProblem? = nil
}

struct UninstallPlan: Sendable {
    let app: UninstallApp
    let items: [UninstallItem]
    let warnings: [String]
    var blockedItems: [UninstallItem] { items.filter { $0.issue != nil } }
    var appItem: UninstallItem? { items.first { $0.id == app.id } }
}

struct UninstallOpenFile: Sendable, Equatable {
    let path: String
    let pid: Int32
    let command: String
    let descriptor: String
    let access: String
    var readOnly: Bool {
        access == "r" || (access.trimmingCharacters(in: .whitespaces).isEmpty && ["txt", "mem"].contains(descriptor))
    }
}

struct UninstallActivity: Sendable {
    var bundleIDs: Set<String> = []
    var appPaths: Set<String> = []
    var openPaths: Set<String> = []
    var executablePaths: Set<String> = []
    var readOnlyPaths: Set<String> = []
    var references: [UninstallOpenFile] = []

    static func live() throws -> Self {
        let apps = NSWorkspace.shared.runningApplications
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // NUL-delimited fields preserve file names containing line breaks.
        process.arguments = ["-nP", "-F0pcfan", "-u", String(getuid())]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadNoPermission) }
        let references = parseOpenFiles(data)
        var executables: [Int32: String] = [:]
        for pid in Set(references.map(\.pid)).union(apps.map(\.processIdentifier)) {
            var buffer = [CChar](repeating: 0, count: 4096)
            if proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 {
                executables[pid] = CleanupEngine.normalizedPath(URL(fileURLWithPath: String(cString: buffer)))
            }
        }
        // A reference is harmless for app-bundle moves only when every holder is known,
        // read-only, and the actual executable lives outside the target app (checked below).
        let grouped = Dictionary(grouping: references, by: \.path)
        let readOnly = Set(grouped.compactMap { path, holders in
            holders.allSatisfy { $0.readOnly && executables[$0.pid] != nil } ? path : nil
        })
        return .init(bundleIDs: Set(apps.compactMap(\.bundleIdentifier)),
                     appPaths: Set(apps.compactMap { $0.bundleURL.map(CleanupEngine.normalizedPath) }),
                     openPaths: Set(references.map(\.path)), executablePaths: Set(executables.values),
                     readOnlyPaths: readOnly, references: references)
    }

    static func parseOpenFiles(_ data: Data) -> [UninstallOpenFile] {
        var records: [UninstallOpenFile] = []
        var pid: Int32 = 0, command = "", descriptor = "", access = "", path: String?
        func append() {
            if let path, path.hasPrefix("/"), pid > 0 {
                records.append(.init(path: CleanupEngine.normalizedPath(URL(fileURLWithPath: path)),
                                     pid: pid, command: command, descriptor: descriptor, access: access))
            }
        }
        for raw in String(decoding: data, as: UTF8.self).split(separator: "\0") {
            let field = raw.drop(while: { $0 == "\n" })
            guard let kind = field.first else { continue }
            let value = String(field.dropFirst())
            switch kind {
            case "p": append(); pid = Int32(value) ?? 0; command = ""; descriptor = ""; access = ""; path = nil
            case "c": command = value
            case "f": append(); descriptor = value; access = ""; path = nil
            case "a": access = value
            case "n": path = value
            default: break
            }
        }
        append()
        return records
    }

    func blockingProblem(for app: UninstallApp, items: [UninstallItem]) -> UninstallProblem? {
        let appPath = CleanupEngine.normalizedPath(app.url)
        if bundleIDs.contains(app.bundleID) || appPaths.contains(appPath)
            || executablePaths.contains(where: { $0 == appPath || $0.hasPrefix(appPath + "/") }) {
            return .init(kind: .running, url: app.url, detail: "")
        }
        for path in openPaths.sorted() {
            guard items.contains(where: { path == $0.url.path || path.hasPrefix($0.url.path + "/") }) else { continue }
            // Moving an app to recoverable Trash does not invalidate another process's
            // existing read-only mapping of its icons, metadata or localized resources.
            // Reads of app DATA remain protected, as do writers and unknown access modes.
            if path.hasPrefix(appPath + "/"), readOnlyPaths.contains(path) { continue }
            let holders = references.filter { $0.path == path }.sorted { $0.pid < $1.pid }
            let detail = holders.map { LF("Process: %@ (PID %d)", $0.command, $0.pid) }.joined(separator: "\n")
            return .init(kind: .inUse, url: URL(fileURLWithPath: path), detail: detail)
        }
        return nil
    }
    func protects(_ app: UninstallApp, items: [UninstallItem]) -> Bool {
        blockingProblem(for: app, items: items) != nil
    }
}

struct UninstallResult: Sendable {
    var moved: [URL] = []
    var failures: [String] = []
    var recoveryURL: URL?
    var inTrash = false
    var cancelled = false
    var problems: [UninstallProblem] = []
}

/// Independent, conservative discovery: exact bundle IDs and explicitly labelled exact app names.
/// Shared vendor folders, app groups, privileged helpers and system-wide Library are outside scope.
struct UninstallEngine: Sendable {
    var home = FileManager.default.homeDirectoryForCurrentUser
    var applicationRoots: [URL] = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    var fileLimit = 200_000
    private var fm: FileManager { .default }
    private var library: URL { home.appendingPathComponent("Library") }
    private var recoveryRoot: URL { library.appendingPathComponent("Application Support/1Tool/Uninstall Recovery") }

    static func application(at url: URL) -> UninstallApp? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app", CleanupEngine.safeAncestors(url),
              let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, validIdentifier(id),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL" else { return nil }
        return .init(url: url, name: bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                     ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent,
                     bundleID: id, version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    }
    private static func validIdentifier(_ id: String) -> Bool {
        id.contains(".") && id.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
            !part.isEmpty && part.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
        }
    }
    func protection(for app: UninstallApp) -> String? {
        let path = CleanupEngine.normalizedPath(app.url)
        if app.bundleID.lowercased().hasPrefix("com.apple.") || ["/System", "/Library", "/usr", "/bin", "/sbin"].contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
            return "System applications are protected"
        }
        if app.bundleID.lowercased() == "com.shopkivoo.onetool" || app.bundleID.lowercased().hasPrefix("com.shopkivoo.onetool.") || app.url == Bundle.main.bundleURL { return "1Tool cannot uninstall itself" }
        if path.contains("/.Trash/") || path.hasPrefix(library.path + "/") { return "Applications in Library or Trash are protected" }
        var ancestor = app.url.deletingLastPathComponent()
        while ancestor.path != "/" {
            if ancestor.pathExtension.lowercased() == "app" { return "Nested applications are protected" }
            ancestor.deleteLastPathComponent()
        }
        return nil
    }
    func applications(cancelled: () -> Bool = { false }) throws -> [UninstallApp] {
        try inventory(cancelled: cancelled).apps
    }
    func inventory(cancelled: () -> Bool = { false }) throws -> UninstallInventory {
        var apps: [String: UninstallApp] = [:], problems: [UninstallProblem] = []
        for root in applicationRoots {
            if cancelled() { throw CancellationError() }
            var info = stat()
            if lstat(root.path, &info) != 0 {
                if errno != ENOENT { problems.append(.posix(at: root)) }
                continue
            }
            do { try validateAncestors(root) }
            catch { problems.append(.capture(error, at: root)); continue }
            guard let entries = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles], errorHandler: { url, error in
                problems.append(.capture(error, at: url)); return true
            }) else { problems.append(.init(kind: .unavailable, url: root, detail: "")); continue }
            for case let url as URL in entries {
                if cancelled() { throw CancellationError() }
                let depth = url.pathComponents.count - root.pathComponents.count
                if url.pathExtension.lowercased() == "app" {
                    entries.skipDescendants()
                    if let app = Self.application(at: url) { apps[app.id] = app }
                } else if depth >= 3 || (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { entries.skipDescendants() }
            }
        }
        return .init(apps: apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }, problems: problems)
    }
    private func relatedPaths(for app: UninstallApp, installed: [UninstallApp]) -> [(URL, String, Bool)] {
        let id = app.bundleID
        var result: [(URL, String, Bool)] = []
        for (folder, leaf, category) in [
            ("Application Support", id, "Application Data"), ("Caches", id, "App Caches"),
            ("Preferences", id + ".plist", "Preferences"), ("Saved Application State", id + ".savedState", "Saved State"),
            ("Logs", id, "Logs"), ("HTTPStorages", id, "Web Data"),
            ("HTTPStorages", id + ".binarycookies", "Web Data"), ("WebKit", id, "Web Data"),
            ("Containers", id, "App Container")
        ] { result.append((library.appendingPathComponent(folder).appendingPathComponent(leaf), category, false)) }
        // Names are weaker ownership evidence. Never select a name shared by another installed app.
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent])
        for name in names.sorted() where name.count >= 3 && name != "." && name != ".." && !name.contains("/") && !name.contains(":") {
            let ambiguous = installed.contains { other in
                other.id != app.id && (other.name.caseInsensitiveCompare(name) == .orderedSame
                    || other.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame)
            }
            guard !ambiguous else { continue }
            for (folder, category) in [("Application Support", "Application Data"), ("Caches", "App Caches"), ("Logs", "Logs")] {
                result.append((library.appendingPathComponent(folder).appendingPathComponent(name), category, true))
            }
        }
        return result
    }
    func scan(_ app: UninstallApp, installed: [UninstallApp], cancelled: () -> Bool = { false }) throws -> UninstallPlan {
        if cancelled() { throw CancellationError() }
        try validateAncestors(app.url)
        guard let current = Self.application(at: app.url), current.bundleID == app.bundleID else {
            throw UninstallProblem(kind: .changed, url: app.url, detail: "")
        }
        if let protection = protection(for: app) {
            let problem = UninstallProblem(kind: .protected, url: app.url, detail: protection)
            return .init(app: app, items: [.init(url: app.url, category: "Application", nameMatch: false, stamps: [], bytes: 0, issue: protection, problem: problem)], warnings: [])
        }
        var items: [UninstallItem] = [], seen = Set<String>(), warnings: [String] = []
        let duplicateID = installed.contains { $0.id != app.id && $0.bundleID == app.bundleID }
        let paths = [(app.url, "Application", false)] + (duplicateID ? [] : relatedPaths(for: app, installed: installed))
        if duplicateID { warnings.append("Another copy of this app is installed. Shared app data is protected.") }
        for (url, category, nameMatch) in paths where seen.insert(url.path).inserted {
            if cancelled() { throw CancellationError() }
            var info = stat()
            if lstat(url.path, &info) != 0 {
                if errno != ENOENT {
                    let problem = UninstallProblem.posix(at: url)
                    items.append(.init(url: url, category: category, nameMatch: nameMatch, stamps: [], bytes: 0, issue: problem.message, problem: problem))
                }
                continue
            }
            do {
                let (stamps, bytes) = try tree(at: url, cancelled: cancelled)
                items.append(.init(url: url, category: category, nameMatch: nameMatch, stamps: stamps, bytes: bytes, issue: nil))
            } catch is CancellationError { throw CancellationError() }
            catch {
                let problem = UninstallProblem.capture(error, at: url)
                items.append(.init(url: url, category: category, nameMatch: nameMatch, stamps: [], bytes: 0, issue: problem.message, problem: problem))
            }
        }
        return .init(app: app, items: items, warnings: warnings)
    }
    private func validateAncestors(_ url: URL) throws {
        var current = URL(fileURLWithPath: CleanupEngine.normalizedPath(url))
        while current.path != "/" {
            var info = stat()
            guard lstat(current.path, &info) == 0 else { throw UninstallProblem.posix(at: current) }
            if (info.st_mode & S_IFMT) == S_IFLNK { throw UninstallProblem(kind: .linked, url: current, detail: "") }
            current.deleteLastPathComponent()
        }
    }
    private func tree(at url: URL, cancelled: () -> Bool) throws -> ([UninstallStamp], Int64) {
        try validateAncestors(url)
        var stamps: [UninstallStamp] = [], bytes: Int64 = 0
        func record(_ child: URL) throws {
            if cancelled() { throw CancellationError() }
            guard stamps.count < fileLimit else { throw UninstallProblem(kind: .limit, url: url, detail: "") }
            var info = stat()
            guard lstat(child.path, &info) == 0 else { throw UninstallProblem.posix(at: child) }
            let kind = info.st_mode & S_IFMT
            guard kind == S_IFDIR || kind == S_IFREG || kind == S_IFLNK else { throw UninstallProblem(kind: .unsupported, url: child, detail: "") }
            stamps.append(.init(path: child.path, device: info.st_dev, inode: UInt64(info.st_ino), mode: info.st_mode,
                                size: info.st_size, modified: Int64(info.st_mtimespec.tv_sec), modifiedNanos: Int64(info.st_mtimespec.tv_nsec),
                                changed: Int64(info.st_ctimespec.tv_sec), changedNanos: Int64(info.st_ctimespec.tv_nsec)))
            bytes += Int64(info.st_blocks) * 512
        }
        try record(url)
        var rootInfo = stat()
        guard lstat(url.path, &rootInfo) == 0 else { throw UninstallProblem.posix(at: url) }
        if (rootInfo.st_mode & S_IFMT) == S_IFDIR {
            var failure: UninstallProblem?
            guard let entries = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { path, error in
                failure = .capture(error, at: path); return false
            }) else { throw UninstallProblem(kind: .unavailable, url: url, detail: "") }
            for case let child as URL in entries {
                try record(child)
                do {
                    if (try child.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true { entries.skipDescendants() }
                } catch { throw UninstallProblem.capture(error, at: child) }
            }
            if let failure { throw failure }
        }
        return (stamps.sorted { $0.path < $1.path }, bytes)
    }

    func uninstall(_ plan: UninstallPlan, selected: Set<String>, installed: [UninstallApp],
                   activity: () throws -> UninstallActivity = { try .live() }, cancelled: () -> Bool = { false },
                   applicationTrash: ((URL) throws -> URL)? = nil) throws -> UninstallResult {
        guard protection(for: plan.app) == nil, selected.contains(plan.app.id),
              let current = Self.application(at: plan.app.url), current.bundleID == plan.app.bundleID else { throw CocoaError(.fileWriteNoPermission) }
        // Re-derive the allowlist. Never trust an arbitrary path supplied by a UI or stale plan.
        let duplicateID = installed.contains { $0.id != plan.app.id && $0.bundleID == plan.app.bundleID }
        let allowed = Set([plan.app.id] + (duplicateID ? [] : relatedPaths(for: plan.app, installed: installed).map { $0.0.path }))
        let items = plan.items.filter { selected.contains($0.id) }
        guard selected.isSubset(of: Set(items.map(\.id))), items.allSatisfy({ allowed.contains($0.id) && $0.issue == nil && !$0.stamps.isEmpty }),
              items.first?.id == plan.app.id else { throw CocoaError(.fileWriteNoPermission) }
        if let problem = try activity().blockingProblem(for: plan.app, items: items) { throw problem }
        if cancelled() { return .init(cancelled: true) }
        // Anchor all moves to a verified recovery directory; a failed Trash call retains this folder.
        let recovery = try createRecovery()
        let recoveryFD = try CleanupEngine.parentDescriptor(recovery.appendingPathComponent("placeholder"))
        defer { close(recoveryFD) }
        var result = UninstallResult()
        do {
            var manifest = items.enumerated().map { ["original": $0.element.url.path, "stored": String(format: "%03d-", $0.offset) + $0.element.url.lastPathComponent] }
            let manifestURL = recovery.appendingPathComponent("1Tool-Uninstall-Recovery.json")
            func saveManifest(initial: Bool = false) throws {
                let data = try JSONSerialization.data(withJSONObject: ["application": plan.app.bundleID, "items": manifest] as [String: Any], options: [.prettyPrinted, .sortedKeys])
                try data.write(to: manifestURL, options: initial ? .withoutOverwriting : .atomic)
            }
            try saveManifest(initial: true)
            for (index, item) in items.enumerated() {
                if cancelled() { result.cancelled = true; break }
                do {
                    if let problem = try activity().blockingProblem(for: plan.app, items: items) { throw problem }
                    let (fresh, _) = try tree(at: item.url, cancelled: cancelled)
                    guard fresh == item.stamps else { throw UninstallError.changed }
                    let parent = try CleanupEngine.parentDescriptor(item.url)
                    defer { close(parent) }
                    var info = stat()
                    guard let stamp = item.stamps.first(where: { $0.path == item.url.path }),
                          fstatat(parent, item.url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
                          UInt64(info.st_ino) == stamp.inode, info.st_dev == stamp.device,
                          info.st_mode == stamp.mode, info.st_ctimespec.tv_sec == stamp.changed,
                          info.st_ctimespec.tv_nsec == stamp.changedNanos else { throw UninstallError.changed }
                    let destination = String(format: "%03d-", index) + item.url.lastPathComponent
                    if renameatx_np(parent, item.url.lastPathComponent, recoveryFD, destination, UInt32(RENAME_EXCL)) != 0 {
                        let failure = errno
                        // Only the selected, validated app may use the system's
                        // interactive Trash operation. Never elevate data-folder moves.
                        guard index == 0, failure == EACCES || failure == EPERM, let applicationTrash else {
                            throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EACCES)
                        }
                        let trashed = try applicationTrash(item.url)
                        result.moved.append(item.url)
                        manifest[index].removeValue(forKey: "stored")
                        manifest[index]["trashed"] = trashed.path
                        try saveManifest()
                        continue
                    }
                    result.moved.append(item.url)
                } catch is CancellationError { result.cancelled = true; break }
                catch let error as CocoaError where error.code == .userCancelled { result.cancelled = true; break }
                catch {
                    result.failures.append(item.url.path + ": " + error.localizedDescription)
                    result.problems.append(.capture(error, at: item.url))
                    // App first: a failure must never strip data from an application still installed.
                    if index == 0 { break }
                }
            }
        } catch { result.failures.append(error.localizedDescription) }
        if result.moved.isEmpty { try? fm.removeItem(at: recovery); return result }
        result.recoveryURL = recovery
        do {
            guard CleanupEngine.safeAncestors(recovery) else { throw CocoaError(.fileWriteNoPermission) }
            var destination: NSURL?
            try fm.trashItem(at: recovery, resultingItemURL: &destination)
            if let destination { result.recoveryURL = destination as URL; result.inTrash = true }
        } catch { result.failures.append(L("Files remain in Uninstall Recovery") + ": " + recovery.path + ": " + error.localizedDescription) }
        return result
    }
    private func createRecovery() throws -> URL {
        var ancestor = recoveryRoot
        while !fm.fileExists(atPath: ancestor.path) && ancestor.path != "/" { ancestor.deleteLastPathComponent() }
        guard CleanupEngine.safeAncestors(ancestor) else { throw CocoaError(.fileWriteNoPermission) }
        try fm.createDirectory(at: recoveryRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard CleanupEngine.safeAncestors(recoveryRoot) else { throw CocoaError(.fileWriteNoPermission) }
        let url = recoveryRoot.appendingPathComponent("1Tool-Uninstall-" + UUID().uuidString)
        try fm.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return url
    }
}

enum UninstallError: LocalizedError {
    case running, changed
    var errorDescription: String? {
        L(self == .running ? "Quit this app and its background processes before uninstalling." : "Files changed since scanning. Scan the app again.")
    }
}
