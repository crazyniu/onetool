// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

enum CleanupCategory: String, CaseIterable, Sendable, Identifiable {
    case browsers, developer, logs
    var id: String { rawValue }
    var title: String { L(self == .browsers ? "App Caches" : self == .developer ? "Developer Caches" : "Old Logs") }
    var symbol: String { self == .browsers ? "globe" : self == .developer ? "hammer" : "doc.text" }
}
struct CleanupRule: Sendable, Identifiable {
    let id: String
    let name: String
    let root: URL
    let category: CleanupCategory
    var age: TimeInterval = 7 * 86400
    var bundleIDs: [String] = []
    var inspectionOnly = false
    var owner: String {
        let label = name.components(separatedBy: " · ").first ?? name
        return ["Google/Chrome": "Google Chrome", "Google/Chrome Canary": "Chrome Canary", "Code": "Visual Studio Code", "com.openai.codex": "Codex", "DiagnosticReports": L("System Diagnostics")][label] ?? label
    }
}
struct CleanupFile: Sendable {
    let url: URL
    let device: Int32
    let inode: UInt64
    let size: Int64
    let allocated: Int64
    let modified: timespec
    // timespec is a value type in Darwin; snapshots never retain file handles.
}
struct CleanupCandidate: Sendable, Identifiable {
    var id: String { rule.id }
    let rule: CleanupRule
    let files: [CleanupFile]
    let skippedFiles: Int
    let note: String?
    var uninspectedPaths: [String] = []
    var occupiedBytes: Int64 = 0
    var bytes: Int64 { files.reduce(0) { $0 + $1.allocated } }
}
struct CleanupStorage: Sendable {
    let total: Int64
    let available: Int64
    var used: Int64 { max(0, total - available) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}
struct CleanupScan: Sendable {
    let candidates: [CleanupCandidate]
    let freeBytes: Int64
    let date: Date
    var incomplete: Bool { candidates.contains { !$0.uninspectedPaths.isEmpty } }
}
struct CleanupResult: Sendable {
    var processedFiles = 0
    var processedBytes: Int64 = 0
    var skippedFiles = 0
    var failures: [String] = []
    var recoveredFolders: [URL] = []
    var freeDelta: Int64 = 0
    var permanent = false
    var cancelled = false
    var requestedFiles = 0
    enum Outcome { case completed, partial, cancelled, failed }
    var outcome: Outcome {
        if cancelled { return .cancelled }
        if !failures.isEmpty { return processedFiles > 0 ? .partial : .failed }
        return skippedFiles > 0 ? .partial : .completed
    }
    var remainingFiles: Int { max(0, requestedFiles - processedFiles - skippedFiles) }
}

/// Deliberately bounded: known rebuildable caches only, never arbitrary user-selected folders.
/// No sudo, whole-home scans, installed tools, site storage, Trash emptying or shell interpolation.
struct CleanupEngine: Sendable {
    let rules: [CleanupRule]
    let stagingRoot: URL
    var now = Date()
    var fileLimit = 150_000

