// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import SystemConfiguration
import Security
import Darwin

struct NetworkProfile: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var address: String
}

struct NetworkConfiguration: Codable, Equatable, Sendable {
    var ipv4: Data
    var dns: Data
    init(ipv4: [String: Any], dns: [String: Any]) throws {
        self.ipv4 = try Self.encode(ipv4); self.dns = try Self.encode(dns)
    }
    static func encode(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
    }
    static func decode(_ data: Data) throws -> [String: Any] {
        guard let result = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw NetworkFailure.message(L("The saved network configuration is invalid."))
        }
        return result
    }
    func matches(_ other: Self) -> Bool {
        guard let a = try? Self.decode(ipv4), let b = try? Self.decode(other.ipv4),
              let c = try? Self.decode(dns), let d = try? Self.decode(other.dns) else { return false }
        return NSDictionary(dictionary: a).isEqual(to: b) && NSDictionary(dictionary: c).isEqual(to: d)
    }
}

struct NetworkServiceState: Identifiable, Sendable {
    let id: String
    let locationID: String
    let name: String
    let interface: String
    let configuration: NetworkConfiguration
    let method: String
    let ip: String
    let mask: String
    let router: String
    let dns: [String]
    let primary: Bool
    var effectiveDNS: [String]? = nil
    var key: String { locationID + "/" + id }
    var usesDHCP: Bool { method == "DHCP" }
    var canSwitch: Bool { ["Manual", "DHCP"].contains(method) && NetworkAddress.validHost(ip, mask: mask) }
    func matches(address: String) -> Bool {
        router == address && dns == [address] && (effectiveDNS == nil || effectiveDNS == [address])
    }
}

enum NetworkFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

enum NetworkAddress {
    static func number(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: UInt32 = 0
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  part.count == 1 || part.first != "0", let byte = UInt8(part) else { return nil }
            result = (result << 8) | UInt32(byte)
        }
        return result
    }
    static func unicast(_ text: String) -> Bool {
        guard let value = number(text) else { return false }
        let first = value >> 24
        return first > 0 && first < 224 && first != 127 && value != UInt32.max
    }
    static func validHost(_ ip: String, mask: String) -> Bool {
        guard unicast(ip), let value = number(ip), let bits = number(mask) else { return false }
        let inverse = ~bits
        guard bits != 0, inverse > 1, inverse & (inverse &+ 1) == 0 else { return false }
        return value & inverse != 0 && value & inverse != inverse
    }
    static func validate(_ address: String, service: NetworkServiceState) throws {
        guard service.canSwitch, validHost(address, mask: service.mask), let gateway = number(address),
              let ip = number(service.ip), let mask = number(service.mask), gateway != ip,
              gateway & mask == ip & mask else {
            throw NetworkFailure.message(L("Use a different host address on the current connection’s IPv4 subnet."))
        }
    }
    static func target(_ address: String, service: NetworkServiceState) throws -> NetworkConfiguration {
        try validate(address, service: service)
        var ipv4 = try NetworkConfiguration.decode(service.configuration.ipv4)
        var dns = try NetworkConfiguration.decode(service.configuration.dns)
        // Preserve unrelated protocol keys, routes, search domains and the host address.
        ipv4[kSCPropNetIPv4ConfigMethod as String] = kSCValNetIPv4ConfigMethodManual as String
        ipv4[kSCPropNetIPv4Addresses as String] = [service.ip]
        ipv4[kSCPropNetIPv4SubnetMasks as String] = [service.mask]
        ipv4[kSCPropNetIPv4Router as String] = address
        dns[kSCPropNetDNSServerAddresses as String] = [address]
        return try NetworkConfiguration(ipv4: ipv4, dns: dns)
    }
}

protocol NetworkAccess: Sendable {
    func read() throws -> [NetworkServiceState]
    func write(service: NetworkServiceState, target: NetworkConfiguration) async throws
}

