// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import IOKit.pwr_mgt
import IOKit.ps

@Observable final class KeepAwake {
    static let durations: [Double] = [30, 60, 120, 240, 480, 0]
    var preferredDuration = 60.0 { didSet { save() } }
    var preventSystem = true { didSet { save(); reconfigure() } }
    var preventDisplay = true { didSet { save(); reconfigure() } }
    var preventDisk = false { didSet { save(); reconfigure() } }
    var preventForcedSleep = false { didSet { save(); reconfigure() } }
    var onAC = false { didSet { save(); applyPowerRule() } }
    var onBattery = false { didSet { save(); applyPowerRule() } }
    private(set) var isActive = false
    private(set) var endDate: Date?
    private(set) var durationMinutes: Double?
    private(set) var error: String?
    private(set) var automatic = false
    private(set) var isOnAC = true
    @ObservationIgnored private var assertions: [IOPMAssertionID] = []
    @ObservationIgnored private var expiry: Timer?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?
    @ObservationIgnored private var powerInitialized = false

    @ObservationIgnored private var restoringPreferences = true
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        preventSystem = d.object(forKey: "awake.system") as? Bool ?? true
        preventDisplay = d.object(forKey: "awake.display") as? Bool ?? true
        preventDisk = d.bool(forKey: "awake.disk")
        preventForcedSleep = d.bool(forKey: "awake.forced")
        onAC = d.bool(forKey: "awake.ac")
        onBattery = d.bool(forKey: "awake.battery")
        let savedDuration = d.object(forKey: "awake.duration") as? Double ?? 60
        preferredDuration = Self.durations.contains(savedDuration) ? savedDuration : 60
        restoringPreferences = false
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let owner = Unmanaged<KeepAwake>.fromOpaque(context).takeUnretainedValue()
            owner.powerChanged()
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.checkExpiry() }
        powerChanged()
    }

    deinit {
        expiry?.invalidate()
        assertions.forEach { IOPMAssertionRelease($0) }
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    var selectedDuration: Double { isActive ? (durationMinutes ?? 0) : preferredDuration }

    func startPreferredSession() {
        start(minutes: preferredDuration == 0 ? nil : preferredDuration)
    }
    func changeDuration(_ minutes: Double) {
        guard Self.durations.contains(minutes) else { return }
        preferredDuration = minutes
        if isActive { startPreferredSession() }
    }

    func start(minutes: Double? = nil, automatic: Bool = false) {
        stop()
        let types = assertionTypes
        guard !types.isEmpty else { error = L("Select at least one sleep-prevention option."); return }
        var created: [IOPMAssertionID] = []
        for type in types {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                    L("1Tool Keep Awake") as CFString, &id)
            guard result == kIOReturnSuccess else {
                created.forEach { IOPMAssertionRelease($0) }
                error = LF("Could not keep awake (%d). Check your power source and try again.", result)
                return
            }
            created.append(id)
        }
        assertions = created
        durationMinutes = minutes.flatMap { $0 > 0 ? $0 : nil }
        isActive = true
        self.automatic = automatic
        error = nil
        if let minutes, minutes > 0 {
            endDate = Date().addingTimeInterval(minutes * 60)
            let timer = Timer(timeInterval: minutes * 60, repeats: false) { [weak self] _ in self?.stop() }
            expiry = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        expiry?.invalidate(); expiry = nil
        assertions.forEach { IOPMAssertionRelease($0) }; assertions.removeAll()
        isActive = false; automatic = false; endDate = nil; durationMinutes = nil
    }

    var assertionTypes: [String] {
        var result: [String] = []
        if preventSystem { result.append("PreventUserIdleSystemSleep") }
        if preventDisplay { result.append("PreventUserIdleDisplaySleep") }
        if preventDisk { result.append("PreventDiskIdle") }
        if preventForcedSleep && isOnAC { result.append("PreventSystemSleep") }
        return result
    }

    func checkExpiry() { if let endDate, endDate <= Date() { stop() } }
    private func reconfigure() {
        guard isActive else { return }
        let remaining = endDate.map { max(0, $0.timeIntervalSinceNow / 60) }
        let wasAutomatic = automatic
        let originalDuration = durationMinutes
        if let remaining, remaining <= 0 { stop(); return }
        start(minutes: remaining, automatic: wasAutomatic)
        durationMinutes = originalDuration
    }
    private func powerChanged() {
        var nextOnAC = isOnAC
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            nextOnAC = type as String == kIOPSACPowerValue
        }
        // Battery percentage updates must not restart a manually ended session.
        guard !powerInitialized || nextOnAC != isOnAC else { return }
        powerInitialized = true
        isOnAC = nextOnAC
        reconfigure()
        applyPowerRule()
    }
    private func applyPowerRule() {
        guard !restoringPreferences else { return }
        let requested = isOnAC ? onAC : onBattery
        if requested && !isActive { start(automatic: true) }
        else if !requested && automatic { stop() }
    }
    private func save() {
        guard !restoringPreferences else { return }
        let d = defaults
        d.set(preferredDuration, forKey: "awake.duration")
        d.set(preventSystem, forKey: "awake.system"); d.set(preventDisplay, forKey: "awake.display")
        d.set(preventDisk, forKey: "awake.disk"); d.set(preventForcedSleep, forKey: "awake.forced")
        d.set(onAC, forKey: "awake.ac"); d.set(onBattery, forKey: "awake.battery")
    }
}