    static func live(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Self {
        let caches = home.appendingPathComponent("Library/Caches")
        var rules: [CleanupRule] = []
        func add(_ id: String, _ name: String, _ path: URL, _ category: CleanupCategory, _ age: TimeInterval = 7 * 86400, _ apps: [String] = []) {
            rules.append(.init(id: id, name: name, root: path, category: category, age: age, bundleIDs: apps))
        }
        for (directory, bundle) in [("Google/Chrome", "com.google.Chrome"), ("Google/Chrome Canary", "com.google.Chrome.canary"), ("Codex", "com.openai.codex")] {
            let root = caches.appendingPathComponent(directory)
            let profiles: [URL]
            do { profiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) }
            catch {
                var info = stat()
                let status = lstat(root.path, &info), code = errno
                if status == 0 || (code != ENOENT && code != ENOTDIR) {
                    rules.append(.init(id: "discovery-" + directory, name: directory, root: root, category: .browsers, inspectionOnly: true))
                }
                continue
            }
            for profile in profiles where profile.lastPathComponent == "Default" || profile.lastPathComponent.hasPrefix("Profile ") {
                for child in ["Cache", "Code Cache"] {
                    let path = profile.appendingPathComponent(child)
                    add(path.path, directory + " · " + profile.lastPathComponent + " · " + child, path, .browsers, 86400, [bundle])
                }
            }
        }
        for (name, bundle) in [("Notion", "notion.id"), ("Code", "com.microsoft.VSCode"), ("orca", "com.stablyai.orca")] {
            for child in ["Cache", "Code Cache", "GPUCache"] {
                let path = home.appendingPathComponent("Library/Application Support/\(name)/\(child)")
                add(path.path, name + " · " + child, path, .browsers, 86400, [bundle])
            }
        }
        for (name, path) in [("pip", "Library/Caches/pip"), ("Homebrew", "Library/Caches/Homebrew"), ("Electron", "Library/Caches/electron"), ("npm", ".npm/_cacache"), ("Cargo", ".cargo/registry/cache")] {
            add(path, name, home.appendingPathComponent(path), .developer)
        }
        add("xcode-modules", "Xcode · ModuleCache", home.appendingPathComponent("Library/Developer/Xcode/DerivedData/ModuleCache.noindex"), .developer, 7 * 86400, ["com.apple.dt.Xcode"])
        let temporary = NSTemporaryDirectory()
        let darwinTemporary = URL(fileURLWithPath: temporary.hasPrefix("/var/") ? "/private" + temporary : temporary)
        let darwinCache = darwinTemporary.deletingLastPathComponent().appendingPathComponent("C/clang/ModuleCache")
        add("clang-modules", "Clang · ModuleCache", darwinCache, .developer, 7 * 86400, ["com.apple.dt.Xcode"])
        for (name, bundle) in [("com.openai.codex", "com.openai.codex"), ("Notion", "notion.id"), ("DiagnosticReports", "")] {
            add("logs-" + name, name, home.appendingPathComponent("Library/Logs/" + name), .logs, 30 * 86400, bundle.isEmpty ? [] : [bundle])
        }
        return Self(rules: rules, stagingRoot: home.appendingPathComponent("Library/Application Support/1Tool/Cleanup Recovery"))
    }

