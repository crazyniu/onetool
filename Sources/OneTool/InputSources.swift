// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import Carbon.HIToolbox

struct InputRule: Codable, Identifiable, Equatable {
    var id: String // application bundle identifier
    var name: String
    var path: String
    var sourceID: String
}

@Observable final class InputSources {
    var enabled = false { didSet { save(); scheduleSwitch() } }
    var fallback = "" { didSet { save() } }
    var clearCapsLock = true { didSet { save() } }
    var rules: [InputRule] = [] { didSet { save() } }
    private(set) var sources: [InputSourceSelection.Reading] = []
    private(set) var currentName = ""
    private(set) var error: String?
    @ObservationIgnored private var activation: NSObjectProtocol?
    @ObservationIgnored private var sourceObserver: NSObjectProtocol?
    @ObservationIgnored private var pending: DispatchWorkItem?

    @ObservationIgnored private var restoringPreferences = true
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        enabled = d.bool(forKey: "input.enabled")
        fallback = d.string(forKey: "input.fallback") ?? ""
        clearCapsLock = d.object(forKey: "input.caps") as? Bool ?? true
        if let data = d.data(forKey: "input.rules"), let saved = try? JSONDecoder().decode([InputRule].self, from: data) { rules = saved }
        restoringPreferences = false
        refresh()
        activation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleSwitch() }
        sourceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }
    deinit {
        pending?.cancel()
        if let activation { NSWorkspace.shared.notificationCenter.removeObserver(activation) }
        if let sourceObserver { DistributedNotificationCenter.default().removeObserver(sourceObserver) }
    }
    func refresh() {
        sources = InputSourceSelection.availableReadings()
        currentName = InputSourceSelection.currentReading()?.name ?? L("Unavailable")
    }
    static func target(bundleID: String, rules: [InputRule], fallback: String, available: [String]) -> String? {
        let id = rules.first { $0.id == bundleID }?.sourceID ?? fallback
        return !id.isEmpty && available.contains(id) ? id : nil
    }
    func scheduleSwitch() {
        pending?.cancel(); error = nil
        guard enabled, let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              id != Bundle.main.bundleIdentifier else { return }
        let pid = app.processIdentifier
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self.refresh()
            let configured = self.rules.first { $0.id == id }?.sourceID ?? self.fallback
            guard !configured.isEmpty else { return }
            guard let target = Self.target(bundleID: id, rules: self.rules, fallback: self.fallback,
                                           available: self.sources.map(\.id)) else {
                self.error = L("The input source is disabled. Enable it in System Settings or choose another one."); return
            }
            let selected = InputSourceSelection.currentReading()?.id == target || InputSourceSelection.select(sourceID: target)
            guard selected else {
                self.error = L("Could not switch input sources. Choose another one and try again.")
                self.refresh()
                return
            }
            if self.clearCapsLock, case .failure(let failure) = DefaultInputSourceCapsLock.clearResult() {
                self.error = failure.message
            }
            self.refresh()
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func addApplication() {
        let panel = NSOpenPanel()
        panel.title = L("Choose an App"); panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false; panel.allowedContentTypes = [.application]
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        guard !rules.contains(where: { $0.id == id }) else { return }
        rules.append(InputRule(id: id, name: FileManager.default.displayName(atPath: url.path), path: url.path,
                               sourceID: fallback.isEmpty ? (sources.first?.id ?? "") : fallback))
    }
    private func save() {
        // Observation setters also run during initialization; finish reading before writing.
        guard !restoringPreferences else { return }
        let d = defaults
        d.set(enabled, forKey: "input.enabled"); d.set(fallback, forKey: "input.fallback")
        d.set(clearCapsLock, forKey: "input.caps"); d.set(try? JSONEncoder().encode(rules), forKey: "input.rules")
    }
}
