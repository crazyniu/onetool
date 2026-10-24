// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation

private struct NetworkBackup: Codable {
    let configuration: NetworkConfiguration
}

@MainActor @Observable final class NetworkSettings {
    private(set) var profiles: [NetworkProfile] = []
    private var services: [NetworkServiceState] = []
    private(set) var isChanging = false
    private(set) var error: String?
    private(set) var notice: String?
    private(set) var pendingDHCP: NetworkProfile?
    @ObservationIgnored private let access: any NetworkAccess
    @ObservationIgnored private let defaults: UserDefaults
    private var backups: [String: NetworkBackup] = [:]
    private var pendingServiceKey: String?
    var current: NetworkServiceState? { services.first { $0.primary } }
    var canRestore: Bool { current.map { backups[$0.key] != nil } ?? false }

    init(access: any NetworkAccess = MacNetworkAccess(), defaults: UserDefaults = .standard) {
        self.access = access; self.defaults = defaults
        if let data = defaults.data(forKey: "network.profiles") {
            do { profiles = try JSONDecoder().decode([NetworkProfile].self, from: data) }
            catch { self.error = L("Saved network profiles could not be read.") }
        }
        if let data = defaults.data(forKey: "network.backups") {
            do { backups = try JSONDecoder().decode([String: NetworkBackup].self, from: data) }
            catch { self.error = L("The saved network configuration is invalid.") }
        }
        refresh()
    }
    func refresh() {
        guard !isChanging else { return }
        do { try reload() } catch { self.error = error.localizedDescription }
    }
    private func reload() throws {
        services = try access.read()
    }
    func save(_ profile: NetworkProfile) -> Bool {
        guard !isChanging else { return false }
        let address = profile.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard NetworkAddress.unicast(address) else {
            error = L("Enter a valid IPv4 router address."); return false
        }
        guard !profiles.contains(where: { $0.id != profile.id && $0.address == address }) else {
            error = L("This router address is already saved."); return false
        }
        let updated = NetworkProfile(id: profile.id, address: address)
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[index] = updated }
        else { profiles.append(updated) }
        persistProfiles(); error = nil; return true
    }
    func remove(_ id: UUID) {
        guard !isChanging else { return }
        profiles.removeAll { $0.id == id }; persistProfiles()
    }
    private func persistProfiles() { defaults.set(try? JSONEncoder().encode(profiles), forKey: "network.profiles") }
    private func persistBackups() throws {
        let data = try JSONEncoder().encode(backups)
        defaults.set(data, forKey: "network.backups")
    }
    func isActive(_ profile: NetworkProfile) -> Bool {
        guard let service = current, service.matches(address: profile.address),
              let config = try? NetworkAddress.target(profile.address, service: service) else { return false }
        return service.configuration.matches(config)
    }
    func requestSwitch(_ profile: NetworkProfile) async {
        guard !isChanging else { return }
        error = nil; notice = nil
        do {
            try reload()
            guard let service = current else { throw NetworkFailure.message(L("No active network connection.")) }
            try NetworkAddress.validate(profile.address, service: service)
            if isActive(profile) { return }
            if service.usesDHCP {
                pendingDHCP = profile; pendingServiceKey = service.key
            } else { await apply(profile, service: service) }
        } catch { self.error = error.localizedDescription }
    }
    func cancelDHCP() { pendingDHCP = nil; pendingServiceKey = nil }
    func confirmDHCP() async {
        guard let profile = pendingDHCP, let key = pendingServiceKey, !isChanging else { return }
        cancelDHCP()
        do {
            try reload()
            guard let service = current, service.key == key else {
                throw NetworkFailure.message(L("The network connection changed. Refresh and try again."))
            }
            await apply(profile, service: service)
        } catch { self.error = error.localizedDescription }
    }
    private func apply(_ profile: NetworkProfile, service: NetworkServiceState) async {
        isChanging = true; error = nil; notice = nil
        defer { isChanging = false }
        do {
            let target = try NetworkAddress.target(profile.address, service: service)
            if backups[service.key] == nil {
                backups[service.key] = .init(configuration: service.configuration)
                try persistBackups()
            }
            try await access.write(service: service, target: target)
            // Config commit is not evidence that configd has installed the live state.
            var verified = false
            for _ in 0..<20 {
                try reload()
                if let live = services.first(where: { $0.key == service.key }),
                   live.primary, live.configuration.matches(target), live.matches(address: profile.address) { verified = true; break }
                try await Task.sleep(for: .milliseconds(250))
            }
            guard verified else {
                throw NetworkFailure.message(L("DNS and router could not both be verified. The previous configuration will be restored."))
            }
            notice = LF("DNS and router switched to %@.", profile.address)
        } catch {
            let reason = error.localizedDescription
            // Restore only our own committed target. Never overwrite a concurrent external change.
            do {
                try reload()
                if let current = services.first(where: { $0.key == service.key }),
                   let target = try? NetworkAddress.target(profile.address, service: service), current.configuration.matches(target) {
                    try await access.write(service: current, target: service.configuration)
                    try reload()
                    guard services.first(where: { $0.key == service.key })?.configuration.matches(service.configuration) == true else {
                        throw NetworkFailure.message(L("Restore failed. Use Restore Previous Configuration or System Settings."))
                    }
                    self.error = reason + "\n" + L("The previous configuration was restored.")
                } else { self.error = reason }
            } catch { self.error = reason + "\n" + error.localizedDescription }
        }
    }
    func restore() async {
        guard !isChanging else { return }
        isChanging = true; error = nil; notice = nil
        defer { isChanging = false }
        do {
            try reload()
            guard let service = current, let backup = backups[service.key] else { return }
            try await access.write(service: service, target: backup.configuration)
            try reload()
            guard services.first(where: { $0.key == service.key })?.configuration.matches(backup.configuration) == true else {
                throw NetworkFailure.message(L("Restore failed. Use Restore Previous Configuration or System Settings."))
            }
            backups.removeValue(forKey: service.key); try persistBackups()
            notice = L("The previous configuration was restored.")
        } catch { self.error = error.localizedDescription; try? reload() }
    }
}
