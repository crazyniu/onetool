// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation

struct DisplayState: Identifiable {
    enum Method: String { case system = "系统亮度", ddc = "DDC 硬件调光", software = "软件调暗", unavailable = "暂不支持调光" }
    let id: CGDirectDisplayID
    let key: String
    let name: String
    let builtIn: Bool
    var method: Method
    var level: Double
    var readable: Bool
    var error: String?
}

@Observable final class Displays {
    private(set) var screens: [DisplayState] = []
    private(set) var scanning = false
    @ObservationIgnored private let queue = DispatchQueue(label: "com.shopkivoo.onetool.displays", qos: .userInitiated)
    @ObservationIgnored private var routes: [CGDirectDisplayID: Route] = [:] // queue only
    @ObservationIgnored private var baselines: [String: Gamma] = [:] // queue only
    @ObservationIgnored private var dimmed = Set<String>() // queue only
    @ObservationIgnored private var commandEnds: [UInt32: UInt64] = [:] // queue only
    @ObservationIgnored private var debounce: DispatchWorkItem?
    @ObservationIgnored private var writes: [UInt32: DispatchWorkItem] = [:]
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var stopped = false

    private struct Route {
        var state: DisplayState
        var service: CFTypeRef?
        var maximum: UInt16 = 100
    }
    private struct Gamma {
        var red: [CGGammaValue]
        var green: [CGGammaValue]
        var blue: [CGGammaValue]
        var count: UInt32
    }

