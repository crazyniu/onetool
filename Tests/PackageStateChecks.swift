// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main @MainActor struct PackageStateChecks {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("onetool-package-states-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = root.appendingPathComponent("fixture npm")
        let script = #"""
        #!/bin/sh
        set -eu
        case "$1" in
          ls) printf '{"dependencies":{"alpha":{"version":"1.0.0"},"beta":{"version":"1.0.0"}}}' ;;
          info) printf '{"formulae":[{"name":"alpha","installed":[{"version":"1.0.0"}],"versions":{"stable":"2.0.0"},"outdated":true}],"casks":[]}' ;;
          outdated)
            if [ -f "$FIXTURE_ROOT/fail-check" ]; then printf '{"error":{"code":"E401","summary":"npm error E401 need auth"}}'; exit 1; fi
            if [ -f "$FIXTURE_ROOT/has-updates" ]; then printf '{"alpha":{"latest":"2.0.0"},"beta":{"latest":"2.0.0"}}'; exit 1; fi
            printf '{}' ;;
          install|uninstall)
            sleep 0.3
            if [ -f "$FIXTURE_ROOT/fail-operation" ] && [ "$4" = "beta@latest" ]; then printf 'sudo: a terminal is required to read the password' >&2; exit 1; fi
            printf 'operation finished' ;;
          *) exit 2 ;;
        esac
        """#
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        var env = ProcessInfo.processInfo.environment; env["FIXTURE_ROOT"] = root.path
        let engine = PackageEngine(provider: .npm, executable: cli.path, environment: env)
        let manager = PackageManager(.npm, engine: engine, automaticallyCheckUpdates: false)
        var count = 0
        func check(_ okay: Bool, _ label: String) {
            guard okay else { fatalError("FAIL: " + label) }
            count += 1; print("PASS: " + label)
        }
        func idle() async throws {
            let deadline = Date().addingTimeInterval(10)
            while manager.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            check(!manager.busy, "async package operation finishes")
        }
        func flag(_ name: String) throws { try Data().write(to: root.appendingPathComponent(name)) }
        check(manager.updateState == .notChecked && manager.checkedAt == nil, "initial updates are unknown")
        manager.refresh(); try await idle()
        check(manager.loaded && manager.packages.count == 2 && manager.upgradable.isEmpty && !manager.updateState.isKnown, "inventory does not establish update availability")
        manager.checkUpdates()
        check(manager.updateState == .checking && !manager.canManage, "update check exposes checking state")
        try await idle()
        check(manager.updateState.isKnown && manager.checkedAt != nil && manager.upgradable.isEmpty, "successful empty check is explicitly known with timestamp")
        try flag("has-updates")
        manager.checkUpdates(); try await idle()
        check(manager.upgradable.count == 2, "successful check enables exactly detected upgrades")
        try flag("fail-check")
        manager.checkUpdates(); try await idle()
        check(manager.updateState == .failed && manager.checkedAt == nil && manager.upgradable.isEmpty && manager.issue?.kind == .registryAuthentication, "failed check invalidates stale results and classifies registry authentication")
        manager.refresh()
        check(manager.updateState == .notChecked && manager.issue == nil, "refresh immediately invalidates update results and old errors")
        try await idle()
        try FileManager.default.removeItem(at: root.appendingPathComponent("fail-check"))
        manager.checkUpdates(); try await idle()
        let pending = PackageRequest(action: .upgrade, packages: manager.upgradable)
        try flag("fail-operation")
        manager.perform(pending)
        check(manager.busy && manager.activePackageID == pending.packages[0].id && manager.operationCount == 2, "batch operation exposes current package and total before yielding")
        try await Task.sleep(for: .milliseconds(150))
        check(manager.outcomes[pending.packages[0].id] == .running && manager.completedCount == 0, "running row progress is observable during CLI execution")
        try await idle()
        check(manager.completedCount == 1 && manager.outcomes[pending.packages[0].id] == .completed && manager.outcomes[pending.packages[1].id] == .failed, "partial failure retains exact completed and failed row states")
        check(manager.issue?.kind == .administrator && manager.loaded && manager.canManage && manager.activePackageID == nil, "administrator failure keeps inventory refreshed and ends busy state")
        check(manager.lastFailedRequest?.packages.map(\.name) == ["beta"], "retry excludes already completed packages and requires a new confirmation")
        check(manager.terminalCommand?.contains("'beta@latest'") == true && manager.terminalCommand?.contains("'" + cli.path + "'") == true, "manual recovery command quotes the selected executable and failed package")
        try FileManager.default.removeItem(at: root.appendingPathComponent("fail-operation"))
        manager.perform(manager.lastFailedRequest!); try await idle()
        check(manager.issue == nil && manager.lastFailedRequest == nil && manager.completedCount == 1 && manager.updateState == .notChecked, "confirmed retry succeeds and invalidates old update data")
        let automatic = PackageManager(.npm, engine: engine)
        automatic.refresh()
        let automaticDeadline = Date().addingTimeInterval(10)
        while automatic.busy && Date() < automaticDeadline { try await Task.sleep(for: .milliseconds(20)) }
        check(automatic.updateState.isKnown && automatic.upgradable.count == 2, "npm automatically checks updates after loading its inventory")
        let brew = PackageManager(.brew, engine: PackageEngine(provider: .brew, executable: cli.path, environment: env))
        brew.refresh()
        let brewDeadline = Date().addingTimeInterval(10)
        while brew.busy && Date() < brewDeadline { try await Task.sleep(for: .milliseconds(20)) }
        check(brew.updateState.isKnown && brew.upgradable.count == 1, "initial Homebrew inventory immediately exposes real locally known upgrades")
        brew.checkUpdates()
        let failedBrewDeadline = Date().addingTimeInterval(10)
        while brew.busy && Date() < failedBrewDeadline { try await Task.sleep(for: .milliseconds(20)) }
        check(brew.issue != nil && brew.updateState.isKnown && brew.upgradable.count == 1, "failed remote Homebrew update preserves known local upgrades with an error")
        let changedEnvironment = PackageRequest(action: .upgrade, packages: automatic.upgradable, environmentID: "different-environment")
        automatic.perform(changedEnvironment)
        check(!automatic.busy && automatic.issue != nil && automatic.activePackageID == nil, "confirmation for a different environment cannot execute")
        let writable = PackageIssue.classify("npm error code EACCES\nnpm error path /opt/homebrew/lib/node_modules/tool")
        check(writable.kind == .directoryAccess && writable.path == "/opt/homebrew/lib/node_modules/tool", "directory denial retains actual reported path")
        check(PackageIssue.classify("EPERM: operation not permitted").kind == .directoryAccess, "EPERM remains file access rather than inferred privacy authorization")
        check(PackageIssue.classify("npm error E403 permission denied").kind == .registryAuthentication, "registry denial is distinguished from directory ownership")
        check(PackageIssue.classify("curl: Could not resolve host: example.org").kind == .network, "network failure has independent recovery guidance")
        check(PackageIssue.classify("unknown diagnostic").kind == .other, "unknown CLI errors remain undiagnosed")
        let quoted = try PackageEngine(provider: .npm, executable: "/tmp/Node's bin/npm", environment: [:]).terminalCommand(for: .install, name: "alpha", kind: .npm)
        check(quoted.contains("'/tmp/Node'\\''s bin/npm'"), "recovery commands escape apostrophes in custom executable paths")
        print("PASS: \(count) package state checks")
    }
}
