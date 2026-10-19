// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct BrandLogo: View {
    var size: CGFloat = 32
    var body: some View {
        Image(nsImage: BrandGlyph.applicationIcon).resizable().scaledToFit()
            .frame(width: size, height: size).accessibilityLabel("1Tool")
    }
}

struct LanguageControls: View {
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    @State private var choosingLanguage = false
    var body: some View {
        ToolSection(title: L("Language")) {
            HStack {
                Text(L("App Language"))
                Spacer(minLength: 16)
                Button { choosingLanguage = true } label: {
                    HStack(spacing: 8) {
                        Text(verbatim: AppLanguage.names[language] ?? L("Follow System"))
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }.accessibilityLabel(L("App Language"))
                    .accessibilityValue(AppLanguage.names[language] ?? L("Follow System"))
                    .popover(isPresented: $choosingLanguage, arrowEdge: .bottom) {
                        VStack(spacing: 2) {
                            ForEach(["system"] + AppLanguage.supported, id: \.self) { code in
                                if code == "en" { Divider().padding(.vertical, 3) }
                                Button {
                                    choosingLanguage = false
                                    language = code
                                } label: {
                                    HStack {
                                        Text(verbatim: AppLanguage.names[code] ?? L("Follow System"))
                                        Spacer()
                                        Image(systemName: "checkmark").opacity(language == code ? 1 : 0)
                                            .accessibilityHidden(true)
                                    }.padding(.horizontal, 10).padding(.vertical, 7).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityAddTraits(language == code ? .isSelected : [])
                            }
                        }.padding(6).frame(width: 220)
                    }
            }
            HelpText(L("Changes apply immediately, including Finder actions."))
        }
    }
}

struct WindowTitleHider: NSViewRepresentable {
    final class View: NSView {
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); window?.titleVisibility = .hidden }
    }
    func makeNSView(context: Context) -> View { View() }
    func updateNSView(_ nsView: View, context: Context) {}
}

enum AppAccent: String, CaseIterable, Identifiable {
    case system, blue, purple, pink, red, orange, yellow, green, graphite
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L("Follow System")
        case .blue: return L("Blue")
        case .purple: return L("Purple")
        case .pink: return L("Pink")
        case .red: return L("Red")
        case .orange: return L("Orange")
        case .yellow: return L("Yellow")
        case .green: return L("Green")
        case .graphite: return L("Graphite")
        }
    }
    var color: Color {
        switch self {
        case .system: return Color(nsColor: .controlAccentColor)
        case .blue: return Color(nsColor: .systemBlue)
        case .purple: return Color(nsColor: .systemPurple)
        case .pink: return Color(nsColor: .systemPink)
        case .red: return Color(nsColor: .systemRed)
        case .orange: return Color(nsColor: .systemOrange)
        case .yellow: return Color(nsColor: .systemYellow)
        case .green: return Color(nsColor: .systemGreen)
        case .graphite: return Color(nsColor: .systemGray)
        }
    }
    static func resolve(_ value: String) -> AppAccent { AppAccent(rawValue: value) ?? .blue }
}
private struct ToolAccentKey: EnvironmentKey { static let defaultValue = AppAccent.blue.color }
extension EnvironmentValues {
    var toolAccent: Color {
        get { self[ToolAccentKey.self] }
        set { self[ToolAccentKey.self] = newValue }
    }
}
enum Theme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
}
struct PrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) { content.buttonStyle(.glassProminent) }
        else { content.buttonStyle(.borderedProminent) }
    }
}

struct AppearanceControls: View {
    @AppStorage("appearance.scheme") private var scheme = "system"
    @AppStorage("appearance.accent") private var accentName = "blue"
    @Environment(\.toolAccent) private var accent
    var body: some View {
        ToolSection(title: L("Appearance")) {
            HStack(alignment: .top, spacing: 16) {
                Text(L("Theme")).frame(width: 96, alignment: .leading).padding(.top, 20)
                ForEach([("light", L("Light")), ("dark", L("Dark")), ("system", L("Automatic"))], id: \.0) { value, title in
                    Button { scheme = value } label: {
                        VStack(spacing: 8) {
                            ThemePreview(mode: value).frame(width: 100, height: 58)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(scheme == value ? accent : .clear, lineWidth: 3).padding(-4))
                            Text(title).font(.callout).fontWeight(scheme == value ? .semibold : .regular)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(LF("Theme: %@", title))
                        .accessibilityAddTraits(scheme == value ? .isSelected : [])
                }
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 10) {
                Text(L("Accent Color")).frame(width: 96, alignment: .leading)
                ForEach(AppAccent.allCases) { choice in
                    Button { accentName = choice.rawValue } label: {
                        Circle().fill(choice.color)
                            .overlay {
                                if choice == .system {
                                    Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                                }
                            }
                            .frame(width: 26, height: 26)
                            .overlay { if AppAccent.resolve(accentName) == choice { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(choice == .yellow ? .black : .white) } }
                            .padding(4).contentShape(Circle())
                    }.buttonStyle(.plain).help(choice.title).accessibilityLabel(LF("Accent color: %@", choice.title))
                        .accessibilityAddTraits(AppAccent.resolve(accentName) == choice ? .isSelected : [])
                }
            }
            HelpText(L("Automatic follows macOS appearance. Accent color applies to controls and selections."))
        }
    }
}

private struct ThemePreview: View {
    let mode: String
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color(red: 0.18, green: 0.47, blue: 0.86)
                HStack(spacing: 0) {
                    preview(dark: mode == "dark")
                    if mode == "system" { preview(dark: true) }
                }.padding(8)
            }.clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .accessibilityHidden(true)
    }
    private func preview(dark: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in Circle().fill(dark ? Color.white.opacity(0.4) : Color.black.opacity(0.2)).frame(width: 4, height: 4) }
                Spacer()
            }.padding(6).background(dark ? Color(white: 0.20) : Color(white: 0.94))
            HStack(spacing: 0) {
                Color(white: dark ? 0.24 : 0.90).frame(width: 18)
                Rectangle().fill(dark ? Color(white: 0.14) : .white)
            }
        }.clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

struct QuickPanelRoot: View {
    let model: AppModel
    @Bindable var anchor: StatusPanelAnchor
    let maximumHeight: () -> CGFloat
    let onHeightChange: (CGFloat) -> Void
    @AppStorage("appearance.accent") private var accent = "blue"
    @AppStorage("appearance.scheme") private var scheme = "system"
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    var body: some View {
        QuickPanel(model: model, maximumHeight: maximumHeight, onHeightChange: onHeightChange)
            .id(language)
            .environment(\.locale, Locale(identifier: AppLanguage.resolve(language)))
            .padding(.top, 10)
            .background(StatusPanelShape(arrowX: anchor.arrowX).fill(Theme.canvas))
            .clipShape(StatusPanelShape(arrowX: anchor.arrowX))
            .overlay(StatusPanelShape(arrowX: anchor.arrowX).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .environment(\.toolAccent, AppAccent.resolve(accent).color)
            .tint(AppAccent.resolve(accent).color)
            .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
    }
}