    init() {
        for (center, name) in [(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification),
                               (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification)] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.refreshAfterChange() }
            observers.append((center, token))
        }
        refresh()
    }
    deinit { observers.forEach { $0.0.removeObserver($0.1) } }
    static func key(_ id: UInt32) -> String {
        if let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "\(CGDisplayVendorNumber(id)):\(CGDisplayModelNumber(id)):\(CGDisplaySerialNumber(id)):\(id)"
    }
    private func refreshAfterChange() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }
    func refresh() {
        guard !stopped else { return }
        generation += 1; let scanGeneration = generation
        writes.values.forEach { $0.cancel() }; writes.removeAll()
        scanning = true
        let inputs = NSScreen.screens.compactMap { screen -> DisplayState? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return DisplayState(id: id, key: Self.key(id), name: screen.localizedName,
                builtIn: CGDisplayIsBuiltin(id) != 0, method: .unavailable, level: 1, readable: false)
        }
        let softwareKeys = Set(UserDefaults.standard.stringArray(forKey: "display.software") ?? [])
        queue.async { [self] in
            var next: [UInt32: Route] = [:]
            var candidates: [(Int, BrightnessSupport.DisplayIdentity)] = []
            for (index, input) in inputs.enumerated() {
                var state = input
                let previous = routes[input.id].flatMap { $0.state.key == input.key ? $0 : nil }
                if let previous { state.level = previous.state.level }
                if !softwareKeys.contains(input.key), let get = BrightnessBridge.getBrightness {
                    var value: Float = -1
                    if get(input.id, &value) == 0, value.isFinite, value >= 0, value <= 1, BrightnessBridge.setBrightness != nil {
                        state.method = .system; state.level = Double(value); state.readable = true
                    }
                }
                next[input.id] = Route(state: state)
                if state.method != .system && !softwareKeys.contains(input.key) && !input.builtIn {
                    candidates.append((index, DisplayHardware.displayIdentity(input.id, info: DisplayHardware.displayInfoDictionary(input.id))))
                }
            }
            let services = candidates.isEmpty ? [] : DisplayHardware.externalServices()
            var scores: [(displayIndex: Int, serviceOrdinal: Int, score: Int)] = []
            for (index, identity) in candidates {
                for service in services {
                    scores.append((index, service.identity.ordinal, BrightnessSupport.matchScore(service: service.identity, display: identity)))
                }
            }
            let assignment = BrightnessSupport.assignServices(scores: scores)
            for (index, _) in candidates {
                let input = inputs[index]
                guard let ordinal = assignment[index], let service = services.first(where: { $0.identity.ordinal == ordinal }),
                      var route = next[input.id] else { continue }
                let probe = readDDC(id: input.id, service: service.service)
                if let value = probe.value {
                    route.state.method = .ddc; route.state.level = Double(value.current) / Double(max(1, value.maximum))
                    route.state.readable = true; route.maximum = max(1, value.maximum); route.service = service.service
                } else if probe.accepted {
                    route.state.method = .ddc; route.state.readable = false; route.service = service.service
                }
                next[input.id] = route
            }
            for input in inputs {
                guard var route = next[input.id] else { continue }
                if route.state.method == .unavailable {
                    if baselines[input.key] == nil { baselines[input.key] = captureGamma(input.id) }
                    if baselines[input.key] != nil { route.state.method = .software; route.state.readable = false }
                }
                if route.state.method != .software && dimmed.contains(input.key) {
                    if restoreGamma(input.id, key: input.key) { dimmed.remove(input.key) }
                }
                route.state.level = min(max(route.state.level, 0), 1)
                next[input.id] = route
            }
            routes = next
            // Retain baselines only while owned or connected; reconnecting IDs cannot inherit another display's curve.
            let connectedKeys = Set(inputs.map(\.key))
            baselines = baselines.filter { dimmed.contains($0.key) || connectedKeys.contains($0.key) }
            let output = inputs.compactMap { next[$0.id]?.state }
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped, self.generation == scanGeneration else { return }
                self.screens = output; self.scanning = false
            }
        }
    }

    func set(_ id: UInt32, level: Double) {
        guard !scanning, level.isFinite, let index = screens.firstIndex(where: { $0.id == id }), screens[index].method != .unavailable else { return }
        let level = min(max(level, 0), 1); let key = screens[index].key; let writeGeneration = generation
        screens[index].level = level; screens[index].error = nil
        writes[id]?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.queue.async { [self] in
                guard var route = self.routes[id], route.state.key == key, Self.key(id) == key else { return }
                var ok = false
                switch route.state.method {
                case .system: ok = BrightnessBridge.setBrightness?(id, Float(level)) == 0
                case .ddc:
                    if let service = route.service, let write = BrightnessBridge.writeI2C {
                        self.pace(id)
                        let value = UInt16((level * Double(route.maximum)).rounded())
                        var packet = BrightnessSupport.writePacket(code: 0x10, value: value)
                        for _ in 0..<2 {
                            usleep(10_000)
                            if write(service, 0x37, 0x51, &packet, UInt32(packet.count)) == 0 { ok = true }
                        }
                        self.recordEnd(id)
                    }
                case .software:
                    if self.baselines[key] == nil { self.baselines[key] = self.captureGamma(id) }
                    if let baseline = self.baselines[key] {
                        let factor = Float(max(0.12, level))
                        var r = baseline.red.map { $0 * factor }, g = baseline.green.map { $0 * factor }, b = baseline.blue.map { $0 * factor }
                        ok = CGSetDisplayTransferByTable(id, baseline.count, &r, &g, &b) == .success
                        if ok { self.dimmed.insert(key) }
                    }
                case .unavailable: break
                }
                if ok { route.state.level = level; self.routes[id] = route }
                let failed = !ok
                let previous = route.state.level
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.stopped, self.generation == writeGeneration,
                          let index = self.screens.firstIndex(where: { $0.id == id && $0.key == key }) else { return }
                    if failed {
                        self.screens[index].error = "调节未成功，请刷新或改用软件调暗。"
                        self.screens[index].level = previous
                    }
                }
            }
        }
        writes[id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    func preferSoftware(_ key: String, enabled: Bool) {
        var keys = Set(UserDefaults.standard.stringArray(forKey: "display.software") ?? [])
        if enabled { keys.insert(key) } else { keys.remove(key) }
        UserDefaults.standard.set(keys.sorted(), forKey: "display.software"); refresh()
    }
    func softwarePreferred(_ key: String) -> Bool { (UserDefaults.standard.stringArray(forKey: "display.software") ?? []).contains(key) }
    func restoreAllSoftware() {
        queue.async { [self] in
            for (id, var route) in routes where dimmed.contains(route.state.key) && Self.key(id) == route.state.key {
                if restoreGamma(id, key: route.state.key) {
                    dimmed.remove(route.state.key); route.state.level = 1; routes[id] = route
                }
            }
            DispatchQueue.main.async { [weak self] in self?.refresh() }
        }
    }
    func stop() {
        stopped = true; debounce?.cancel(); writes.values.forEach { $0.cancel() }
        queue.sync {
            for (id, route) in routes where dimmed.contains(route.state.key) && Self.key(id) == route.state.key { _ = restoreGamma(id, key: route.state.key) }
            dimmed.removeAll()
        }
    }
    private func captureGamma(_ id: UInt32) -> Gamma? {
        let capacity = min(CGDisplayGammaTableCapacity(id), 4096)
        guard capacity > 0 else { return nil }
        var r = [Float](repeating: 0, count: Int(capacity)), g = r, b = r; var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(id, capacity, &r, &g, &b, &count) == .success, count > 0 else { return nil }
        return Gamma(red: r, green: g, blue: b, count: count)
    }
    private func restoreGamma(_ id: UInt32, key: String) -> Bool {
        guard var table = baselines[key] else { return false }
        return CGSetDisplayTransferByTable(id, table.count, &table.red, &table.green, &table.blue) == .success
    }
    private func pace(_ id: UInt32) {
        let now = DispatchTime.now().uptimeNanoseconds / 1000
        let wait = BrightnessSupport.ddcCommandDelay(nowMicroseconds: now, lastCommandEndMicroseconds: commandEnds[id])
        if wait > 0 { usleep(wait) }
    }
    private func recordEnd(_ id: UInt32) { commandEnds[id] = DispatchTime.now().uptimeNanoseconds / 1000 }
    private func readDDC(id: UInt32, service: CFTypeRef) -> (value: (current: UInt16, maximum: UInt16)?, accepted: Bool) {
        guard let write = BrightnessBridge.writeI2C, let read = BrightnessBridge.readI2C else { return (nil, false) }
        var accepted = false
        for attempt in 0..<5 {
            pace(id)
            var request = BrightnessSupport.readRequestPacket(code: 0x10)
            for _ in 0..<(attempt == 4 ? 2 : 1) {
                usleep(10_000)
                if write(service, 0x37, 0x51, &request, UInt32(request.count)) == 0 { accepted = true }
            }
            usleep(50_000)
            var reply = [UInt8](repeating: 0, count: 11)
            let result = read(service, 0x37, 0, &reply, 11)
            recordEnd(id)
            if result == 0, let value = BrightnessSupport.parseReply(reply, code: 0x10) { return (value, accepted) }
        }
        return (nil, accepted)
    }
}

