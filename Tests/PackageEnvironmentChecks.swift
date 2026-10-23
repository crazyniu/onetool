// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

enum PackageEnvironmentChecks {
    static func run(in parent: URL, check: (Bool, String) -> Void) throws {
        let home = parent.appendingPathComponent("node-environment-fixture")
        let roots = [home.appendingPathComponent(".nvm/versions/node/v20.0.0"), home.appendingPathComponent(".local/share/fnm/node-versions/v24.0.0/installation")]
        let fm = FileManager.default
        let log = home.appendingPathComponent("node-used")
        for (index, root) in roots.enumerated() {
            let bin = root.appendingPathComponent("bin"), cli = root.appendingPathComponent("lib/node_modules/npm/bin/npm-cli.js")
            try fm.createDirectory(at: bin, withIntermediateDirectories: true)
            try fm.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
            let node = "#!/bin/sh\nif [ \"$1\" = --version ]; then printf 'v\(index == 0 ? "20.0.0" : "24.0.0")'; exit 0; fi\n[ -z \"${BINDING_LOG:-}\" ] || printf '%s\\n' \"$0\" >> \"$BINDING_LOG\"\nexec /bin/sh \"$@\"\n"
            try node.write(to: bin.appendingPathComponent("node"), atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: bin.appendingPathComponent("node").path)
            let script = #"""
            #!/bin/sh
            set -eu
            prefix=$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)
            if [ "$1" = --prefix ]; then prefix="$2"; shift 2; fi
            case "$1" in
              prefix) printf '%s' "$prefix" ;;
              --version) printf '11.0.0' ;;
              ls) printf '{"dependencies":{"fixture":{"version":"1.0.0"}}}' ;;
              install) printf 'selected-prefix=%s' "$prefix" ;;
              *) exit 2 ;;
            esac
            """#
            try script.write(to: cli, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
            try fm.createSymbolicLink(at: bin.appendingPathComponent("npm"), withDestinationURL: cli)
        }
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/bin:/bin"; env["BINDING_LOG"] = log.path
        let candidates = PackageEnvironmentCatalog.candidateExecutables(home: home, environment: env).filter {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().path.hasPrefix(home.resolvingSymlinksInPath().path + "/")
        }
        check(candidates.count == 2, "nvm and fnm runtimes are discovered even when npm is absent from PATH")
        let catalog = try PackageEnvironmentCatalog.inspect(candidates: candidates + [candidates[0]], environment: env, home: home)
        check(catalog.environments.count == 2 && catalog.warnings.isEmpty, "separate runtime prefixes survive discovery and aliases are deduplicated")
        for entry in catalog.environments {
            check(entry.engine.prefix?.hasPrefix(home.resolvingSymlinksInPath().path) == true && entry.engine.nodeExecutable != nil, "environment records canonical prefix and paired node")
            let inventory = try entry.engine.inventory()
            check(inventory.packages.map(\.name) == ["fixture"], "bound environment reads its own global inventory")
        }
        let first = catalog.environments[0].engine
        let second = catalog.environments[1].engine
        try Data().write(to: log)
        let command = try first.terminalCommand(for: .install, name: "fixture", kind: .npm)
        var poisoned = env
        poisoned["PATH"] = URL(fileURLWithPath: second.nodeExecutable!).deletingLastPathComponent().path + ":/usr/bin:/bin"
        let copied = try PackageProcess.run("/bin/sh", ["-c", command], environment: poisoned)
        try copied.requireSuccess()
        let used = try String(contentsOf: log, encoding: .utf8)
        check(used.contains(first.nodeExecutable!) && !used.contains(second.nodeExecutable!), "copied recovery command preserves paired node despite a different Terminal PATH")
        check(copied.output.contains(first.prefix!), "copied recovery command preserves the selected global prefix")
        let brokenCLI = home.appendingPathComponent("partial-npm")
        let brokenScript = #"""
        #!/bin/sh
        printf '{"dependencies":{"healthy":{"version":"1.0.0"},"broken":{"version":"2.0.0"}},"error":{"code":"ELSPROBLEMS","summary":"invalid dependency"},"problems":["invalid: nested dependency"]}'
        printf 'npm error code ELSPROBLEMS' >&2
        exit 1
        """#
        try brokenScript.write(to: brokenCLI, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brokenCLI.path)
        let partial = try PackageEngine(provider: .npm, executable: brokenCLI.path, environment: env).inventory()
        check(partial.packages.count == 2 && partial.warning?.contains("invalid dependency") == true, "ELSPROBLEMS preserves available packages with an explicit warning")
        let bunManifest = home.appendingPathComponent(".bun/install/global/package.json")
        try fm.createDirectory(at: bunManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"dependencies":{"top-level-tool":"1.0.0"}}"#.utf8).write(to: bunManifest)
        let summaries = PackageEnvironmentCatalog.otherManagerSummaries(home: home)
        check(summaries.count == 1 && summaries[0].contains("top-level-tool"), "other manager inventory uses root manifests rather than flattened transitive dependencies")
        check(PackageUpdateState.cached(.now).isKnown && !PackageUpdateState.notChecked.isKnown, "real local Homebrew metadata is known and distinct from unchecked inventory")
    }
}
