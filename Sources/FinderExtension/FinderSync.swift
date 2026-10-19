// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import FinderSync

@objc(OneToolFinderSync)
final class OneToolFinderSync: FIFinderSync {
    private var config = SuperRightClickConfiguration()
    private var requests: [Int: SuperRightClickRequest] = [:]
    private var nextTag = 0

    override init() {
        super.init()
        // A root on the startup volume does not cover separately mounted disks.
        // Keep scope registered while disabled so existing windows keep menus.
        refreshDirectories()
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self, selector: #selector(refreshDirectories), name: name, object: nil)
        }
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(receiveConfiguration(_:)),
            name: SuperRightClickIPC.configuration, object: nil)
        requestConfiguration()
    }
    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func refreshDirectories() {
        let volumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        FIFinderSyncController.default().directoryURLs = SuperRightClickScope.directories(volumes: volumes)
    }

    private func requestConfiguration() {
        DistributedNotificationCenter.default().postNotificationName(
            SuperRightClickIPC.request, object: nil, userInfo: nil, deliverImmediately: true)
    }
    @objc private func receiveConfiguration(_ notification: Notification) {
        guard let value = SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: notification.object) else { return }
        guard value != config else { return }
        config = value
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        requestConfiguration()
        guard config.enabled,
              menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else { return nil }
        let controller = FIFinderSyncController.default()
        let selected = menuKind == .contextualMenuForItems ? (controller.selectedItemURLs() ?? []) : []
        guard let target = SuperRightClickScope.target(targeted: controller.targetedURL(),
                                                     selection: selected) else { return nil }
        let menu = NSMenu()
        // Keep recent snapshots for menus in other Finder windows. Never reuse
        // a tag for a different selection while an older menu might be open.
        if requests.count > 512 {
            for tag in requests.keys.sorted().prefix(requests.count - 256) { requests.removeValue(forKey: tag) }
        }
        func item(_ title: String, action: String, entry: String? = nil, image: NSImage? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(performAction(_:)), keyEquivalent: "")
            item.image = image
            item.target = self
            // Finder serializes NSMenuItems across processes. Only the tag is
            // a reliable action identifier; arbitrary representedObject is lost.
            nextTag += 1
            item.tag = nextTag
            requests[item.tag] = SuperRightClickRequest(
                token: config.token, action: action, entryID: entry,
                directory: target.path, selection: selected.map(\.path))
            return item
        }
        for group in config.visibleGroups {
            if group == .copyPath {
                menu.addItem(item(group.title(chinese: config.chinese), action: "copyPath",
                                  image: menuIcon("link", color: .systemGreen)))
                continue
            }
            let parent = NSMenuItem(title: group.title(chinese: config.chinese), action: nil, keyEquivalent: "")
            let sub = NSMenu()
            switch group {
            case .newFile:
                parent.image = menuIcon("doc.badge.plus", color: .systemGreen)
                sub.addItem(item(config.chinese ? "输入文件名…" : "Choose File Name…", action: "newFile",
                                 image: menuIcon("square.and.pencil", color: .systemOrange)))
                for entry in config.templates {
                    sub.addItem(item(entry.name, action: "newFile", entry: entry.id,
                                     image: menuIcon("doc.text", color: .systemBlue)))
                }
            case .directories:
                parent.image = menuIcon("heart.fill", color: .systemRed)
                for entry in config.directories {
                    sub.addItem(item(entry.name, action: "directory", entry: entry.id,
                                     image: menuIcon("folder.fill", color: .systemBlue)))
                }
            case .openWith:
                parent.image = menuIcon("bolt.fill", color: .systemOrange)
                for entry in config.applications {
                    sub.addItem(item(entry.name, action: "application", entry: entry.id,
                                     image: menuImage(NSWorkspace.shared.icon(forFile: entry.value))))
                }
                if config.showHiddenToggle {
                    sub.addItem(item(config.chinese ? "显示／隐藏隐藏文件" : "Show / Hide Hidden Files", action: "hiddenFiles",
                                     image: menuIcon("eye", color: .systemPurple)))
                }
            case .copyPath: break
            }
            if !sub.items.isEmpty { parent.submenu = sub; menu.addItem(parent) }
        }
        return menu.items.isEmpty ? nil : menu
    }

    private func menuIcon(_ symbol: String, color: NSColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration) else { return nil }
        return menuImage(image)
    }

    private func menuImage(_ source: NSImage) -> NSImage {
        // Render pixels before Finder serializes the menu, preserving color
        // instead of letting template-symbol tinting turn the icon monochrome.
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size)
        image.lockFocus()
        source.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    @objc private func performAction(_ sender: NSMenuItem) {
        guard let request = requests[sender.tag],
              let raw = SuperRightClickIPC.encode(request) else { return }
        // Sandbox notifications carry an object string, never userInfo.
        DistributedNotificationCenter.default().postNotificationName(
            SuperRightClickIPC.action, object: raw, userInfo: nil, deliverImmediately: true)
    }
}