@Observable final class KeyboardLight {
    private(set) var level: Double = 0
    private(set) var supported = false
    private(set) var error: String?
    private(set) var automatic = false
    private(set) var autoSupported = false
    private(set) var suppressed = false
    @ObservationIgnored private var verification: DispatchWorkItem?
    @ObservationIgnored private var bridge = KeyboardLightBridge()
    init() { refresh() }
    func refresh() {
        if bridge == nil { bridge = KeyboardLightBridge() }
        guard let value = bridge?.brightness(), value.isFinite, value >= 0, value <= 1 else { supported = false; return }
        supported = true; level = Double(value)
        autoSupported = bridge?.autoBrightness != nil
        automatic = bridge?.autoBrightness ?? false
        suppressed = bridge?.suppressed ?? false
    }
    func setAutomatic(_ enabled: Bool) {
        guard bridge?.setAutoBrightness(enabled) == true else { error = "无法更改环境光自动调节，请在系统键盘设置中重试。"; return }
        error = nil; refresh()
    }
    func set(_ value: Double) {
        guard supported, value.isFinite else { return }
        // A saturated ambient-light sensor suppresses manual writes while auto-brightness is on.
        if automatic {
            guard bridge?.setAutoBrightness(false) == true else { error = "请先在系统键盘设置中关闭环境光自动调节。"; return }
            automatic = false
        }
        guard bridge?.setBrightness(Float(min(max(value, 0), 1))) == true else {
            error = "键盘背光调节失败，请在系统设置中检查自动亮度。"; return
        }
        error = nil; level = min(max(value, 0), 1)
        verification?.cancel()
        let requested = level
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.refresh()
            if abs(self.level - requested) > 0.03 { self.error = "系统未应用此亮度，请检查环境光、键盘状态后重试。" }
        }
        verification = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
