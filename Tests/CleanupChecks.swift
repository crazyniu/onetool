// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

enum CleanupChecks {
    static func run(in parent: URL, check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        let path = parent.path.hasPrefix("/var/") ? "/private" + parent.path : parent.path
        let root = URL(fileURLWithPath: path).appendingPathComponent("cleanup-fixture")
        let cache = root.appendingPathComponent("Cache")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let outside = root.appendingPathComponent("personal.txt")
        try Data("preserve".utf8).write(to: outside)
        func write(_ name: String, old: Bool = true) throws -> URL {
            let file = cache.appendingPathComponent(name)
            try Data("cache".utf8).write(to: file)
            if old { try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 86400)], ofItemAtPath: file.path) }
            return file
        }
        let old = try write("old"), recent = try write("recent", old: false), busy = try write("busy")
        try fm.createSymbolicLink(at: cache.appendingPathComponent("linked"), withDestinationURL: outside)
        let hardlink = cache.appendingPathComponent("hardlink")
        try fm.linkItem(at: outside, to: hardlink)
        let rule = CleanupRule(id: "fixture", name: "Fixture", root: cache, category: .developer, bundleIDs: ["fixture.app"])
        let engine = CleanupEngine(rules: [rule], stagingRoot: root.appendingPathComponent("Recovery"))
        let scan = try engine.scan(openFiles: [busy.path], runningApps: [])
        check(scan.candidates.count == 1 && scan.candidates[0].files.map(\.url) == [old], "cleanup selects only old, closed, unlinked cache files")
        check(scan.candidates[0].occupiedBytes > scan.candidates[0].bytes, "cache occupancy includes recent and protected files separately from reclaimable bytes")
        let active = try engine.scan(openFiles: [], runningApps: ["fixture.app"])
        check(active.candidates.first?.files.isEmpty == true, "cleanup skips caches owned by running apps")
        check(active.candidates.first?.occupiedBytes == scan.candidates.first?.occupiedBytes, "running apps retain measured occupancy without becoming cleanable")
        let growing = try write("growing")
        let firstGrowth = try engine.scan(openFiles: [busy.path], runningApps: [])
        try Data(repeating: 0x61, count: 128 * 1024).write(to: growing)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 86400)], ofItemAtPath: growing.path)
        let secondGrowth = try engine.scan(openFiles: [busy.path], runningApps: [])
        check(secondGrowth.candidates[0].occupiedBytes > firstGrowth.candidates[0].occupiedBytes && secondGrowth.candidates[0].bytes > firstGrowth.candidates[0].bytes, "rescanning changed files refreshes occupancy and reclaimable capacity")
        try fm.removeItem(at: growing)
        let afterRemoval = try engine.scan(openFiles: [busy.path], runningApps: [])
        check(afterRemoval.candidates[0].occupiedBytes == scan.candidates[0].occupiedBytes, "rescanning removed files lowers cache occupancy")
        let disk = CleanupEngine.storage(at: root)
        check(disk != nil && disk!.total > 0 && disk!.available >= 0 && disk!.usedFraction >= 0 && disk!.usedFraction <= 1, "disk overview reads valid capacity from the actual fixture volume")
        check(CleanupStorage(total: 1000, available: 497).usedFraction == 0.503, "disk usage retains fractional precision rather than truncating to 50 percent")
        let result = try engine.clean(scan.candidates, permanent: true, openFiles: [], runningApps: [])
        check(result.processedFiles == 1 && !fm.fileExists(atPath: old.path), "selected cache deletion completes")
        let afterCleaning = try engine.scan(openFiles: [busy.path], runningApps: [])
        check(afterCleaning.candidates[0].occupiedBytes == scan.candidates[0].occupiedBytes - result.processedBytes && afterCleaning.candidates[0].bytes == 0, "cleanup followed by rescan refreshes totals while preserving protected files")
        check(fm.fileExists(atPath: recent.path) && fm.fileExists(atPath: busy.path) && (try? Data(contentsOf: outside)) == Data("preserve".utf8), "recent files, busy files and personal data survive cleanup")
        let changed = try write("changed")
        let before = try engine.scan(openFiles: [busy.path], runningApps: [])
        try Data("new content".utf8).write(to: changed)
        let stale = try engine.clean(before.candidates, permanent: true, openFiles: [], runningApps: [])
        check(stale.processedFiles == 0 && fm.fileExists(atPath: changed.path), "changed files are revalidated and skipped")
        let guarded = try write("guarded")
        let guardedScan = try engine.scan(openFiles: [busy.path], runningApps: [])
        let moved = root.appendingPathComponent("moved-cache")
        try fm.moveItem(at: cache, to: moved)
        try fm.createSymbolicLink(at: cache, withDestinationURL: moved)
        let refused = try engine.clean(guardedScan.candidates, permanent: true, openFiles: [], runningApps: [])
        check(refused.processedFiles == 0 && fm.fileExists(atPath: moved.appendingPathComponent(guarded.lastPathComponent).path), "replaced ancestor symlinks cannot redirect cleanup")
        try fm.removeItem(at: cache); try fm.moveItem(at: moved, to: cache)
        try fm.removeItem(at: hardlink)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 86400)], ofItemAtPath: outside.path)
        let outsider = CleanupCandidate(rule: rule, files: [CleanupEngine.snapshot(outside)!], skippedFiles: 0, note: nil)
        let forged = try engine.clean([outsider], permanent: true, openFiles: [], runningApps: [])
        check(forged.processedFiles == 0 && fm.fileExists(atPath: outside.path), "forged paths outside the rule are refused")
        let traversal = cache.appendingPathComponent("../personal.txt")
        let traversalCandidate = CleanupCandidate(rule: rule, files: [CleanupEngine.snapshot(traversal)!], skippedFiles: 0, note: nil)
        let traversed = try engine.clean([traversalCandidate], permanent: true, openFiles: [], runningApps: [])
        check(traversed.processedFiles == 0 && fm.fileExists(atPath: outside.path), "dot components cannot escape a cache rule")
        check(SuperRightClickFiles.suggestedName("personal.txt", in: root) == "personal 2.txt", "Finder suggests a new name for existing files")
        let recoverable = try write("recoverable")
        let trashCandidate = CleanupCandidate(rule: rule, files: [CleanupEngine.snapshot(recoverable)!], skippedFiles: 0, note: nil)
        let trashed = try engine.clean([trashCandidate], permanent: false, openFiles: [], runningApps: [])
        check(trashed.processedFiles == 1 && !fm.fileExists(atPath: recoverable.path), "default cleanup moves the selected fixture")
        if let recovery = trashed.recoveredFolders.first {
            check((try? Data(contentsOf: recovery.appendingPathComponent("Files/recoverable"))) == Data("cache".utf8), "trash contents remain recoverable")
            check(fm.fileExists(atPath: recovery.appendingPathComponent("1Tool-Recovery.json").path), "recovery manifest preserves the original path")
            // Remove only the UUID folder created by this fixture, never empty the user's Trash.
            try fm.removeItem(at: recovery)
        } else { check(false, "cleanup returns the recovery location") }
        let stopped = try engine.clean([trashCandidate], permanent: true, openFiles: [], runningApps: [], cancelled: { true })
        check(stopped.processedFiles == 0 && stopped.cancelled && stopped.outcome == .cancelled && stopped.remainingFiles == 1, "cleanup cancellation records unfinished work without claiming success")
        let unreadable = cache.appendingPathComponent("Private")
        try fm.createDirectory(at: unreadable, withIntermediateDirectories: true)
        try Data("private".utf8).write(to: unreadable.appendingPathComponent("data"))
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        let restricted = try engine.scan(openFiles: [], runningApps: [])
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: unreadable.path)
        check(restricted.incomplete && restricted.candidates.contains { $0.uninspectedPaths.contains(unreadable.path) }, "unreadable cache directories remain visible as incomplete scans")
        var limitedEngine = engine; limitedEngine.fileLimit = 1
        let limited = try limitedEngine.scan(openFiles: [], runningApps: [])
        check(limited.incomplete, "scan limits cannot produce an all-clear result")
        var discoveryRule = rule; discoveryRule.inspectionOnly = true
        let discoveryEngine = CleanupEngine(rules: [discoveryRule], stagingRoot: engine.stagingRoot)
        let protectedDiscovery = try discoveryEngine.clean([outsider], permanent: true, openFiles: [], runningApps: [])
        check(protectedDiscovery.processedFiles == 0, "discovery-only locations cannot be cleaned")
        var failed = CleanupResult(); failed.failures = ["fixture failure"]
        check(failed.outcome == .failed, "zero-processed failures are not reported as successful cleanup")
        failed.processedFiles = 1
        check(failed.outcome == .partial, "partial cleanup failures remain distinguishable")
        check(CleanupEngine.normalizedPath(URL(fileURLWithPath: "/var/folders/test")) == "/private/var/folders/test", "Darwin open-file aliases match cache paths")
        var cancelled = false
        do { _ = try engine.scan(openFiles: [], runningApps: [], cancelled: { true }) }
        catch is CancellationError { cancelled = true }
        check(cancelled, "cleanup scan cancellation is honored")
    }
}
