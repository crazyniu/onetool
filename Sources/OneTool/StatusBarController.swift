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
        // The old SF Symbols placeholder is reset once; later symbol choices are intentional.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "appearance.brandIconMigrated") {
            defaults.set("", forKey: "appearance.icon")
            defaults.set(true, forKey: "appearance.brandIconMigrated")
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
        item.button?.image = BrandGlyph.image(active: model.awake.isActive,
            showDot: UserDefaults.standard.object(forKey: "appearance.activeDot") as? Bool ?? true)
        item.button?.toolTip = model.awake.isActive ? L("1Tool · Keeping Awake") : L("1Tool · Click for Quick Panel; right-click for menu")
        let scheme = UserDefaults.standard.string(forKey: "appearance.scheme") ?? "system"
        let appearance = scheme == "dark" ? NSAppearance(named: .darkAqua)
            : scheme == "light" ? NSAppearance(named: .aqua) : nil
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
        if panel.appearance?.name != appearance?.name { panel.appearance = appearance }
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
        menu.addItem(withTitle: model.awake.isActive ? L("Status: Active") : L("Status: Inactive"), action: nil, keyEquivalent: "")
        add(model.awake.isActive ? L("Stop Keeping Awake") : L("Start Keeping Awake"), to: menu, action: #selector(toggleAwake))
        let duration = NSMenuItem(title: L("Keep Awake For…"), action: nil, keyEquivalent: "")
        let options = NSMenu()
        for (title, minutes) in [(L("30 min"), 30), (L("1 hr"), 60), (L("2 hr"), 120), (L("4 hr"), 240), (L("8 hr"), 480), (L("∞ Indefinitely"), 0)] {
            let entry = NSMenuItem(title: title, action: #selector(startDuration(_:)), keyEquivalent: "")
            entry.target = self; entry.tag = minutes; options.addItem(entry)
        }
        duration.submenu = options; menu.addItem(duration)
        menu.addItem(.separator())
        add(L("Open Settings…"), to: menu, action: #selector(openSettings), key: ",")
        add(L("Change Menu Bar Icon…"), to: menu, action: #selector(openAppearance))
        menu.addItem(.separator())
        add(L("Quit 1Tool"), to: menu, action: #selector(quit), key: "q")
        return menu
    }
    private func add(_ title: String, to menu: NSMenu, action: Selector, key: String = "") {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self; menu.addItem(entry)
    }
    @objc private func toggleAwake() { if model.awake.isActive { model.awake.stop() } else { model.awake.start() } }
    @objc private func startDuration(_ sender: NSMenuItem) { model.awake.start(minutes: sender.tag == 0 ? nil : Double(sender.tag)) }
    @objc private func openSettings() { model.openMainWindow?(.awake) }
    @objc private func openAppearance() { model.openMainWindow?(.appearance) }
    @objc private func quit() { NSApp.terminate(nil) }
}
