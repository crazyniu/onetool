// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ToolSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !title.isEmpty { Text(title).font(.headline).foregroundStyle(.secondary).padding(.horizontal, 2) }
            VStack(alignment: .leading, spacing: Layout.rowSpacing) { content }
                .padding(Layout.groupPadding).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Layout.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Layout.cornerRadius).stroke(Theme.border, lineWidth: 0.5))
        }
    }
}
struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}
struct ErrorText: View {
    let error: String?
    var body: some View {
        if let error { Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
    }
}
struct SettingToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var value: Bool
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                if let subtitle { HelpText(subtitle) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(title)
        }.padding(.vertical, 2)
    }
}
/// Native menu rendering, with a trailing frame shared by every settings row.
struct ChoiceMenu<Content: View>: View {
    let title: String
    let value: String
    var width: CGFloat = 180
    @ViewBuilder var content: Content
    var body: some View {
        Menu { content } label: { Text(value).lineLimit(1).truncationMode(.middle).frame(maxWidth: width - 36, alignment: .trailing) }
            .menuStyle(.button).buttonStyle(.bordered).fixedSize()
            .frame(width: width, alignment: .trailing)
            .help(value).accessibilityLabel(title).accessibilityValue(value)
    }
}

struct PermissionHelpButton: View {
    var body: some View {
        Button(L("Permissions"), systemImage: "lock.shield") { AppModel.shared.page = .permissions }
    }
}

struct AboutPage: View {
    @Environment(\.toolAccent) private var accent
    private let source = URL(string: "https://github.com/crazyniu/onetool")!
    var body: some View {
        HStack(spacing: 18) {
            BrandLogo(size: 64)
            VStack(alignment: .leading, spacing: 5) {
                Text("1Tool").font(.system(size: 28, weight: .semibold))
                Text(LF("Version %@ · Build %@", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0", Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12)
        ToolSection(title: L("Open Source")) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Source Code")).fontWeight(.medium)
                    Text("github.com/crazyniu/onetool").font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer()
                Link(destination: source) { Label(L("View on GitHub"), systemImage: "arrow.up.right") }
            }
            Divider()
            HStack {
                Text(L("License")); Spacer(); Text("GPL-3.0-or-later").foregroundStyle(.secondary)
                Button(L("View")) {
                    if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") { NSWorkspace.shared.open(url) }
                }
            }
            Link(L("Report an Issue"), destination: source.appendingPathComponent("issues"))
        }
        ToolSection(title: L("Built with Care")) {
            HelpText(L("Native macOS controls. Local processing. No account required."))
            HStack {
                Text(L("Cleanup References")).font(.callout)
                Spacer()
                Link("Mole", destination: URL(string: "https://github.com/tw93/Mole")!)
                Link("PureMac", destination: URL(string: "https://github.com/momenbasel/PureMac")!)
            }
            HelpText(L("Cleanup uses an allowlist, previews every selection, and rechecks files before changing them."))
            Button(L("Open Source Notices")) {
                if let url = Bundle.main.url(forResource: "NOTICE", withExtension: "md") { NSWorkspace.shared.open(url) }
            }
        }
    }
}
