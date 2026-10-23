// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum UninstallChecks {
    static func run(in parent: URL, check: (Bool, String) -> Void) throws {
        let fm = FileManager.default
        let resolved = parent.resolvingSymlinksInPath().path
        let canonical = URL(fileURLWithPath: resolved.hasPrefix("/var/") ? "/private" + resolved : resolved).appendingPathComponent("uninstall-fixture")
        let home = canonical.appendingPathComponent("home")
        let apps = canonical.appendingPathComponent("Applications")
        try fm.createDirectory(at: home, withIntermediateDirectories: true)
        try fm.createDirectory(at: apps, withIntermediateDirectories: true)
        let engine = UninstallEngine(home: home, applicationRoots: [apps])
        func write(_ relative: String, _ data: String = "fixture") throws -> URL {
            let url = home.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(data.utf8).write(to: url)
            return url
        }
        func makeApp(_ name: String, id: String = "org.onetool.uninstall-fixture", root: URL? = nil) throws -> UninstallApp {
            let url = (root ?? apps).appendingPathComponent(name + ".app")
            let contents = url.appendingPathComponent("Contents")
            try fm.createDirectory(at: contents, withIntermediateDirectories: true)
            let plist = ["CFBundleIdentifier": id, "CFBundleName": name, "CFBundlePackageType": "APPL", "CFBundleShortVersionString": "1.0"]
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            try Data("executable fixture".utf8).write(to: contents.appendingPathComponent("payload"))
            guard let app = UninstallEngine.application(at: url) else {
                throw NSError(domain: "UninstallFixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid fixture: " + url.path + " safe=" + String(CleanupEngine.safeAncestors(url)) + " bundle=" + String(describing: Bundle(url: url)?.infoDictionary)])
            }
            return app
        }
        func refuses(_ title: String, _ body: () throws -> Void) {
            do { try body(); check(false, title) } catch { check(true, title) }
        }
        func removeRecovery(_ result: UninstallResult) throws {
            if let url = result.recoveryURL {
                check(url.lastPathComponent.hasPrefix("1Tool-Uninstall-"), "uninstaller recovery folder has its own UUID")
                try fm.removeItem(at: url)
            }
        }
        let app = try makeApp("Fixture App")
        let identifier = app.bundleID
        let resource = app.url.appendingPathComponent("Contents/Resources/en.lproj/InfoPlist.strings")
        try fm.createDirectory(at: resource.deletingLastPathComponent(), withIntermediateDirectories: true)
        let resourceData = Data("fixture resource".utf8)
        try resourceData.write(to: resource)
        let cache = try write("Library/Caches/\(identifier)/cache")
        let preferences = try write("Library/Preferences/\(identifier).plist")
        let named = try write("Library/Application Support/Fixture App/user-data")
        let shared = try write("Library/Group Containers/group.\(identifier)/shared-data")
        let vendor = try write("Library/Application Support/org.onetool/other-app-data")
        let unrelated = try write("Library/Caches/\(identifier).other/cache")
        let personal = try write("Documents/saved-work")
        let discovered = try engine.applications()
        check(discovered.count == 1 && discovered.first?.bundleID == app.bundleID, "uninstaller discovers top-level applications")
        let plan = try engine.scan(app, installed: discovered)
        check(Set(plan.items.map(\.url)) == Set([app.url, cache.deletingLastPathComponent(), preferences, named.deletingLastPathComponent()]), "uninstaller matches exact app identifiers and names without vendor or prefix matches")
        check(plan.items.first?.id == app.id && plan.items.first?.issue == nil, "application is first and inspectable")
        check(plan.items.first(where: { $0.url == named.deletingLastPathComponent() })?.nameMatch == true, "name matches carry an explicit ownership caveat")
        let all = Set(plan.items.map(\.id))
        let mapped = UninstallOpenFile(path: resource.path, pid: 123, command: "NotificationCenter", descriptor: "txt", access: " ")
        let readOnlyReference = UninstallActivity(openPaths: [resource.path], executablePaths: ["/System/Library/CoreServices/NotificationCenter.app/Contents/MacOS/NotificationCenter"], readOnlyPaths: [resource.path], references: [mapped])
        check(readOnlyReference.blockingProblem(for: app, items: plan.items) == nil,
              "a foreign process mapping a read-only app resource does not mean the app is running")
        let helper = UninstallActivity(executablePaths: [app.url.appendingPathComponent("Contents/Helpers/Worker").path])
        check(helper.blockingProblem(for: app, items: plan.items)?.kind == .running,
              "background executables inside the app still block removal without a GUI bundle identifier")
        let writer = UninstallActivity(openPaths: [resource.path], references: [.init(path: resource.path, pid: 456, command: "FixtureWriter", descriptor: "5", access: "w")])
        check(writer.blockingProblem(for: app, items: plan.items)?.kind == .inUse
              && writer.blockingProblem(for: app, items: plan.items)?.detail.contains("456") == true,
              "app bundle writers remain protected and identify the blocking process")
        let dataReader = UninstallActivity(openPaths: [cache.path], readOnlyPaths: [cache.path], references: [.init(path: cache.path, pid: 789, command: "FixtureReader", descriptor: "4", access: "r")])
        check(dataReader.blockingProblem(for: app, items: plan.items)?.kind == .inUse,
              "read-only access to selected app data is still protected with a file-in-use reason")
        let unknownReference = UninstallActivity(openPaths: [resource.path])
        check(unknownReference.blockingProblem(for: app, items: plan.items)?.kind == .inUse,
              "unknown file access remains protected rather than being assumed harmless")
        let nulFields = ["p123", "cNotificationCenter", "ftxt", "a ", "n" + resource.path, "\np456", "cFixtureWriter", "f5", "aw", "n" + resource.path + "\nsecond-line"]
        let parsed = UninstallActivity.parseOpenFiles(Data((nulFields.joined(separator: "\0") + "\0\n").utf8))
        check(parsed.count == 2 && parsed[0] == mapped && parsed[1].access == "w" && parsed[1].path.hasSuffix("\nsecond-line"),
              "NUL-delimited lsof parsing preserves owners, access modes and newlines in paths")
        let forgedItem = UninstallItem(url: personal, category: "Application Data", nameMatch: false, stamps: plan.items[0].stamps, bytes: 0, issue: nil)
        let forgedPlan = UninstallPlan(app: app, items: [plan.items[0], forgedItem], warnings: [])
        refuses("forged plan paths cannot escape the discovery allowlist") {
            _ = try engine.uninstall(forgedPlan, selected: [app.id, personal.path], installed: discovered, activity: { .init() })
        }
        refuses("running app blocks uninstall") {
            _ = try engine.uninstall(plan, selected: all, installed: discovered, activity: { .init(bundleIDs: [identifier]) })
        }
        refuses("open related data blocks uninstall") {
            _ = try engine.uninstall(plan, selected: all, installed: discovered, activity: { .init(openPaths: [cache.path]) })
        }
        refuses("missing process inspection fails closed") {
            _ = try engine.uninstall(plan, selected: all, installed: discovered, activity: { throw CocoaError(.fileReadNoPermission) })
        }
        let cancelled = try engine.uninstall(plan, selected: all, installed: discovered, activity: { .init() }, cancelled: { true })
        check(cancelled.cancelled && cancelled.moved.isEmpty && fm.fileExists(atPath: app.id), "cancellation preserves all files")
        refuses("data-only and forged selections are refused") {
            _ = try engine.uninstall(plan, selected: [personal.path], installed: discovered, activity: { .init() })
        }
        try Data("updated app".utf8).write(to: app.url.appendingPathComponent("Contents/payload"))
        let stale = try engine.uninstall(plan, selected: all, installed: discovered, activity: { .init() })
        check(stale.moved.isEmpty && !stale.failures.isEmpty && fm.fileExists(atPath: cache.path), "changed app stops uninstall before any app data moves")
        let fresh = try engine.scan(app, installed: discovered)
        let resourceHandle = try FileHandle(forReadingFrom: resource)
        defer { try? resourceHandle.close() }
        let observed = try UninstallActivity.live()
        check(observed.readOnlyPaths.contains(resource.path) && observed.blockingProblem(for: app, items: [fresh.appItem!]) == nil,
              "real lsof classifies a read-only foreign resource handle as non-blocking for the app bundle")
        let appOnly = try engine.uninstall(fresh, selected: [app.id], installed: discovered, activity: { try .live() })
        check(try resourceHandle.readToEnd() == resourceData,
              "an existing read-only resource handle remains valid after moving the fixture app to Trash")
        try resourceHandle.close()
        check(appOnly.moved == [app.url] && !fm.fileExists(atPath: app.id), "application-only uninstall moves the app")
        check(fm.fileExists(atPath: cache.path) && fm.fileExists(atPath: preferences.path) && fm.fileExists(atPath: named.path), "unselected app data remains unchanged")
        check(appOnly.inTrash && appOnly.failures.isEmpty, "uninstaller uses the real macOS Trash successfully")
        let recovery = appOnly.recoveryURL!
        check(fm.fileExists(atPath: recovery.appendingPathComponent("000-Fixture App.app/Contents/payload").path), "uninstalled app remains recoverable")
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: recovery.appendingPathComponent("1Tool-Uninstall-Recovery.json"))) as! [String: Any]
        let manifestItems = manifest["items"] as! [[String: String]]
        check(manifestItems.first?["original"] == app.id, "recovery manifest records exact original paths")
        try removeRecovery(appOnly)

        let app2 = try makeApp("Fixture App")
        let plan2 = try engine.scan(app2, installed: [app2])
        let full = try engine.uninstall(plan2, selected: Set(plan2.items.map(\.id)), installed: [app2], activity: { .init() })
        check(full.moved.count == plan2.items.count && full.failures.isEmpty, "full uninstall moves selected app and data together")
        check([cache, preferences, named].allSatisfy { !fm.fileExists(atPath: $0.path) }, "selected data is moved")
        check([shared, vendor, unrelated, personal].allSatisfy { fm.fileExists(atPath: $0.path) }, "shared groups, vendor folders, prefix matches and documents survive")
        try removeRecovery(full)

        let app3 = try makeApp("Fixture App")
        _ = try write("Library/Caches/\(identifier)/cache")
        let copy = try makeApp("Fixture Copy")
        let duplicate = try engine.scan(app3, installed: [app3, copy])
        check(duplicate.items.count == 1 && !duplicate.warnings.isEmpty, "another installed copy protects shared identifier data")
        let unique = try engine.scan(app3, installed: [app3])
        refuses("a copy installed after preview blocks data removal") {
            _ = try engine.uninstall(unique, selected: Set(unique.items.map(\.id)), installed: [app3, copy], activity: { .init() })
        }
        let rootCache = cache.deletingLastPathComponent()
        try fm.removeItem(at: rootCache)
        try fm.createSymbolicLink(at: rootCache, withDestinationURL: personal.deletingLastPathComponent())
        let linked = try engine.scan(app3, installed: [app3])
        check(linked.items.first(where: { $0.id == rootCache.path })?.issue != nil, "linked data roots are protected")
        let staleLink = try engine.uninstall(unique, selected: Set(unique.items.map(\.id)), installed: [app3], activity: { .init() })
        check(!staleLink.failures.isEmpty && fm.fileExists(atPath: personal.path), "post-scan symlinks cannot redirect removal")
        try removeRecovery(staleLink)
        let system = try makeApp("System", id: "com.apple.test")
        let selfApp = try makeApp("1Tool", id: "com.shopkivoo.onetool")
        let nested = try makeApp("Nested", root: system.url.appendingPathComponent("Contents"))
        check([system, selfApp, nested].allSatisfy { engine.protection(for: $0) != nil }, "system, self and nested apps are protected")
        let systemPlan = try engine.scan(system, installed: [system])
        refuses("engine refuses system app removal even with a forged selection") {
            _ = try engine.uninstall(systemPlan, selected: [system.id], installed: [system], activity: { .init() })
        }
        check(systemPlan.appItem?.problem?.kind == .protected && systemPlan.appItem?.stamps.isEmpty == true, "protected applications have an explicit reason and are never scanned or selected")
        let readDenied = UninstallProblem.capture(POSIXError(.EACCES), at: personal)
        check(readDenied.kind == .permission && readDenied.url == personal && readDenied.detail.contains(NSPOSIXErrorDomain), "permission failures retain the precise path and original error")
        let disappeared = UninstallProblem.capture(POSIXError(.ENOENT), at: personal)
        check(disappeared.kind == .changed, "disappeared files are distinguished from permission failures")
        let unknown = UninstallProblem.capture(POSIXError(.EIO), at: personal)
        check(unknown.kind == .unavailable, "I/O failures are not presented as missing privacy permission")
        let limitedApp = try makeApp("Limited App", id: "org.onetool.limited-fixture")
        var limitedEngine = engine
        limitedEngine.fileLimit = 1
        let limitedPlan = try limitedEngine.scan(limitedApp, installed: [limitedApp])
        check(limitedPlan.appItem?.problem?.kind == .limit && limitedPlan.appItem?.problem?.url.path == limitedApp.id,
              "scan limits retain an unselectable item with the affected path")
        check(linked.items.first(where: { $0.id == rootCache.path })?.problem?.kind == .linked,
              "symbolic link protection is distinguished from permission denial")
        check(stale.problems.first?.kind == .changed, "changed files retain a structured retry reason in removal results")
        let inaccessibleFile = try write("Library/Caches/\(limitedApp.bundleID)/restricted/private-cache")
        let inaccessibleDirectory = inaccessibleFile.deletingLastPathComponent()
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: inaccessibleDirectory.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inaccessibleDirectory.path) }
        let deniedPlan = try engine.scan(limitedApp, installed: [limitedApp])
        let blockedCache = deniedPlan.items.first { $0.category == "App Caches" }
        check(blockedCache?.problem?.kind == .permission && blockedCache?.issue != nil && blockedCache?.stamps.isEmpty == true,
              "real unreadable cache directories are retained as blocked items rather than absent data")
        check(blockedCache?.problem?.url.path.hasPrefix(inaccessibleDirectory.path) == true,
              "real permission errors identify the exact unreadable subdirectory")
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inaccessibleDirectory.path)
        let linkedRoot = canonical.appendingPathComponent("linked-applications")
        try fm.createSymbolicLink(at: linkedRoot, withDestinationURL: apps)
        let blockedInventory = try UninstallEngine(home: home, applicationRoots: [linkedRoot]).inventory()
        check(blockedInventory.apps.isEmpty && blockedInventory.problems.first?.kind == .linked,
              "unscanned application roots remain visible as incomplete inventory")
        let deniedRoot = canonical.appendingPathComponent("unreadable-applications")
        try fm.createDirectory(at: deniedRoot, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o000])
        defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedRoot.path) }
        let unreadableInventory = try UninstallEngine(home: home, applicationRoots: [deniedRoot]).inventory()
        check(unreadableInventory.apps.isEmpty && unreadableInventory.problems.first?.kind == .permission,
              "an unreadable app inventory is reported as incomplete rather than empty")
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: deniedRoot.path)
        let systemApp = try makeApp("System Trash Fixture", id: "org.onetool.native-trash-fixture")
        let systemData = try write("Library/Caches/\(systemApp.bundleID)/cache").deletingLastPathComponent()
        let nativePlan = try engine.scan(systemApp, installed: [systemApp])
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: apps.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps.path) }
        var nativeRequestedURL: URL?
        let cancelledSystem = try engine.uninstall(nativePlan, selected: Set(nativePlan.items.map(\.id)), installed: [systemApp], activity: { .init() }, applicationTrash: { url in
            nativeRequestedURL = url
            throw CocoaError(.userCancelled)
        })
        check(nativeRequestedURL == systemApp.url, "system authorization receives only the selected app")
        check(cancelledSystem.cancelled && fm.fileExists(atPath: systemApp.id) && fm.fileExists(atPath: systemData.path), "declining system Trash leaves app and data intact")
        var nativeDestination: URL?
        let systemResult = try engine.uninstall(nativePlan, selected: Set(nativePlan.items.map(\.id)), installed: [systemApp], activity: { .init() }, applicationTrash: { url in
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: apps.path)
            var destination: NSURL?
            try fm.trashItem(at: url, resultingItemURL: &destination)
            nativeDestination = destination as URL?
            return nativeDestination!
        })
        check(systemResult.problems.isEmpty && Set(systemResult.moved) == Set([systemApp.url, systemData]), "native app Trash fallback permits selected data only after the app moves")
        let manifestData = try Data(contentsOf: systemResult.recoveryURL!.appendingPathComponent("1Tool-Uninstall-Recovery.json"))
        let nativeManifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        let entries = nativeManifest["items"] as! [[String: String]]
        check(entries.first?["trashed"] == nativeDestination?.path && entries.first?["stored"] == nil, "recovery manifest records the native Trash destination")
        if let nativeDestination { try fm.removeItem(at: nativeDestination) }
        try removeRecovery(systemResult)
        var didCancel = false
        do { _ = try engine.scan(system, installed: [], cancelled: { true }) } catch is CancellationError { didCancel = true }
        check(didCancel, "application scanning honors cancellation")
    }
}
