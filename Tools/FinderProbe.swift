// SPDX-License-Identifier: GPL-3.0-or-later
// Integration probe for the real host/extension IPC. Uses only a caller-supplied test directory.
import AppKit

@main struct FinderProbe {
    static func main() {
        guard CommandLine.arguments.count == 3 else { print("Usage: FinderProbe <copyPath|newFile|hiddenFiles|terminal> <test-directory>"); exit(2) }
        let action = CommandLine.arguments[1]
        let directory = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL.path
        guard FileManager.default.fileExists(atPath: directory), ["copyPath", "newFile", "hiddenFiles", "terminal"].contains(action) else { exit(2) }
        let center = DistributedNotificationCenter.default()
        var config: SuperRightClickConfiguration?
        let observer = center.addObserver(forName: SuperRightClickIPC.configuration, object: nil, queue: .main) { note in
            config = SuperRightClickIPC.decode(SuperRightClickConfiguration.self, from: note.object)
        }
        defer { center.removeObserver(observer) }
        center.postNotificationName(SuperRightClickIPC.request, object: nil, userInfo: nil, deliverImmediately: true)
        let deadline = Date().addingTimeInterval(3)
        while config == nil && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        guard let config, config.enabled else { print("FAIL: running host configuration unavailable or disabled"); exit(1) }
        print("HOST CONFIG: enabled, \(config.templates.count) templates, \(config.applications.count) installed app shortcuts")
        let actual = action == "terminal" ? "application" : action
        let entry = action == "newFile" ? config.templates.first(where: { $0.value == "json" })?.id
            : action == "terminal" ? config.applications.first(where: { Bundle(path: $0.value)?.bundleIdentifier == "com.apple.Terminal" })?.id : nil
        if ["newFile", "terminal"].contains(action) && entry == nil { print("FAIL: entry unavailable"); exit(1) }
        let request = SuperRightClickRequest(token: config.token, action: actual, entryID: entry, directory: directory, selection: [])
        let pasteboard = NSPasteboard.general
        let clipboardSnapshot: [NSPasteboardItem] = action == "copyPath" ? (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types { if let data = original.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } : []
        defer {
            if action == "copyPath" { pasteboard.clearContents(); if !clipboardSnapshot.isEmpty { pasteboard.writeObjects(clipboardSnapshot) } }
        }
        guard let raw = SuperRightClickIPC.encode(request) else { exit(1) }
        center.postNotificationName(SuperRightClickIPC.action, object: raw, userInfo: nil, deliverImmediately: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        if action == "copyPath" {
            guard pasteboard.string(forType: .string) == directory else { print("FAIL: copy path content mismatch"); exit(1) }
            print("PASS: real host copy-path action; original clipboard restored on exit")
        }
        print("SENT: " + action + " (completion must be checked in host/UI)")
    }
}
