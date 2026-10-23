// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

enum PackageProvider: String, Sendable {
    case brew, npm
    var title: String { self == .brew ? "Homebrew" : "npm" }
}

enum PackageKind: String, CaseIterable, Identifiable, Sendable {
    case formula, cask, npm
    var id: String { rawValue }
    var title: String { self == .formula ? "Formula" : self == .cask ? "Cask" : L("Global Package") }
}

struct ManagedPackage: Identifiable, Sendable {
    let name: String
    let kind: PackageKind
    let version: String
    var latest: String?
    var outdated: Bool
    var pinned = false
    var id: String { kind.rawValue + ":" + name }
}

enum PackageAction: String, Sendable {
    case install, uninstall, upgrade
    var title: String { L(rawValue.capitalized) }
}

enum PackageUpdateState: Equatable, Sendable {
    case notChecked, checking, cached(Date), checked(Date), failed
    var isKnown: Bool {
        switch self { case .cached, .checked: return true; default: return false }
    }
    var explanation: String {
        switch self {
        case .notChecked: return L("Updates have not been checked. Check for Updates to see available upgrades.")
        case .checking: return L("Checking for updates…")
        case .failed: return L("The update check failed. Update availability is unknown. Try Check for Updates again.")
        case .cached: return L("Available upgrades use local Homebrew metadata. Check for Updates refreshes the source.")
        case .checked: return L("No updates available.")
        }
    }
}

