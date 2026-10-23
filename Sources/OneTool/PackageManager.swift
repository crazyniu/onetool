// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation

@MainActor @Observable final class PackageManager {
    let provider: PackageProvider
    private(set) var packages: [ManagedPackage] = []
    private(set) var executable: String?
    private(set) var environments: [PackageEnvironment] = []
    private(set) var selectedEnvironmentID: String?
    private(set) var environmentWarnings: [String] = []
    private(set) var otherManagers: [String] = []
    private(set) var inventoryWarning: String?
    private(set) var busy = false
    private(set) var loaded = false
    private(set) var attempted = false
    private(set) var error: String?
    private(set) var issue: PackageIssue?
    private(set) var message: String?
    private(set) var activity = ""
    private(set) var log = ""
    private(set) var updateState = PackageUpdateState.notChecked
    private(set) var activePackageID: String?
    private(set) var completedCount = 0
    private(set) var operationCount = 0
    private(set) var outcomes: [String: PackageOutcome] = [:]
    private(set) var lastFailedRequest: PackageRequest?
    private(set) var terminalCommand: String?
    @ObservationIgnored private var engine: PackageEngine?
    @ObservationIgnored private let automaticallyCheckUpdates: Bool

    init(_ provider: PackageProvider, engine: PackageEngine? = nil, automaticallyCheckUpdates: Bool = true) {
        self.provider = provider; self.engine = engine; executable = engine?.executable
        self.automaticallyCheckUpdates = automaticallyCheckUpdates
    }
    var checkedAt: Date? { if case .checked(let date) = updateState { return date }; return nil }
    var upgradable: [ManagedPackage] { updateState.isKnown ? packages.filter { $0.outdated && !$0.pinned } : [] }
    var canManage: Bool { loaded && engine != nil && !busy }
    var hasStatus: Bool { busy || issue != nil || message != nil }
    var statusTitle: String { busy ? activity : issue?.title ?? message ?? "" }
    var selectedEnvironment: PackageEnvironment? { environments.first { $0.id == selectedEnvironmentID } }
    var globalPrefix: String? { engine?.prefix }
    var environmentID: String? { selectedEnvironmentID ?? engine.map { $0.executable + "|" + ($0.prefix ?? "") } }
    var environmentTitle: String? { selectedEnvironment?.title ?? globalPrefix ?? executable }
    private var preferenceKey: String { "packages.\(provider.rawValue).executable" }
    private var environmentPreferenceKey: String { "packages.npm.environment" }

    func refresh(discover: Bool = false) {
        guard !busy else { return }
        busy = true; clearIssue(); message = nil; activity = L("Reading installed packages…")
        updateState = .notChecked
        let provider = provider, cached = discover ? nil : engine
        let override = UserDefaults.standard.string(forKey: preferenceKey)
        let savedEnvironment = selectedEnvironmentID ?? UserDefaults.standard.string(forKey: environmentPreferenceKey)
        Task {
            var checkAfterLoading = false
            defer {
                busy = false; attempted = true
                if checkAfterLoading { checkUpdates() }
            }
            do {
                let catalog = try await Task.detached(priority: .utility) {
                    try provider == .npm && cached == nil ? PackageEnvironmentCatalog.discover(override: override) : nil
                }.value
                let detected: PackageEngine?
                if let catalog {
                    environments = catalog.environments; environmentWarnings = catalog.warnings; otherManagers = catalog.otherManagers
                    let selected = environments.first { $0.id == savedEnvironment } ?? environments.first
                    selectedEnvironmentID = selected?.id; detected = selected?.engine
                } else {
                    detected = try await Task.detached(priority: .utility) { try cached ?? PackageEngine.discover(provider, override: override) }.value
                }
                engine = detected; executable = detected?.executable
                let inventory = try await Task.detached(priority: .utility) { try detected?.inventory() }.value
                packages = inventory?.packages ?? []; inventoryWarning = inventory?.warning
                loaded = detected != nil
                if loaded && provider == .brew { updateState = .cached(.now) }
                checkAfterLoading = loaded && provider == .npm && automaticallyCheckUpdates
            } catch { loaded = false; setIssue(error.localizedDescription) }
        }
    }