struct MacNetworkAccess: NetworkAccess {
    func read() throws -> [NetworkServiceState] {
        guard let prefs = SCPreferencesCreate(nil, "1Tool Network" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(prefs),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService],
              let store = SCDynamicStoreCreate(nil, "1Tool Network" as CFString, nil, nil) else { throw failure() }
        let location = SCNetworkSetGetSetID(set) as String? ?? ""
        let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let globalDNS = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
        return try services.compactMap { service in
            guard SCNetworkServiceGetEnabled(service), let interface = SCNetworkServiceGetInterface(service),
                  let device = SCNetworkInterfaceGetBSDName(interface) as String?,
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  [kSCNetworkInterfaceTypeEthernet as String, kSCNetworkInterfaceTypeIEEE80211 as String].contains(type),
                  let ipv4 = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeIPv4),
                  let dns = SCNetworkServiceCopyProtocol(service, kSCNetworkProtocolTypeDNS),
                  SCNetworkProtocolGetEnabled(ipv4), SCNetworkProtocolGetEnabled(dns) else { return nil }
            let id = SCNetworkServiceGetServiceID(service) as String? ?? ""
            let config = SCNetworkProtocolGetConfiguration(ipv4) as? [String: Any] ?? [:]
            let dnsConfig = SCNetworkProtocolGetConfiguration(dns) as? [String: Any] ?? [:]
            let live = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(id)/IPv4" as CFString) as? [String: Any] ?? [:]
            let liveDNS = SCDynamicStoreCopyValue(store, "State:/Network/Service/\(id)/DNS" as CFString) as? [String: Any] ?? [:]
            let configuredDNS = dnsConfig[kSCPropNetDNSServerAddresses as String] as? [String] ?? []
            let resolvedDNS = configuredDNS.isEmpty ? liveDNS[kSCPropNetDNSServerAddresses as String] as? [String] ?? [] : configuredDNS
            let primary = global?[kSCDynamicStorePropNetPrimaryService as String] as? String == id
            return NetworkServiceState(id: id, locationID: location, name: SCNetworkServiceGetName(service) as String? ?? device,
                interface: device, configuration: try .init(ipv4: config, dns: dnsConfig),
                method: config[kSCPropNetIPv4ConfigMethod as String] as? String ?? "",
                ip: (live[kSCPropNetIPv4Addresses as String] as? [String])?.first ?? "",
                mask: (live[kSCPropNetIPv4SubnetMasks as String] as? [String])?.first ?? "",
                router: live[kSCPropNetIPv4Router as String] as? String ?? "",
                dns: resolvedDNS, primary: primary,
                effectiveDNS: primary ? globalDNS?[kSCPropNetDNSServerAddresses as String] as? [String] ?? [] : nil)
        }.sorted { $0.primary && !$1.primary || $0.primary == $1.primary && $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func write(service: NetworkServiceState, target: NetworkConfiguration) async throws {
        try await Task.detached(priority: .userInitiated) { try Self.commit(service: service, target: target) }.value
    }
    private static func commit(service: NetworkServiceState, target: NetworkConfiguration) throws {
        var authorization: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [], &authorization)
        guard status == errAuthorizationSuccess, let authorization else {
            throw NetworkFailure.message(L("Administrator authorization was not granted."))
        }
        defer { AuthorizationFree(authorization, []) }
        guard let prefs = SCPreferencesCreateWithAuthorization(nil, "1Tool DNS & Router" as CFString, nil, authorization) else { throw failure() }
        // Lock also performs the native authorization interaction. Never request it during reads.
        guard SCPreferencesLock(prefs, true) else { throw failure() }
        defer { SCPreferencesUnlock(prefs) }
        guard let set = SCNetworkSetCopyCurrent(prefs), SCNetworkSetGetSetID(set) as String? == service.locationID,
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService],
              let selected = services.first(where: { SCNetworkServiceGetServiceID($0) as String? == service.id }),
              SCNetworkServiceGetEnabled(selected),
              let ipv4 = SCNetworkServiceCopyProtocol(selected, kSCNetworkProtocolTypeIPv4),
              let dns = SCNetworkServiceCopyProtocol(selected, kSCNetworkProtocolTypeDNS) else {
            throw NetworkFailure.message(L("The network connection changed. Refresh and try again."))
        }
        guard let live = try MacNetworkAccess().read().first(where: { $0.key == service.key }),
              live.primary, !service.usesDHCP || (live.ip == service.ip && live.mask == service.mask) else {
            throw NetworkFailure.message(L("The network connection changed. Refresh and try again."))
        }
        let previous = try NetworkConfiguration(ipv4: SCNetworkProtocolGetConfiguration(ipv4) as? [String: Any] ?? [:],
                                                dns: SCNetworkProtocolGetConfiguration(dns) as? [String: Any] ?? [:])
        guard previous.matches(service.configuration) else {
            throw NetworkFailure.message(L("The network connection changed. Refresh and try again."))
        }
        // Stage DNS and IPv4 in one preferences session and commit together.
        guard SCNetworkProtocolSetConfiguration(ipv4, try NetworkConfiguration.decode(target.ipv4) as CFDictionary),
              SCNetworkProtocolSetConfiguration(dns, try NetworkConfiguration.decode(target.dns) as CFDictionary) else { throw failure() }
        guard SCPreferencesCommitChanges(prefs) else { throw failure() }
        guard SCPreferencesApplyChanges(prefs) else {
            let reason = failure().localizedDescription
            let oldIPv4 = try NetworkConfiguration.decode(previous.ipv4) as CFDictionary
            let oldDNS = try NetworkConfiguration.decode(previous.dns) as CFDictionary
            let restored = SCNetworkProtocolSetConfiguration(ipv4, oldIPv4)
                && SCNetworkProtocolSetConfiguration(dns, oldDNS)
                && SCPreferencesCommitChanges(prefs) && SCPreferencesApplyChanges(prefs)
            throw NetworkFailure.message(reason + "\n" + L(restored ? "The previous configuration was restored." : "Restore failed. Use Restore Previous Configuration or System Settings."))
        }
    }
    private func failure() -> NetworkFailure { Self.failure() }
    private static func failure() -> NetworkFailure {
        .message(LF("Network settings failed: %@", String(cString: SCErrorString(SCError()))))
    }
}
