// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation
import Darwin

// Compiled into both the host and its sandboxed Finder Sync extension.
enum SuperRightClickIPC {
    static let prefix = "com.shopkivoo.onetool.super-right-click"
    static let request = Notification.Name(prefix + ".request")
    static let configuration = Notification.Name(prefix + ".configuration")
    static let action = Notification.Name(prefix + ".action")

    static func encode<T: Encodable>(_ value: T) -> String? {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) }
    }
    static func decode<T: Decodable>(_ type: T.Type, from value: Any?) -> T? {
        guard let raw = value as? String, raw.utf8.count <= 256 * 1024 else { return nil }
        return try? JSONDecoder().decode(type, from: Data(raw.utf8))
    }
}

/// Finder registers scopes per volume. Virtual views may have selected items
/// without exposing a directory target; use those real URLs for item actions.
enum SuperRightClickScope {
    static func directories(volumes: [URL]) -> Set<URL> {
        Set(([URL(fileURLWithPath: "/"), URL(fileURLWithPath: "/System/Volumes/Data")]
             + volumes.filter(\.isFileURL)).map(\.standardizedFileURL))
    }

    static func target(targeted: URL?, selection: [URL]) -> URL? {
        ([targeted].compactMap { $0 } + selection).first {
            $0.isFileURL && $0.path.hasPrefix("/") && !$0.path.contains("\0")
        }
    }
}

enum SuperRightClickGroup: String, Codable, CaseIterable, Identifiable {
    case newFile, directories, copyPath, openWith
    var id: String { rawValue }
    func title(chinese: Bool) -> String {
        switch self {
        case .newFile: return chinese ? "新建文件" : "New File"
        case .directories: return chinese ? "常用目录" : "Favorite Folders"
        case .copyPath: return chinese ? "复制路径" : "Copy Path"
        case .openWith: return chinese ? "快捷操作" : "Quick Actions"
        }
    }
}

struct SuperRightClickEntry: Codable, Identifiable, Equatable {
    var id = UUID().uuidString
    var name: String
    // A file extension for templates; an absolute path for folders/apps.
    var value: String
    var content = ""
}

struct SuperRightClickConfiguration: Codable, Equatable {
    var enabled = false
    var chinese = true
    var token = ""
    var order = SuperRightClickGroup.allCases
    var hiddenGroups: [SuperRightClickGroup] = []
    var showHiddenToggle = true
    var templates = [
        SuperRightClickEntry(name: "TXT", value: "txt"),
        SuperRightClickEntry(name: "Markdown", value: "md"),
        SuperRightClickEntry(name: "JSON", value: "json", content: "{}\n"),
    ]
    var directories: [SuperRightClickEntry] = []
    var applications = [SuperRightClickEntry(name: "Terminal", value: "/System/Applications/Utilities/Terminal.app")]
    var disabledApplications: [String] = []

    var visibleGroups: [SuperRightClickGroup] {
        var seen = Set<SuperRightClickGroup>()
        return (order + SuperRightClickGroup.allCases).filter {
            seen.insert($0).inserted && !hiddenGroups.contains($0)
        }
    }
    static func initial(home: URL) -> Self {
        var config = Self()
        config.directories = ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Movies"].map {
            SuperRightClickEntry(name: $0, value: home.appendingPathComponent($0).path)
        }
        if FileManager.default.fileExists(atPath: "/Applications/iTerm.app") {
            config.applications.append(SuperRightClickEntry(name: "iTerm2", value: "/Applications/iTerm.app"))
        }
        return config
    }
}

extension SuperRightClickConfiguration {
    private enum CodingKeys: String, CodingKey {
        case enabled, chinese, token, order, hiddenGroups, showHiddenToggle
        case templates, directories, applications, disabledApplications
    }
    // Preserve configurations saved before per-app switches were introduced.
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? enabled
        chinese = try values.decodeIfPresent(Bool.self, forKey: .chinese) ?? chinese
        token = try values.decodeIfPresent(String.self, forKey: .token) ?? token
        order = try values.decodeIfPresent([SuperRightClickGroup].self, forKey: .order) ?? order
        hiddenGroups = try values.decodeIfPresent([SuperRightClickGroup].self, forKey: .hiddenGroups) ?? hiddenGroups
        showHiddenToggle = try values.decodeIfPresent(Bool.self, forKey: .showHiddenToggle) ?? showHiddenToggle
        templates = try values.decodeIfPresent([SuperRightClickEntry].self, forKey: .templates) ?? templates
        directories = try values.decodeIfPresent([SuperRightClickEntry].self, forKey: .directories) ?? directories
        applications = try values.decodeIfPresent([SuperRightClickEntry].self, forKey: .applications) ?? applications
        disabledApplications = try values.decodeIfPresent([String].self, forKey: .disabledApplications) ?? []
    }
}

enum SuperRightClickApplications {
    // Supported terminals, editors and IDEs. Resolve installed bundles through
    // Launch Services instead of presenting an unfiltered catalog of all apps.
    static let supportedBundleIDs = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders", "com.apple.dt.Xcode", "com.sublimetext.4",
        "com.sublimetext.3", "com.barebones.bbedit", "com.coteditor.CotEditor",
        "dev.zed.Zed", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce", "com.jetbrains.CLion", "com.jetbrains.WebStorm",
        "com.jetbrains.PhpStorm", "com.jetbrains.rubymine", "com.jetbrains.goland",
        "com.jetbrains.rider",
    ]
    static func available(custom: [SuperRightClickEntry], detected: [SuperRightClickEntry],
                          isInstalled: (String) -> Bool) -> [SuperRightClickEntry] {
        var paths = Set<String>()
        return (custom + detected).filter {
            isInstalled($0.value) && paths.insert(URL(fileURLWithPath: $0.value).standardizedFileURL.path).inserted
        }
    }
}

struct SuperRightClickRequest: Codable {
    var token: String
    var action: String
    var entryID: String?
    var directory: String
    var selection: [String]
}

enum SuperRightClickFiles {
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".."
            && !name.contains("/") && !name.contains(":") && !name.contains("\0")
            && name.utf8.count <= 255
    }
    static func directory(_ path: String) -> URL? {
        guard path.hasPrefix("/"), !path.contains("\0") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
        return url
    }
    static func insertionDirectory(target: String, selection: [String]) -> URL? {
        // Resolve metadata in the host, which can access the Finder target;
        // the sandboxed extension need not read arbitrary filesystem metadata.
        guard target.hasPrefix("/"), !target.contains("\0") else { return nil }
        if selection.count == 1, let selectedFolder = directory(selection[0]) { return selectedFolder }
        if let folder = directory(target) { return folder }
        // Tags and searches can supply a virtual target. Resolve the selected
        // item's parent instead of creating a file beside a saved search.
        if let first = selection.first, first.hasPrefix("/"), !first.contains("\0"),
           let parent = directory(URL(fileURLWithPath: first).deletingLastPathComponent().path) {
            return parent
        }
        return directory(URL(fileURLWithPath: target).deletingLastPathComponent().path)
    }
    // O_EXCL prevents overwrites, including dangling symlinks and races.
    static func create(name: String, in directory: URL, content: Data) throws -> URL {
        guard validName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
        let url = directory.appendingPathComponent(name)
        let fd = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        do {
            try content.withUnsafeBytes { buffer in
                var offset = 0
                while offset < buffer.count {
                    let count = write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
                    offset += count
                }
            }
        } catch {
            unlink(url.path)
            throw error
        }
        return url
    }
}
