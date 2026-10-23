// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

struct PackageEnvironment: Identifiable, Sendable {
    let engine: PackageEngine
    let npmVersion: String
    let nodeVersion: String
    var id: String { URL(fileURLWithPath: engine.executable).resolvingSymlinksInPath().path + "|" + (engine.prefix ?? "") }
    var title: String { "Node \(nodeVersion) · npm \(npmVersion) · \(engine.prefix ?? engine.executable)" }
}

struct PackageEnvironmentCatalog: Sendable {
    let environments: [PackageEnvironment]
    let warnings: [String]
    let otherManagers: [String]

    static func discover(override: String? = nil, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Self {
        let base = try PackageEngine.discover(.npm, override: override)
        var environment = base?.environment ?? PackageEngine.commandEnvironment(ProcessInfo.processInfo.environment)
        // Capture only tool-location and network variables used by the login shell.
        // Values stay inside child-process environments and are never printed.
        let keys = ["PATH", "NVM_DIR", "FNM_DIR", "VOLTA_HOME", "ASDF_DATA_DIR", "MISE_DATA_DIR", "npm_config_prefix", "NPM_CONFIG_PREFIX", "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "all_proxy", "no_proxy"]
        let script = "for key in " + keys.joined(separator: " ") + "; do value=${(P)key}; [[ -n $value ]] && printf '%s=%s\\0' \"$key\" \"$value\"; done; true"
        if let result = try? PackageProcess.run("/bin/zsh", ["-ilc", script], environment: environment, timeout: 10), result.status == 0 {
            for entry in result.stdout.split(separator: 0) {
                let pair = String(decoding: entry, as: UTF8.self).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if pair.count == 2, keys.contains(String(pair[0])) { environment[String(pair[0])] = String(pair[1]) }
            }
        }
        var candidates = [override, base?.executable].compactMap { $0 }
        candidates += candidateExecutables(home: home, environment: environment)
        return try inspect(candidates: candidates, environment: environment, home: home)
    }

    static func inspect(candidates: [String], environment: [String: String], home: URL) throws -> Self {
        var seenCLI = Set<String>(), seenInventory = Set<String>()
        var found: [PackageEnvironment] = [], warnings: [String] = []
        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate)
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            let resolved = url.resolvingSymlinksInPath()
            guard seenCLI.insert(resolved.path).inserted else { continue }
            var childEnvironment = environment
            // npm's symlink often targets lib/node_modules/npm/bin/npm-cli.js;
            // find the matching runtime from its prefix before falling back to PATH.
            let adjacent = url.deletingLastPathComponent().appendingPathComponent("node").path
            let matching = matchingNode(for: url, resolved: resolved) ?? (FileManager.default.isExecutableFile(atPath: adjacent) ? adjacent : nil)
            if let matching {
                childEnvironment["PATH"] = URL(fileURLWithPath: matching).deletingLastPathComponent().path + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
            }
            let probe = PackageEngine(provider: .npm, executable: candidate, environment: childEnvironment, nodeExecutable: matching)
            do {
                let prefixResult = try probe.run(["prefix", "--global"], timeout: 15)
                try prefixResult.requireSuccess()
                let rawPrefix = String(decoding: prefixResult.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                guard rawPrefix.hasPrefix("/"), !rawPrefix.contains("\n") else { throw PackageFailure(message: L("npm did not report a valid global prefix.")) }
                // Canonical prefixes also avoid npm/Arborist treating /var symlinks
                // as linked roots and silently skipping their installed children.
                let prefix = URL(fileURLWithPath: rawPrefix).resolvingSymlinksInPath().path
                childEnvironment["npm_config_prefix"] = prefix
                childEnvironment["NPM_CONFIG_PREFIX"] = nil
                let npmResult = try probe.run(["--version"], timeout: 10)
                try npmResult.requireSuccess()
                let npmVersion = String(decoding: npmResult.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                var nodeVersion = "—"
                if let matching, let nodeResult = try? PackageProcess.run(matching, ["--version"], environment: childEnvironment, timeout: 10), nodeResult.status == 0 {
                    nodeVersion = String(decoding: nodeResult.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                // Multiple aliases to the same runtime/prefix share one inventory.
                let identity = prefix + "|" + (matching.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path } ?? resolved.path)
                guard seenInventory.insert(identity).inserted else { continue }
                found.append(PackageEnvironment(engine: PackageEngine(provider: .npm, executable: candidate, environment: childEnvironment,
                                                                      nodeExecutable: matching, prefix: prefix), npmVersion: npmVersion, nodeVersion: nodeVersion))
            } catch { warnings.append(candidate + ": " + error.localizedDescription) }
        }
        if found.isEmpty, !warnings.isEmpty { throw PackageFailure(message: warnings.joined(separator: "\n")) }
        return Self(environments: found, warnings: warnings, otherManagers: otherManagerSummaries(home: home))
    }

    static func candidateExecutables(home: URL, environment: [String: String]) -> [String] {
        let fm = FileManager.default
        var directories = (environment["PATH"] ?? "").split(separator: ":").map { URL(fileURLWithPath: String($0)) }
        directories += ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".volta/bin").path,
                        home.appendingPathComponent(".asdf/shims").path, home.appendingPathComponent(".local/share/mise/shims").path].map { URL(fileURLWithPath: $0) }
        var versionRoots: [(URL, String)] = [
            (home.appendingPathComponent(".nvm/versions/node"), "bin"),
            (home.appendingPathComponent(".fnm/node-versions"), "installation/bin"),
            (home.appendingPathComponent(".local/share/fnm/node-versions"), "installation/bin"),
            (home.appendingPathComponent("Library/Application Support/fnm/node-versions"), "installation/bin"),
            (home.appendingPathComponent(".volta/tools/image/node"), "bin"),
            (home.appendingPathComponent(".asdf/installs/nodejs"), "bin"),
            (home.appendingPathComponent(".local/share/mise/installs/node"), "bin")
        ]
        for (key, suffix, bin) in [("NVM_DIR", "versions/node", "bin"), ("FNM_DIR", "node-versions", "installation/bin"),
                                   ("VOLTA_HOME", "tools/image/node", "bin"), ("ASDF_DATA_DIR", "installs/nodejs", "bin"),
                                   ("MISE_DATA_DIR", "installs/node", "bin")] {
            if let root = environment[key], root.hasPrefix("/") { versionRoots.append((URL(fileURLWithPath: root).appendingPathComponent(suffix), bin)) }
        }
        for (root, suffix) in versionRoots {
            let versions = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            directories += versions.filter { !$0.lastPathComponent.hasPrefix(".") }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent(suffix) }
        }
        for root in ["/opt/homebrew/opt", "/usr/local/opt"] {
            let entries = (try? fm.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil)) ?? []
            directories += entries.filter { $0.lastPathComponent == "node" || $0.lastPathComponent.hasPrefix("node@") }.map { $0.appendingPathComponent("bin") }
        }
        var seen = Set<String>()
        return directories.map { $0.appendingPathComponent("npm").path }.filter { seen.insert($0).inserted && fm.isExecutableFile(atPath: $0) }
    }

    private static func matchingNode(for original: URL, resolved: URL) -> String? {
        let components = resolved.pathComponents
        if let libIndex = components.lastIndex(of: "lib"), components.dropFirst(libIndex + 1).first == "node_modules" {
            let prefix = NSString.path(withComponents: Array(components.prefix(libIndex)))
            let node = URL(fileURLWithPath: prefix).appendingPathComponent("bin/node").path
            if FileManager.default.isExecutableFile(atPath: node) { return node }
        }
        let node = original.deletingLastPathComponent().appendingPathComponent("node").path
        return FileManager.default.isExecutableFile(atPath: node) ? node : nil
    }

    static func otherManagerSummaries(home: URL) -> [String] {
        var result: [String] = []
        let bun = home.appendingPathComponent(".bun/install/global/package.json")
        if let summary = manifestSummary(bun) { result.append("Bun · " + summary) }
        for base in [home.appendingPathComponent("Library/pnpm/global"), home.appendingPathComponent(".local/share/pnpm/global")] {
            let versions = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)) ?? []
            var names = Set<String>()
            for version in versions {
                let roots = [version] + ((try? FileManager.default.contentsOfDirectory(at: version, includingPropertiesForKeys: nil)) ?? [])
                for root in roots { names.formUnion(manifestNames(root.appendingPathComponent("package.json"))) }
            }
            if !names.isEmpty { result.append("pnpm · " + names.sorted().joined(separator: ", ") + " · " + base.path) }
        }
        return result
    }
    private static func manifestSummary(_ url: URL) -> String? {
        let names = manifestNames(url)
        return names.isEmpty ? nil : names.sorted().joined(separator: ", ") + " · " + url.deletingLastPathComponent().path
    }
    private static func manifestNames(_ url: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return Set((json["dependencies"] as? [String: Any] ?? [:]).keys)
    }
}
