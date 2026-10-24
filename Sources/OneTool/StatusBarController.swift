// SPDX-License-Identifier: GPL-3.0-or-later
// Native left/right status-button dispatch adapted from the reference StatusItemController.
import SwiftUI
import Observation

@MainActor final class StatusBarController: NSObject {
    private let model: AppModel
    private let item: NSStatusItem
    private let panel = StatusPanel(contentRect: NSRect(x: 0, y: 0, width: 365, height: 490),
        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let anchor = StatusPanelAnchor()
    private var panelHeight: CGFloat = 480
    private var preferences: NSObjectProtocol?
    private var outsideClick: Any?
    private var localClick: Any?

    init(model: AppModel) {
        self.model = model
        let defaults = UserDefaults.standard
        // Retired, ambiguous presets return to the original 1Tool mark.
        defaults.set(StatusIconSelection.sanitized(defaults.string(forKey: "appearance.icon")), forKey: "appearance.icon")
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.autosaveName = "com.shopkivoo.onetool.status"
        item.behavior = []
        item.isVisible = true
        if let button = item.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("1Tool")
        }
        let host = NSHostingController(rootView: QuickPanelRoot(model: model, anchor: anchor,
            maximumHeight: { [weak self] in
                max(120, (self?.item.button?.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 800) - 40)
            }, onHeightChange: { [weak self] height in
                self?.resizePanel(to: height)
            }))
        panel.contentViewController = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        model.dismissQuickPanel = { [weak self] in self?.panel.orderOut(nil) }
        panel.setAccessibilityTitle(L("1Tool Quick Panel"))
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.panel.orderOut(nil) }
        }
        localClick = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                if let self, event.window !== self.panel, event.window !== self.item.button?.window { self.panel.orderOut(nil) }
            }
            return event
        }
        preferences = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshAppearance() }
            }
        observeAwakeState()
        refreshAppearance()
    }
    private func resizePanel(to height: CGFloat) {
        panelHeight = height
        // Defer AppKit window resizing until SwiftUI completes the content layout.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.positionPanel()
        }
    }
    deinit {
        if let preferences { NotificationCenter.default.removeObserver(preferences) }
        if let outsideClick { NSEvent.removeMonitor(outsideClick) }
        if let localClick { NSEvent.removeMonitor(localClick) }
        NSStatusBar.system.removeStatusItem(item)
    }
    private func observeAwakeState() {
        withObservationTracking {
            _ = model.awake.isActive
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.refreshAppearance(); self?.observeAwakeState() }
        }
    }
    private func refreshAppearance() {
        panel.setAccessibilityTitle(L("1Tool Quick Panel"))
        item.button?.image = BrandGlyph.image(active: model.awake.isActive)
        item.button?.toolTip = model.awake.isActive ? L("1Tool · Keeping Awake") : L("1Tool · Click for Quick Panel; right-click for menu")
        // Both windows inherit the live system appearance. Retired app-local
        // theme preferences never change macOS during startup.
        if NSApp.appearance != nil { NSApp.appearance = nil }
        if panel.appearance != nil { panel.appearance = nil }
    }
    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else { togglePanel() }
    }
    func togglePanel() {
        if panel.isVisible { panel.orderOut(nil) }
        else {
            model.refresh(); model.displays.refresh()
            positionPanel()
            panel.makeKeyAndOrderFront(nil)
        }
    }
    private func positionPanel() {
        guard let button = item.button, let window = button.window,
              let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let buttonFrame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let height = panelHeight + 10
        let x = min(max(buttonFrame.midX - 182.5, screen.minX + 8), screen.maxX - 373)
        anchor.arrowX = buttonFrame.midX - x
        panel.setFrame(NSRect(x: x, y: max(screen.minY + 8, buttonFrame.minY - height - 2), width: 365, height: height), display: panel.isVisible)
    }
    func showMenu() {
        guard let button = item.button else { return }
        panel.orderOut(nil)
        // Anchor directly to the status button. Replaying its click would re-enter
        // the custom left/right dispatcher on some macOS releases.
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        add(model.awake.isActive ? L("Stop Keeping Awake") : L("Start Keeping Awake"), to: menu, action: #selector(toggleAwake))
        let duration = NSMenuItem(title: model.awake.isActive ? L("Change Duration…") : L("Keep Awake For…"), action: nil, keyEquivalent: "")
        let options = NSMenu()
        for (title, minutes) in [(L("30 min"), 30), (L("1 hr"), 60), (L("2 hr"), 120), (L("4 hr"), 240), (L("8 hr"), 480), (L("∞ Indefinitely"), 0)] {
            let entry = NSMenuItem(title: title, action: #selector(startDuration(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = minutes
            entry.state = model.awake.selectedDuration == Double(minutes) ? .on : .off
            options.addItem(entry)
        }
        duration.submenu = options; menu.addItem(duration)
        menu.addItem(.separator())
        model.systemTheme.refresh()
        let appearance = NSMenuItem(title: L("System Appearance"), action: nil, keyEquivalent: "")
        let themes = NSMenu()
        for (index, mode) in SystemThemeMode.allCases.enumerated() {
            let entry = NSMenuItem(title: mode.title, action: #selector(setSystemTheme(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = index
            entry.state = model.systemTheme.state.mode == mode ? .on : .off
            entry.isEnabled = model.systemTheme.canChange && !model.systemTheme.isChanging
            themes.addItem(entry)
        }
        themes.autoenablesItems = false
        themes.addItem(.separator())
        add(L("System Settings…"), to: themes, action: #selector(openSystemAppearance))
        appearance.submenu = themes; menu.addItem(appearance)
        addNetworkMenu(to: menu)
        menu.addItem(.separator())
        add(L("Open Settings…"), to: menu, action: #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add(L("Quit 1Tool"), to: menu, action: #selector(quit), key: "q")
        return menu
    }
    private func addNetworkMenu(to menu: NSMenu) {
        model.network.refresh()
        let network = model.network
        let root = NSMenuItem(title: L("DNS & Router"), action: nil, keyEquivalent: "")
        let choices = NSMenu()
        choices.autoenablesItems = false
        for profile in network.profiles {
            let entry = NSMenuItem(title: profile.address, action: #selector(switchNetwork(_:)), keyEquivalent: "")
            entry.target = self; entry.representedObject = profile.id.uuidString
            entry.state = network.isActive(profile) ? .on : .off
            entry.isEnabled = !network.isChanging && !network.isActive(profile) && network.current?.canSwitch == true
            choices.addItem(entry)
        }
        if network.profiles.isEmpty {
            let empty = NSMenuItem(title: L("No Saved Routers"), action: nil, keyEquivalent: "")
            empty.isEnabled = false; choices.addItem(empty)
        }
        choices.addItem(.separator())
        add(L("Manage Routers…"), to: choices, action: #selector(openNetworkSettings))
        root.submenu = choices; menu.addItem(root)
    }
    @objc private func switchNetwork(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let profile = model.network.profiles.first(where: { $0.id.uuidString == id }) else { return }
        Task {
            await model.network.requestSwitch(profile)
            if model.network.error != nil || model.network.pendingDHCP != nil { model.openMainWindow?(.network) }
        }
    }
    @objc private func openNetworkSettings() { model.openMainWindow?(.network) }
    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self; menu.addItem(entry)
    }
    @objc private func toggleAwake() { if model.awake.isActive { model.awake.stop() } else { model.awake.startPreferredSession() } }
    @objc private func startDuration(_ sender: NSMenuItem) {
        let wasActive = model.awake.isActive
        model.awake.changeDuration(Double(sender.tag))
        if !wasActive { model.awake.startPreferredSession() }
    }
    @objc private func setSystemTheme(_ sender: NSMenuItem) {
        guard SystemThemeMode.allCases.indices.contains(sender.tag) else { return }
        Task {
            await model.systemTheme.set(SystemThemeMode.allCases[sender.tag])
            if model.systemTheme.error != nil { model.openMainWindow?(.appearance) }
        }
    }
    @objc private func openSystemAppearance() { SystemTheme.openSettings() }
    @objc private func openSettings() { model.openMainWindow?(.appearance) }
    @objc private func quit() { NSApp.terminate(nil) }
}
