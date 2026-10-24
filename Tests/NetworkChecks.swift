// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

private final class NetworkFixture: NetworkAccess, @unchecked Sendable {
    var services: [NetworkServiceState]
    var writes = 0
    var reject = false
    var ignoreLive = false
    var pause = false
    init(_ service: NetworkServiceState) { services = [service] }
    func read() throws -> [NetworkServiceState] { services }
    func write(service: NetworkServiceState, target: NetworkConfiguration) async throws {
        writes += 1
        if pause { try await Task.sleep(for: .milliseconds(80)) }
        if reject { throw NetworkFailure.message("Authorization cancelled") }
        guard services[0].configuration.matches(service.configuration) else { throw NetworkFailure.message("Conflict") }
        let ipv4 = try NetworkConfiguration.decode(target.ipv4)
        let dns = try NetworkConfiguration.decode(target.dns)
        services = [.init(id: service.id, locationID: service.locationID, name: service.name, interface: service.interface,
            configuration: target, method: ipv4["ConfigMethod"] as? String ?? "DHCP",
            ip: service.ip, mask: service.mask, router: ignoreLive ? service.router : ipv4["Router"] as? String ?? "192.168.1.1",
            dns: ignoreLive ? service.dns : dns["ServerAddresses"] as? [String] ?? ["192.168.1.1"], primary: true)]
    }
}