    func chooseExecutable() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = LF("Choose the %@ executable", provider.rawValue)
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let path = panel.url?.path {
            guard FileManager.default.isExecutableFile(atPath: path) else {
                setIssue(L("Choose an executable file.")); return
            }
            UserDefaults.standard.set(path, forKey: preferenceKey)
            if provider == .npm { UserDefaults.standard.removeObject(forKey: environmentPreferenceKey); selectedEnvironmentID = nil }
            engine = nil; executable = nil; loaded = false
            refresh(discover: true)
        }
    }

    func detectAutomatically() {
        guard !busy else { return }
        UserDefaults.standard.removeObject(forKey: preferenceKey)
        if provider == .npm { UserDefaults.standard.removeObject(forKey: environmentPreferenceKey); selectedEnvironmentID = nil }
        engine = nil; executable = nil; loaded = false
        refresh(discover: true)
    }

    func selectEnvironment(_ id: String) {
        guard !busy, let selected = environments.first(where: { $0.id == id }) else { return }
        selectedEnvironmentID = id; engine = selected.engine; executable = selected.engine.executable
        UserDefaults.standard.set(id, forKey: environmentPreferenceKey)
        packages = []; loaded = false; outcomes = [:]; inventoryWarning = nil
        refresh()
    }

    func checkUpdates() {
        guard canManage, let engine else { return }
        let packages = packages
        let previousState = updateState
        busy = true; clearIssue(); message = nil; activity = L("Checking for updates…")
        updateState = .checking
        Task {
            defer { busy = false }
            do {
                self.packages = try await Task.detached(priority: .utility) { try engine.updates(packages) }.value
                updateState = .checked(.now)
                let count = self.packages.filter(\.outdated).count
                message = count == 0 ? L("All packages are up to date.") : LF("%d updates available", count)
            } catch {
                // A failed remote brew refresh does not erase known local upgrades.
                if provider == .brew {
                    switch previousState {
                    case .cached(let date), .checked(let date): updateState = .cached(date)
                    default: updateState = .failed
                    }
                } else { updateState = .failed }
                setIssue(error.localizedDescription)
            }
        }
    }

    func perform(_ request: PackageRequest) {
        guard canManage, let engine, !request.packages.isEmpty else { return }
        guard request.environmentID == nil || request.environmentID == environmentID else {
            setIssue(L("The package environment changed. Review the selected environment and confirm again.")); return
        }
        busy = true; clearIssue(); message = nil; log = ""
        updateState = .notChecked; completedCount = 0; operationCount = request.packages.count
        outcomes = [:]; activePackageID = request.packages.first?.id
        lastFailedRequest = nil
        activity = LF("%@ · %@", request.action.title, request.packages[0].name)
        Task { [self] in
            defer { busy = false; activePackageID = nil }
            var operationError: String?
            do {
                try await Task.detached(priority: .utility) { [self] in
                    for package in request.packages {
                        await MainActor.run {
                            self.activePackageID = package.id
                            self.activity = LF("%@ · %@", request.action.title, package.name)
                            self.outcomes[package.id] = .running
                            self.terminalCommand = try? engine.terminalCommand(for: request.action, name: package.name, kind: package.kind)
                        }
                        do {
                            try engine.perform(request.action, name: package.name, kind: package.kind) { chunk in
                                Task { @MainActor [weak self] in self?.appendLog(chunk) }
                            }
                            await MainActor.run {
                                self.completedCount += 1
                                self.outcomes[package.id] = .completed
                            }
                        } catch {
                            await MainActor.run { self.outcomes[package.id] = .failed }
                            throw error
                        }
                    }
                }.value
                message = L("Operation completed.")
            } catch {
                operationError = error.localizedDescription
                lastFailedRequest = PackageRequest(action: request.action, packages: request.packages.filter { outcomes[$0.id] != .completed },
                                                   environmentID: request.environmentID, environmentTitle: request.environmentTitle)
            }
            // A nonzero exit may still have changed some packages. Always reread.
            do {
                let inventory = try await Task.detached(priority: .utility) { try engine.inventory() }.value
                packages = inventory.packages; inventoryWarning = inventory.warning
                loaded = true
                if provider == .brew { updateState = .cached(.now) }
            } catch {
                loaded = false
                operationError = [operationError, L("Could not refresh packages. Click Refresh before the next operation."), error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
            }
            if let operationError { setIssue(operationError) }
        }
    }

    private func appendLog(_ chunk: String) { log = String((log + chunk).suffix(24_000)) }
    private func clearIssue() { error = nil; issue = nil; terminalCommand = nil; lastFailedRequest = nil }
    private func setIssue(_ details: String) { error = details; issue = .classify(details) }
}

enum PackageOutcome: Sendable { case running, completed, failed }

struct PackageRequest: Identifiable, Sendable {
    let id = UUID()
    let action: PackageAction
    let packages: [ManagedPackage]
    let environmentID: String?
    let environmentTitle: String?
    init(action: PackageAction, packages: [ManagedPackage], environmentID: String? = nil, environmentTitle: String? = nil) {
        self.action = action; self.packages = packages; self.environmentID = environmentID; self.environmentTitle = environmentTitle
    }
}

