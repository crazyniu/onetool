// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum PackageChecks {
    static func run(in root: URL, check: (Bool, String) -> Void) throws {
        for name in ["wget", "node@22", "homebrew/cask/firefox", "foo.bar", "gtk+3"] {
            check(PackageEngine.validName(name, kind: .formula), "brew accepts package identifier: " + name)
        }
        for name in ["typescript", "@scope/package", "npm", "foo.bar"] {
            check(PackageEngine.validName(name, kind: .npm), "npm accepts package identifier: " + name)
        }
        for name in ["", "--force", "-g", "../pkg", "/tmp/pkg", "https://example.org/pkg", "foo bar", "foo;touch /tmp/oops", "$(id)", "foo\nbar", "foo\n", "foo\0bar", "foo/../bar", String(repeating: "a", count: 215)] {
            check(!PackageEngine.validName(name, kind: .formula) && !PackageEngine.validName(name, kind: .npm), "reject unsafe package specification: " + name.debugDescription)
        }
        check(!PackageEngine.validName("foo@latest", kind: .npm) && !PackageEngine.validName("@scope/pkg@1.0", kind: .npm), "npm accepts names only, with upgrade target supplied by the app")
        let brewJSON = Data(#"{"formulae":[{"name":"tool","full_name":"owner/tap/tool","installed":[{"version":"1.0_1"},{"version":"1.1"}],"versions":{"stable":"2.0"},"outdated":true,"pinned":true},{"name":"head","installed":[{"version":"HEAD-123"}],"versions":{"stable":null},"outdated":false}],"casks":[{"token":"tool","full_token":"owner/apps/tool","installed":"3.0","version":"4.0","outdated":true}]}"#.utf8)
        let packages = try PackageEngine.parseInstalled(brewJSON, provider: .brew)
        check(packages.count == 3 && Set(packages.map(\.id)).count == 3, "formula and cask retain separate stable identities")
        check(packages.contains { $0.name == "owner/tap/tool" && $0.version == "1.0_1, 1.1" && $0.pinned && $0.outdated }, "brew preserves taps, installed revisions and pinned state")
        check(packages.contains { $0.kind == .cask && $0.version == "3.0" && $0.latest == "4.0" }, "cask uses installed version rather than available version")
        let npmJSON = Data(#"{"dependencies":{"@scope/pkg":{"version":"1.0.0"},"empty":{},"tool":{"version":"2.0.0"}}}"#.utf8)
        let npmPackages = try PackageEngine.parseInstalled(npmJSON, provider: .npm)
        check(npmPackages.count == 3 && npmPackages.first?.name == "@scope/pkg", "npm parses scoped packages and handles missing version")
        let updated = try PackageEngine.applyingNpmUpdates(Data(#"{"@scope/pkg":{"current":"1.0.0","wanted":"1.2.0","latest":"2.0.0"},"tool":{"current":"2.0.0","latest":"2.0.0"}}"#.utf8), to: npmPackages)
        check(updated.first?.latest == "2.0.0" && updated.filter(\.outdated).count == 1, "npm upgrades to latest including major versions")
        let cleared = try PackageEngine.applyingNpmUpdates(Data("{}".utf8), to: updated)
        check(cleared.allSatisfy { !$0.outdated && $0.latest == nil }, "empty outdated response clears stale update indicators")
        var rejected = false
        do { _ = try PackageEngine.applyingNpmUpdates(Data(#"{"error":{"code":"E401","summary":"Auth required"}}"#.utf8), to: npmPackages) } catch { rejected = true }
        check(rejected, "registry errors cannot appear as an up-to-date result")
        rejected = false
        do { _ = try PackageEngine.parseInstalled(Data("garbage".utf8), provider: .brew) } catch { rejected = true }
        check(rejected, "malformed package output is reported")
        let brew = PackageEngine(provider: .brew, executable: "/fixture/brew", environment: [:])
        let npm = PackageEngine(provider: .npm, executable: "/fixture/npm", environment: [:])
        for action in [PackageAction.install, .uninstall, .upgrade] {
            for kind in [PackageKind.formula, .cask] {
                let args = try brew.arguments(for: action, name: "owner/tap/tool", kind: kind)
                check(args == [action.rawValue, "--" + kind.rawValue, "--", "owner/tap/tool"], "brew " + action.rawValue + " explicitly selects " + kind.rawValue)
            }
        }
        let install = try npm.arguments(for: .install, name: "@scope/pkg", kind: .npm)
        let uninstall = try npm.arguments(for: .uninstall, name: "@scope/pkg", kind: .npm)
        let upgrade = try npm.arguments(for: .upgrade, name: "@scope/pkg", kind: .npm)
        check(install == ["install", "--global", "--", "@scope/pkg"] && uninstall == ["uninstall", "--global", "--", "@scope/pkg"], "npm install and uninstall are limited to named global packages")
        check(upgrade == ["install", "--global", "--", "@scope/pkg@latest"], "npm upgrade command matches displayed latest target")
        rejected = false
        do { _ = try brew.arguments(for: .uninstall, name: "npm", kind: .npm) } catch { rejected = true }
        check(rejected, "cross-provider requests cannot reach a CLI")
        let env = ProcessInfo.processInfo.environment
        let output = try PackageProcess.run("/bin/sh", ["-c", "printf '{\"ok\":true}'; printf 'warning' >&2"], environment: env)
        check(output.status == 0 && String(decoding: output.stdout, as: UTF8.self) == "{\"ok\":true}" && output.stderr == "warning", "CLI JSON stays separate from stderr warnings")
        let large = try PackageProcess.run("/bin/sh", ["-c", "i=0; while [ $i -lt 6000 ]; do printf '1234567890'; printf 'abcdefghij' >&2; i=$((i+1)); done"], environment: env)
        check(large.stdout.count == 60_000 && large.stderr.count == 60_000, "both output streams drain without truncation or deadlock")
        let nonzero = try PackageProcess.run("/bin/sh", ["-c", "printf '{}'; exit 1"], environment: env)
        try nonzero.requireSuccess(allowing: [0, 1])
        rejected = false
        do { try nonzero.requireSuccess() } catch { rejected = true }
        check(rejected, "exit 1 is accepted only by the npm outdated caller")
        let started = Date()
        rejected = false
        do { _ = try PackageProcess.run("/bin/sleep", ["5"], environment: env, timeout: 0.15) } catch { rejected = true }
        check(rejected && Date().timeIntervalSince(started) < 3, "hung CLI times out without blocking the UI")

        // Execute the complete command pipeline against a disposable Homebrew fixture.
        let fixture = root.appendingPathComponent("package-fixture")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: false)
        let cli = fixture.appendingPathComponent("brew")
        let script = #"""
        #!/bin/sh
        set -eu
        state="$FIXTURE_ROOT/state"
        printf '%s\n' "$*" >> "$FIXTURE_ROOT/commands"
        case "$1" in
          install) printf '1.0' > "$state" ;;
          upgrade) printf '2.0' > "$state" ;;
          uninstall) rm -f "$state" ;;
          info)
            if [ -f "$state" ]; then
              version=$(cat "$state")
              printf '{"formulae":[{"name":"fixture","installed":[{"version":"%s"}],"versions":{"stable":"2.0"},"outdated":false}],"casks":[]}' "$version"
            else
              printf '{"formulae":[],"casks":[]}'
            fi ;;
          *) exit 2 ;;
        esac
        """#
        try script.write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        var fixtureEnv = env; fixtureEnv["FIXTURE_ROOT"] = fixture.path
        let fixtureEngine = PackageEngine(provider: .brew, executable: cli.path, environment: fixtureEnv)
        try fixtureEngine.perform(.install, name: "fixture", kind: .formula, output: { _ in })
        var current = try fixtureEngine.installed()
        check(current.first?.version == "1.0", "brew fixture install is visible after refresh")
        try fixtureEngine.perform(.upgrade, name: "fixture", kind: .formula, output: { _ in })
        current = try fixtureEngine.installed()
        check(current.first?.version == "2.0", "brew fixture upgrade is visible after refresh")
        try fixtureEngine.perform(.uninstall, name: "fixture", kind: .formula, output: { _ in })
        current = try fixtureEngine.installed()
        check(current.isEmpty, "brew fixture uninstall disappears after refresh")
        let commands = try String(contentsOf: fixture.appendingPathComponent("commands"), encoding: .utf8)
        check(!commands.contains("--force") && !commands.contains("--zap") && !commands.contains("--ignore-dependencies"), "brew operations preserve normal dependency and data protections")
    }
}