    static func storage(at location: URL = FileManager.default.homeDirectoryForCurrentUser) -> CleanupStorage? {
        var url = URL(fileURLWithPath: location.path)
        url.removeAllCachedResourceValues()
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]),
              let total = values.volumeTotalCapacity, let available = values.volumeAvailableCapacity,
              total > 0, available >= 0 else { return nil }
        return CleanupStorage(total: Int64(total), available: min(Int64(total), Int64(available)))
    }
    static func freeSpace() -> Int64 { storage()?.available ?? 0 }
    static func totalSpace() -> Int64 { storage()?.total ?? 0 }
    // Foundation's standardizedFileURL collapses /private/var back to the /var symlink.
    // Normalize dot components lexically, without resolving or introducing links.
    static func normalizedPath(_ url: URL) -> String {
        var parts: [String] = []
        for part in url.pathComponents {
            if part == "/" || part == "." { continue }
            if part == ".." { if !parts.isEmpty { parts.removeLast() } }
            else { parts.append(part) }
        }
        let result = "/" + parts.joined(separator: "/")
        return result.hasPrefix("/var/") ? "/private" + result : result
    }
    /// Refuse symbolic links in every ancestor, including dangling links.
    static func safeAncestors(_ url: URL) -> Bool {
        var current = URL(fileURLWithPath: normalizedPath(url))
        while current.path != "/" {
            var info = stat()
            guard lstat(current.path, &info) == 0, (info.st_mode & S_IFMT) != S_IFLNK else { return false }
            current.deleteLastPathComponent()
        }
        return true
    }
    static func snapshot(_ url: URL) -> CleanupFile? {
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1 else { return nil }
        return .init(url: url, device: info.st_dev, inode: UInt64(info.st_ino), size: info.st_size,
                     allocated: Int64(info.st_blocks) * 512, modified: info.st_mtimespec)
    }
    static func unchanged(_ file: CleanupFile) -> Bool {
        guard let current = snapshot(file.url) else { return false }
        return current.device == file.device && current.inode == file.inode && current.size == file.size
            && current.modified.tv_sec == file.modified.tv_sec && current.modified.tv_nsec == file.modified.tv_nsec
    }
    static func openFiles() throws -> Set<String> {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "-F", "n", "-u", String(getuid())]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileReadNoPermission) }
        return Set(String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap {
            $0.hasPrefix("n/") ? normalizedPath(URL(fileURLWithPath: String($0.dropFirst()))) : nil
        })
    }
    func scan(openFiles: Set<String>, runningApps: Set<String>, cancelled: () -> Bool = { false }) throws -> CleanupScan {
        var candidates: [CleanupCandidate] = []
        for rule in rules {
            if cancelled() { throw CancellationError() }
            var rootInfo = stat()
            if lstat(rule.root.path, &rootInfo) != 0 {
                if errno != ENOENT && errno != ENOTDIR {
                    candidates.append(.init(rule: rule, files: [], skippedFiles: 0, note: "This location could not be inspected", uninspectedPaths: [rule.root.path]))
                }
                continue
            }
            if rule.inspectionOnly {
                candidates.append(.init(rule: rule, files: [], skippedFiles: 0, note: "This location could not be inspected", uninspectedPaths: [rule.root.path])); continue
            }
            guard Self.safeAncestors(rule.root) else {
                candidates.append(.init(rule: rule, files: [], skippedFiles: 0, note: "Linked paths are protected")); continue
            }
            let appRunning = !runningApps.isDisjoint(with: rule.bundleIDs)
            var files: [CleanupFile] = [], skipped = 0
            var occupied: Int64 = 0
            var countedInodes = Set<String>()
            var uninspected: [String] = []
            var seen = 0
            guard let enumerator = FileManager.default.enumerator(at: rule.root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [], errorHandler: { url, _ in uninspected.append(url.path); return true }) else {
                candidates.append(.init(rule: rule, files: [], skippedFiles: 0, note: "This location could not be inspected", uninspectedPaths: [rule.root.path])); continue
            }
            for case let url as URL in enumerator {
                if cancelled() { throw CancellationError() }
                seen += 1
                if seen > fileLimit { uninspected.append(rule.root.path); break }
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true { enumerator.skipDescendants(); skipped += 1; continue }
                if values?.isDirectory == true { continue }
                var info = stat()
                guard lstat(url.path, &info) == 0 else { uninspected.append(url.path); continue }
                if (info.st_mode & S_IFMT) == S_IFREG,
                   countedInodes.insert("\(info.st_dev):\(info.st_ino)").inserted {
                    occupied += max(0, Int64(info.st_blocks) * 512)
                }
                guard !appRunning, let file = Self.snapshot(url), !openFiles.contains(Self.normalizedPath(url)),
                      now.timeIntervalSince1970 - Double(file.modified.tv_sec) >= rule.age else { skipped += 1; continue }
                files.append(file)
            }
            if !files.isEmpty || skipped > 0 || !uninspected.isEmpty {
                candidates.append(.init(rule: rule, files: files, skippedFiles: skipped,
                    note: !uninspected.isEmpty ? "Some files could not be inspected" : appRunning ? "Quit this app to clean its cache" : nil,
                    uninspectedPaths: Array(Set(uninspected)).sorted(), occupiedBytes: occupied))
            }
        }
        return .init(candidates: candidates, freeBytes: Self.freeSpace(), date: now)
    }
    func clean(_ candidates: [CleanupCandidate], permanent: Bool, openFiles: Set<String>, runningApps: Set<String>,
               cancelled: () -> Bool = { false }, progress: (Int) -> Void = { _ in }) throws -> CleanupResult {
        var result = CleanupResult(); result.permanent = permanent
        result.requestedFiles = candidates.reduce(0) { $0 + $1.files.count }
        let before = Self.freeSpace()
        let fm = FileManager.default
        for (index, candidate) in candidates.enumerated() {
            if cancelled() { result.cancelled = true; break }
            guard let rule = rules.first(where: { $0.id == candidate.id }), rule.root == candidate.rule.root,
                  !rule.inspectionOnly, Self.safeAncestors(rule.root), runningApps.isDisjoint(with: rule.bundleIDs) else {
                result.skippedFiles += candidate.files.count; continue
            }
            var recovery: URL?
            if !permanent {
              do {
                var existing = stagingRoot
                while !fm.fileExists(atPath: existing.path) && existing.path != "/" { existing.deleteLastPathComponent() }
                guard Self.safeAncestors(existing) else { throw CocoaError(.fileWriteNoPermission) }
                try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                guard Self.safeAncestors(stagingRoot) else { throw CocoaError(.fileWriteNoPermission) }
                recovery = stagingRoot.appendingPathComponent("1Tool-" + UUID().uuidString)
                try fm.createDirectory(at: recovery!, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                let manifest: [String: String] = ["source": rule.root.path, "application": rule.owner, "created": ISO8601DateFormatter().string(from: Date()), "restore": "Quit the owning app. Restore files from Files/ to source only if the destination does not already exist."]
                let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: recovery!.appendingPathComponent("1Tool-Recovery.json"), options: .withoutOverwriting)
              } catch {
                result.failures.append(rule.root.path + ": " + error.localizedDescription)
                if let recovery { result.recoveredFolders.append(recovery) }
                continue
              }
            }
            for file in candidate.files {
                if cancelled() { result.cancelled = true; break }
                let path = Self.normalizedPath(file.url)
                guard path.hasPrefix(Self.normalizedPath(rule.root) + "/"), Self.safeAncestors(file.url.deletingLastPathComponent()),
                      !openFiles.contains(path), Self.unchanged(file), now.timeIntervalSince1970 - Double(file.modified.tv_sec) >= rule.age else {
                    result.skippedFiles += 1; continue
                }
                do {
                    // Anchor operations to verified parent descriptors; never follow a replaced path.
                    let fd = try Self.parentDescriptor(file.url)
                    defer { close(fd) }
                    var info = stat()
                    guard fstatat(fd, file.url.lastPathComponent, &info, AT_SYMLINK_NOFOLLOW) == 0,
                          UInt64(info.st_ino) == file.inode, info.st_dev == file.device, info.st_size == file.size,
                          info.st_mtimespec.tv_sec == file.modified.tv_sec, info.st_mtimespec.tv_nsec == file.modified.tv_nsec,
                          info.st_uid == getuid(), info.st_nlink == 1, (info.st_mode & S_IFMT) == S_IFREG else {
                        result.skippedFiles += 1; continue
                    }
                    if permanent {
                        guard unlinkat(fd, file.url.lastPathComponent, 0) == 0 else { throw POSIXError(.EACCES) }
                    } else if let recovery {
                        let relative = String(path.dropFirst(Self.normalizedPath(rule.root).count + 1))
                        let destination = recovery.appendingPathComponent("Files").appendingPathComponent(relative)
                        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                        let destFD = try Self.parentDescriptor(destination)
                        defer { close(destFD) }
                        guard renameatx_np(fd, file.url.lastPathComponent, destFD, destination.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw POSIXError(.EACCES) }
                    }
                    result.processedFiles += 1; result.processedBytes += file.allocated
                } catch { result.failures.append(file.url.path + ": " + error.localizedDescription) }
            }
            if let recovery {
                do {
                    var destination: NSURL?
                    try fm.trashItem(at: recovery, resultingItemURL: &destination)
                    if let destination { result.recoveredFolders.append(destination as URL) }
                } catch {
                    result.recoveredFolders.append(recovery)
                    result.failures.append(L("Files are recoverable in Cleanup Recovery") + ": " + recovery.path)
                }
            }
            progress(index + 1)
        }
        result.freeDelta = Self.freeSpace() - before
        return result
    }
    static func parentDescriptor(_ url: URL) throws -> Int32 {
        var fd = open("/", O_RDONLY | O_DIRECTORY)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        for component in url.deletingLastPathComponent().pathComponents.dropFirst() {
            let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            close(fd)
            guard next >= 0 else { throw POSIXError(.EACCES) }
            fd = next
        }
        return fd
    }
}
