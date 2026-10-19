// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Text presets stay editable; Office documents use real bundled blank files.
enum SuperRightClickTemplatePreset: String, CaseIterable, Identifiable {
    case txt, md, html, js, json, csv, xml, py, sh, docx, xlsx, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .docx: return "Word (.docx)"
        case .xlsx: return "Excel (.xlsx)"
        case .custom: return ""
        default: return rawValue.uppercased() + " (." + rawValue + ")"
        }
    }

    var entry: SuperRightClickEntry {
        let content: String
        switch self {
        case .html:
            content = "<!DOCTYPE html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <title></title>\n</head>\n<body>\n</body>\n</html>\n"
        case .json: content = "{}\n"
        case .xml: content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root/>\n"
        case .sh: content = "#!/bin/sh\n"
        default: content = ""
        }
        let name = self == .docx ? "Word" : self == .xlsx ? "Excel" : rawValue.uppercased()
        return SuperRightClickEntry(name: self == .custom ? "" : name,
                                    value: self == .custom ? "" : rawValue, content: content)
    }
}

enum SuperRightClickTemplates {
    static func normalizedExtension(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if result.hasPrefix(".") { result.removeFirst() }
        return result
    }

    static func validExtension(_ value: String) -> Bool {
        let value = normalizedExtension(value)
        return !value.isEmpty && value.utf8.count <= 32 && value.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-")
        }
    }

    static func isOffice(_ value: String) -> Bool {
        ["docx", "xlsx"].contains(normalizedExtension(value))
    }

    static func data(for entry: SuperRightClickEntry?, resourceDirectory: URL?) throws -> Data {
        guard let entry else { return Data() }
        let ext = normalizedExtension(entry.value)
        guard isOffice(ext) else { return Data(entry.content.utf8) }
        guard let resourceDirectory else { throw CocoaError(.fileNoSuchFile) }
        return try Data(contentsOf: resourceDirectory.appendingPathComponent("Blank." + ext))
    }
}
