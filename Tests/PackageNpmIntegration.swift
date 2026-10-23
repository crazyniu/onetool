// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Uses a loopback fixture registry and a disposable npm global prefix.
@main struct PackageNpmIntegration {
    static func main() throws {
        let env = ProcessInfo.processInfo.environment
        let engine = PackageEngine(provider: .npm, executable: env["ONETOOL_TEST_NPM"]!, environment: env)
        func check(_ okay: Bool, _ label: String) {
            guard okay else { print("FAIL: " + label); exit(1) }
            print("PASS: " + label)
        }
        try engine.perform(.install, name: "onetool-fixture", kind: .npm, output: { print($0, terminator: "") })
        var packages = try engine.installed()
        check(packages.count == 1 && packages[0].version == "1.0.0", "real npm installs only into disposable global prefix")
        let registry = URL(string: env["npm_config_registry"]!)!
        _ = try Data(contentsOf: registry.appendingPathComponent("advance"))
        packages = try engine.updates(packages)
        check(packages[0].outdated && packages[0].latest == "2.0.0", "real npm outdated exit 1 identifies major upgrade")
        try engine.perform(.upgrade, name: "onetool-fixture", kind: .npm, output: { print($0, terminator: "") })
        packages = try engine.installed()
        check(packages.count == 1 && packages[0].version == "2.0.0", "real npm upgrade installs latest into disposable prefix")
        try engine.perform(.uninstall, name: "onetool-fixture", kind: .npm, output: { print($0, terminator: "") })
        packages = try engine.installed()
        check(packages.isEmpty, "real npm uninstall removes fixture from disposable prefix")
        var failed = false
        do { try engine.perform(.install, name: "missing-fixture", kind: .npm, output: { _ in }) } catch { failed = true }
        packages = try engine.installed()
        check(failed && packages.isEmpty, "real npm registry failure is reported and leaves package list accurate")
    }
}