@main struct NetworkChecks {
    @MainActor static func main() async throws {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); count += 1; print("PASS: " + message)
        }
        func fixture(method: String = "Manual", id: String = "wifi-id", primary: Bool = true) throws -> NetworkServiceState {
            let config = try NetworkConfiguration(ipv4: ["ConfigMethod": method, "Addresses": ["192.168.1.123"],
                "SubnetMasks": ["255.255.255.0"], "Router": "192.168.1.1", "DHCPClientID": "original",
                "AdditionalRoutes": [["DestinationAddress": "10.0.0.0", "SubnetMask": "255.0.0.0", "GatewayAddress": "192.168.1.2"]]],
                dns: ["ServerAddresses": ["192.168.1.1"], "SearchDomains": ["home.test"]])
            return .init(id: id, locationID: "home", name: "Wi-Fi", interface: "en0", configuration: config,
                method: method, ip: "192.168.1.123", mask: "255.255.255.0", router: "192.168.1.1", dns: ["192.168.1.1"], primary: primary)
        }
        let suite = "1ToolNetworkChecks-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try fixture()
        let access = NetworkFixture(original)
        let model = NetworkSettings(access: access, defaults: defaults)
        check(access.writes == 0 && model.profiles.isEmpty, "startup reads network without applying a profile or prompting")
        for invalid in ["", "192.168.1.999", "192.168.01.1", "127.0.0.1", "0.0.0.0", "224.0.0.1", "1.2.3.4;whoami", "1.2.3.4\n"] {
            check(!NetworkAddress.unicast(invalid), "reject malformed or non-unicast address: " + invalid.debugDescription)
        }
        for invalid in ["192.168.1.123", "192.168.1.0", "192.168.1.255", "192.168.2.1"] {
            check((try? NetworkAddress.validate(invalid, service: original)) == nil, "reject host, subnet, broadcast and off-subnet gateway: " + invalid)
        }
        let profile = NetworkProfile(address: "192.168.1.250")
        check(model.save(profile) && access.writes == 0, "saving a router does not write system settings")
        check(!model.save(.init(address: profile.address)), "duplicate addresses are rejected")
        let updated = NetworkProfile(id: profile.id, address: "192.168.1.251")
        check(model.save(updated) && model.profiles.count == 1, "updating an IP address retains stable identity")
        let reloaded = NetworkSettings(access: access, defaults: defaults)
        check(reloaded.profiles == [updated], "profiles persist across model restarts")
        let target = try NetworkAddress.target(profile.address, service: original)
        let targetIP = try NetworkConfiguration.decode(target.ipv4)
        let targetDNS = try NetworkConfiguration.decode(target.dns)
        check(targetIP["Addresses"] as? [String] == [original.ip] && targetIP["SubnetMasks"] as? [String] == [original.mask], "switch preserves host address and subnet")
        check(targetIP["Router"] as? String == profile.address && targetDNS["ServerAddresses"] as? [String] == [profile.address], "one target sets both router and DNS")
        check(targetIP["AdditionalRoutes"] != nil && targetIP["DHCPClientID"] as? String == "original" && targetDNS["SearchDomains"] as? [String] == ["home.test"], "unrelated routes, client ID and DNS search domains survive")
        await model.requestSwitch(profile)
        check(model.isActive(profile) && model.error == nil && model.canRestore && access.writes == 1, "switch verifies persisted and live DNS and router")
        let second = NetworkProfile(address: "192.168.1.251")
        await model.requestSwitch(second)
        let restarted = NetworkSettings(access: access, defaults: defaults)
        check(restarted.canRestore, "original backup survives switching again and relaunch")
        await restarted.restore()
        check(access.services[0].configuration.matches(original.configuration) && !restarted.canRestore, "restore returns both protocols to the original configuration")
        access.reject = true
        await model.requestSwitch(profile)
        check(model.error != nil && !model.isActive(profile) && !model.isChanging && access.services[0].configuration.matches(original.configuration), "cancelled authorization reports failure without changing settings")
        access.reject = false; access.ignoreLive = true
        await model.requestSwitch(profile)
        check(model.error != nil && access.services[0].configuration.matches(original.configuration) && !model.isActive(profile), "persisted-only success is rejected and both settings roll back")
        access.ignoreLive = false
        access.services = [try fixture(method: "DHCP")]
        model.refresh()
        let before = access.writes
        await model.requestSwitch(profile)
        check(model.pendingDHCP == profile && access.writes == before, "DHCP requires explicit manual-mode acknowledgement before writes")
        model.cancelDHCP()
        check(model.pendingDHCP == nil && access.writes == before, "cancelling DHCP acknowledgement leaves connection unchanged")
        await model.requestSwitch(profile)
        await model.confirmDHCP()
        check(access.services[0].method == "Manual" && model.isActive(profile), "confirmed DHCP switch retains host address and uses manual IPv4")
        access.pause = true
        let task = Task { await model.requestSwitch(second) }
        while !model.isChanging { await Task.yield() }
        let overlapCount = access.writes
        await model.requestSwitch(profile)
        check(access.writes == overlapCount, "overlapping switches cannot interleave writes")
        await task.value
        model.remove(profile.id)
        check(model.profiles.isEmpty && access.services[0].router == second.address, "deleting saved profile does not change active network")
        access.services = [try fixture(primary: false)]
        model.refresh()
        let beforeInactive = access.writes
        await model.requestSwitch(profile)
        check(model.current == nil && access.writes == beforeInactive, "no primary connection never falls back to an inactive service")
        access.services = [try fixture(id: "old", primary: false), try fixture(id: "new")]
        model.refresh()
        check(model.current?.id == "new", "current connection follows the system primary service without a picker")
        let dhcpSuite = suite + "-dhcp"
        let dhcpDefaults = UserDefaults(suiteName: dhcpSuite)!
        defer { dhcpDefaults.removePersistentDomain(forName: dhcpSuite) }
        let dhcpOriginal = try fixture(method: "DHCP")
        let dhcpAccess = NetworkFixture(dhcpOriginal)
        let dhcp = NetworkSettings(access: dhcpAccess, defaults: dhcpDefaults)
        await dhcp.requestSwitch(profile)
        await dhcp.confirmDHCP()
        await dhcp.requestSwitch(profile)
        check(dhcpAccess.writes == 1, "selecting an already active IP does not write or request authorization again")
        await dhcp.restore()
        check(dhcpAccess.services[0].method == "DHCP" && dhcpAccess.services[0].configuration.matches(dhcpOriginal.configuration), "restore recovers original DHCP and DNS dictionaries")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        check(json["name"] == nil && json["address"] as? String == profile.address, "saved entries contain only IP and stable identity, with no profile name")
        let live = try MacNetworkAccess().read()
        check(!live.isEmpty && live.contains(where: { $0.primary && !$0.ip.isEmpty }), "real Mac read-only discovery identifies active physical connection")
        for service in live { print("LIVE: \(service.name) \(service.interface) \(service.method) IP=\(service.ip) router=\(service.router) DNS=\(service.dns)") }
        print("PASS: \(count) network checks")
    }
}