struct PackageIssue: Sendable {
    enum Kind: String, Sendable { case administrator, directoryAccess, registryAuthentication, network, other }
    let kind: Kind
    let details: String
    let path: String?
    var title: String {
        switch kind {
        case .administrator: return L("Administrator interaction required")
        case .directoryAccess: return L("Package directory access denied")
        case .registryAuthentication: return L("Package registry authentication required")
        case .network: return L("Package server could not be reached")
        case .other: return L("Package operation failed")
        }
    }
    func guidance(for provider: PackageProvider) -> String {
        switch kind {
        case .administrator: return L("This operation needs an interactive administrator prompt. Copy the command and run it in Terminal, then return and Refresh. 1Tool does not elevate privileges.")
        case .directoryAccess:
            return provider == .npm
                ? L("Check ownership and write access for the reported path. Use a user-owned npm prefix or select another Node installation, then Refresh and retry. This error does not establish a Full Disk Access problem.")
                : L("Check ownership and write access for the reported Homebrew path, then Refresh and retry. This error does not establish a Full Disk Access problem.")
        case .registryAuthentication: return L("Check the configured package source and sign-in credentials in Terminal, then retry. System privacy permissions do not sign you into a registry.")
        case .network: return L("Check your network, proxy and configured package server, then retry.")
        case .other: return L("Review the command details, resolve the reported error, then Refresh before retrying.")
        }
    }
    static func classify(_ details: String) -> Self {
        let text = details.lowercased()
        let administrator = ["a terminal is required", "no tty present", "a password is required", "no password was provided", "unable to read password", "administrator privileges", "requires root privileges", "must be run as root", "askpass program"]
        let access = ["eacces", "eperm", "permission denied", "operation not permitted", "not writable", "not writeable"]
        let authentication = ["e401", "e403", "eneedauth", "authentication required", "need auth"]
        let network = ["eai_again", "enotfound", "etimedout", "econnreset", "could not resolve host", "failed to connect"]
        let kind: Kind
        if administrator.contains(where: text.contains) { kind = .administrator }
        else if authentication.contains(where: text.contains) { kind = .registryAuthentication }
        else if access.contains(where: text.contains) { kind = .directoryAccess }
        else if network.contains(where: text.contains) { kind = .network }
        else { kind = .other }
        let path = details.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .compactMap { line -> String? in
                let candidate = line.range(of: #"(?:npm (?:ERR!|error) path\s+)(/.+)"#, options: .regularExpression)
                if let candidate, let slash = line[candidate].firstIndex(of: "/") { return String(line[slash...]) }
                return line.hasPrefix("/") ? line : nil
            }.first
        return Self(kind: kind, details: details, path: path)
    }
}

struct PackageCommandResult: Sendable {
    let status: Int32
    let stdout: Data
    let stderr: String
    var output: String { String(decoding: stdout, as: UTF8.self) + stderr }
    func requireSuccess(allowing statuses: Set<Int32> = [0]) throws {
        guard statuses.contains(status) else {
            throw PackageFailure(message: LF("Command failed (exit %d). %@", status, String(output.suffix(4000))))
        }
    }
}

struct PackageFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Runs off the main actor. Separate regular files prevent pipe deadlocks, including
/// when a timed-out CLI leaves a child process holding its output handles open.
enum PackageProcess {
    static func run(_ executable: String, _ arguments: [String], environment: [String: String],
                    timeout: TimeInterval = 120, output: @Sendable (String) -> Void = { _ in }) throws -> PackageCommandResult {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("onetool-packages-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                              attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let stdoutURL = directory.appendingPathComponent("stdout"), stderrURL = directory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let stdoutWriter = try FileHandle(forWritingTo: stdoutURL), stderrWriter = try FileHandle(forWritingTo: stderrURL)
        let stdoutReader = try FileHandle(forReadingFrom: stdoutURL), stderrReader = try FileHandle(forReadingFrom: stderrURL)
        defer {
            try? stdoutWriter.close(); try? stderrWriter.close()
            try? stdoutReader.close(); try? stderrReader.close()
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutWriter; process.standardError = stderrWriter
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var stdout = Data(), stderr = Data()
        func drain() throws {
            for (reader, isError) in [(stdoutReader, false), (stderrReader, true)] {
                let chunk = try reader.read(upToCount: 65_536) ?? Data()
                if !chunk.isEmpty {
                    if isError { stderr.append(chunk); stderr = Data(stderr.suffix(200_000)) }
                    else { stdout.append(chunk) }
                    output(String(decoding: chunk, as: UTF8.self))
                }
            }
        }
        do {
            while process.isRunning {
                try drain()
                if Date() >= deadline { throw PackageFailure(message: L("The command timed out. Refresh to check the current package state.")) }
                if stdout.count > 32_000_000 { throw PackageFailure(message: L("The command produced too much output. Refresh to check the current package state.")) }
                Thread.sleep(forTimeInterval: 0.1)
            }
            process.waitUntilExit()
            // Drain the final output even when a short-lived process exits before polling.
            while true {
                let before = (try stdoutReader.offset(), try stderrReader.offset())
                try drain()
                if before == (try stdoutReader.offset(), try stderrReader.offset()) { break }
                if stdout.count > 32_000_000 { throw PackageFailure(message: L("The command produced too much output. Refresh to check the current package state.")) }
            }
        } catch {
            if process.isRunning { kill(process.processIdentifier, SIGKILL); process.waitUntilExit() }
            throw error
        }
        return PackageCommandResult(status: process.terminationStatus, stdout: stdout, stderr: String(decoding: stderr, as: UTF8.self))
    }
}

struct PackageEngine: Sendable {
    let provider: PackageProvider
    let executable: String
    let environment: [String: String]
    var nodeExecutable: String? = nil
    var prefix: String? = nil

    func run(_ arguments: [String], timeout: TimeInterval = 120, output: @Sendable (String) -> Void = { _ in }) throws -> PackageCommandResult {
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        if provider == .npm, let nodeExecutable, resolved.hasSuffix(".js") {
            return try PackageProcess.run(nodeExecutable, [resolved] + arguments, environment: environment, timeout: timeout, output: output)
        }
        return try PackageProcess.run(executable, arguments, environment: environment, timeout: timeout, output: output)
    }

    static func discover(_ provider: PackageProvider, override: String? = nil) throws -> Self? {
        var environment = ProcessInfo.processInfo.environment
        // Use the user's interactive login PATH so nvm, fnm, asdf and mise resolve
        // the same active Node installation as Terminal. This script is constant.
        if let result = try? PackageProcess.run("/bin/zsh", ["-ilc", "/usr/bin/printenv PATH"], environment: environment, timeout: 10), result.status == 0,
           let path = String(decoding: result.stdout, as: UTF8.self).split(separator: "\n").last {
            environment["PATH"] = String(path)
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init) +
            ["/opt/homebrew/bin", "/usr/local/bin", home + "/.volta/bin", home + "/.local/share/mise/shims", home + "/.asdf/shims", "/usr/bin", "/bin"]
        let candidates = override.map { [$0] } ?? directories.map { $0 + "/" + provider.rawValue }
        guard let executable = candidates.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        environment["PATH"] = ([URL(fileURLWithPath: executable).deletingLastPathComponent().path] + directories).joined(separator: ":")
        environment = commandEnvironment(environment)
        return Self(provider: provider, executable: executable, environment: environment)
    }

    static func commandEnvironment(_ input: [String: String]) -> [String: String] {
        var environment = input
        environment["HOMEBREW_NO_ANALYTICS"] = "1"
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        environment["HOMEBREW_NO_AUTOREMOVE"] = "1"
        environment["HOMEBREW_COLOR"] = nil
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        environment["NONINTERACTIVE"] = "1"
        environment["SUDO_ASKPASS"] = "/usr/bin/false"
        environment["npm_config_update_notifier"] = "false"
        environment["npm_config_color"] = "false"
        environment["npm_config_progress"] = "false"
        environment["npm_config_fetch_retries"] = "1"
        environment["npm_config_fetch_timeout"] = "30000"
        return environment
    }

    static func validName(_ name: String, kind: PackageKind) -> Bool {
        let component = "[a-z0-9][a-z0-9._+@-]*"
        let pattern = kind == .npm ? "\\A(?:@[a-z0-9][a-z0-9._-]*/)?[a-z0-9][a-z0-9._-]*\\z" : "\\A\(component)(?:/\(component)/\(component))?\\z"
        return name.utf8.count <= 214 && name.range(of: pattern, options: .regularExpression) != nil
    }

    func arguments(for action: PackageAction, name: String, kind: PackageKind) throws -> [String] {
        guard Self.validName(name, kind: kind), (provider == .npm) == (kind == .npm) else {
            throw PackageFailure(message: L("Enter one package name, such as wget or @scope/package. URLs, paths and command options are not supported."))
        }
        if provider == .brew {
            return [action == .upgrade ? "upgrade" : action.rawValue, kind == .cask ? "--cask" : "--formula", "--", name]
        }
        // Explicit @latest also upgrades across major versions, matching the displayed target.
        return [action == .uninstall ? "uninstall" : "install", "--global", "--", action == .upgrade ? name + "@latest" : name]
    }

    func terminalCommand(for action: PackageAction, name: String, kind: PackageKind) throws -> String {
        // Display/copy only. The app still executes arguments directly with Process.
        func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let resolved = URL(fileURLWithPath: executable).resolvingSymlinksInPath().path
        var command = [executable]
        var pathAssignment = ""
        if provider == .npm, let nodeExecutable {
            let directory = URL(fileURLWithPath: nodeExecutable).deletingLastPathComponent().path
            pathAssignment = "PATH=" + quote(directory) + ":\"$PATH\" "
            if resolved.hasSuffix(".js") { command = [nodeExecutable, resolved] }
        }
        if provider == .npm, let prefix { command += ["--prefix", prefix] }
        return pathAssignment + (command + (try arguments(for: action, name: name, kind: kind))).map(quote).joined(separator: " ")
    }

    func installed() throws -> [ManagedPackage] { try inventory().packages }

    func inventory() throws -> PackageInventory {
        let args = provider == .brew ? ["info", "--json=v2", "--installed"] : ["ls", "--global", "--depth=0", "--json"]
        let result = try run(args)
        var warning: String?
        if provider == .npm,
           let document = try? JSONDecoder().decode(NpmList.self, from: result.stdout),
           document.dependencies != nil,
           (document.error?.code == "ELSPROBLEMS" || (result.status == 1 && !(document.problems ?? []).isEmpty)) {
            warning = [document.error?.summary, document.problems?.joined(separator: "\n"), result.stderr].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        } else { try result.requireSuccess() }
        return PackageInventory(packages: try Self.parseInstalled(result.stdout, provider: provider), warning: warning)
    }

    func updates(_ packages: [ManagedPackage]) throws -> [ManagedPackage] {
        // Brew update refreshes metadata; automatic updates stay disabled elsewhere.
        if provider == .brew {
            try run(["update"], timeout: 300).requireSuccess()
            return try installed()
        }
        let result = try run(["outdated", "--global", "--depth=0", "--json"])
        try result.requireSuccess(allowing: [0, 1]) // npm uses 1 when updates exist.
        return try Self.applyingNpmUpdates(result.stdout, to: packages)
    }

    func perform(_ action: PackageAction, name: String, kind: PackageKind, output: @Sendable (String) -> Void) throws {
        let args = try arguments(for: action, name: name, kind: kind)
        output("$ " + (try terminalCommand(for: action, name: name, kind: kind)) + "\n")
        try run(args, timeout: 1800, output: output).requireSuccess()
    }

    static func parseInstalled(_ data: Data, provider: PackageProvider) throws -> [ManagedPackage] {
        if provider == .npm {
            let document = try JSONDecoder().decode(NpmList.self, from: data)
            guard document.error == nil || (document.error?.code == "ELSPROBLEMS" && document.dependencies != nil) else {
                throw PackageFailure(message: document.error?.summary ?? L("Could not read the package list."))
            }
            guard document.dependencies != nil || document.error == nil else { throw PackageFailure(message: L("Could not read the package list.")) }
            return (document.dependencies ?? [:]).map { name, value in
                ManagedPackage(name: name, kind: .npm, version: value.version ?? "—", outdated: false)
            }.sorted { $0.name < $1.name }
        }
        let info = try JSONDecoder().decode(BrewInfo.self, from: data)
        return (info.formulae.map {
            ManagedPackage(name: $0.full_name ?? $0.name, kind: .formula,
                           version: $0.installed.map(\.version).joined(separator: ", "), latest: $0.versions.stable,
                           outdated: $0.outdated, pinned: $0.pinned ?? false)
        } + info.casks.map {
            ManagedPackage(name: $0.full_token ?? $0.token, kind: .cask, version: $0.installed ?? "—",
                           latest: $0.version, outdated: $0.outdated)
        }).sorted { $0.name < $1.name }
    }

    static func applyingNpmUpdates(_ data: Data, to packages: [ManagedPackage]) throws -> [ManagedPackage] {
        // Error envelopes must not be mistaken for an empty update list.
        let envelope = try JSONDecoder().decode(NpmList.self, from: data)
        if let error = envelope.error { throw PackageFailure(message: error.summary ?? L("Could not check for updates.")) }
        let updates = try JSONDecoder().decode([String: NpmUpdate].self, from: data)
        return packages.map { package in
            var package = package
            package.latest = updates[package.name]?.latest
            package.outdated = package.latest.map { $0 != package.version } ?? false
            return package
        }
    }

    private struct BrewInfo: Decodable {
        let formulae: [Formula]
        let casks: [Cask]
        struct Formula: Decodable {
            let name: String; let full_name: String?; let installed: [Installation]
            let versions: Versions; let outdated: Bool; let pinned: Bool?
            struct Installation: Decodable { let version: String }
            struct Versions: Decodable { let stable: String? }
        }
        struct Cask: Decodable {
            let token: String; let full_token: String?; let installed: String?
            let version: String; let outdated: Bool
        }
    }
    private struct NpmList: Decodable {
        var dependencies: [String: Dependency]?
        var error: Failure?
        var problems: [String]?
        struct Dependency: Decodable { let version: String? }
        struct Failure: Decodable { let code: String?; let summary: String? }
    }
    private struct NpmUpdate: Decodable { let latest: String? }
}

struct PackageInventory: Sendable {
    let packages: [ManagedPackage]
    let warning: String?
}
