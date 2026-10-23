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
    private var nativeColor: NSColor {
        switch self {
        case .system: return .controlAccentColor
        case .blue: return .systemBlue
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .red: return .systemRed
        case .orange: return .systemOrange
        case .yellow: return .systemYellow
        case .green: return .systemGreen
        case .graphite: return .systemGray
        }
    }
    var color: Color { Color(nsColor: nativeColor) }
    /// Preserve the chosen hue while keeping accent text readable on light surfaces.
    var readableColor: Color {
        // The default blue and system accent must retain their native macOS values.
        if self == .blue || self == .system { return color }
        return Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = self.nativeColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = self.nativeColor.usingColorSpace(.sRGB) ?? self.nativeColor
            }
            guard appearance.bestMatch(from: [.aqua, .darkAqua]) != .darkAqua,
                  let rgb = resolved.usingColorSpace(.sRGB) else { return resolved }
            var r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            while 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > 0.13 {
                r *= 0.95; g *= 0.95; b *= 0.95
            }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
    /// Selected navigation labels are white in both appearances. Custom bright
    /// accents therefore need a separate fill from their text/slider color.
    var selectionColor: Color {
        if self == .blue { return color }
        return Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = self.nativeColor
            appearance.performAsCurrentDrawingAppearance {
                resolved = self.nativeColor.usingColorSpace(.sRGB) ?? self.nativeColor
            }
            guard let rgb = resolved.usingColorSpace(.sRGB) else { return resolved }
            var r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            while 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b) > 0.18 {
                r *= 0.95; g *= 0.95; b *= 0.95
            }
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
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
enum Layout {
    static let sidebarWidth: CGFloat = 220
    static let contentWidth: CGFloat = 920
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let groupPadding: CGFloat = 16
    static let rowSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 10
}
enum Theme {
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .windowBackgroundColor)
    static let border = Color(nsColor: .separatorColor)
    static let selection = Color.primary.opacity(0.08)
    static let surface = Color(nsColor: .controlBackgroundColor)
}
private struct ToolGlassKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var toolGlassEnabled: Bool {
        get { self[ToolGlassKey.self] }
        set { self[ToolGlassKey.self] = newValue }
    }
}
struct ToolAppearance: ViewModifier {
    @AppStorage("appearance.liquidGlass") private var enabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.environment(\.toolGlassEnabled, enabled && !reduceTransparency && contrast != .increased)
    }
}
struct PrimaryAction: ViewModifier {
    @Environment(\.toolGlassEnabled) private var glass
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass { content.buttonStyle(.glassProminent) }
        else { content.buttonStyle(.borderedProminent) }
    }
}
/// Glass belongs to navigation and actions. Content groups keep a readable surface.
struct ToolGlassSurface: ViewModifier {
    @Environment(\.toolGlassEnabled) private var glass
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass {
            content.glassEffect(.regular, in: .rect(cornerRadius: radius))
        } else if glass {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(Theme.surface, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Theme.border, lineWidth: 0.5))
        }
    }
}
struct ToolActionBar: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(Layout.groupPadding)
            .frame(maxWidth: Layout.contentWidth - Layout.pagePadding * 2)
            .modifier(ToolGlassSurface())
            .padding(.horizontal, Layout.pagePadding).padding(.bottom, 12).padding(.top, 8)
            .frame(maxWidth: .infinity)
    }
}
struct ToolToolbarAppearance: ViewModifier {
    @Environment(\.toolGlassEnabled) private var glass
    func body(content: Content) -> some View {
        if glass { content }
        else { content.toolbarBackground(Theme.canvas, for: .windowToolbar) }
    }
}

struct AppearanceControls: View {
    @Bindable var systemTheme: SystemTheme
    @AppStorage("appearance.accent") private var accentName = "blue"
    @AppStorage("appearance.liquidGlass") private var liquidGlass = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.toolAccent) private var accent
    var body: some View {
        ToolSection(title: L("Appearance")) {
            HStack(alignment: .top, spacing: 16) {
                Text(L("System Appearance")).frame(width: 96, alignment: .leading).padding(.top, 20)
                ForEach(SystemThemeMode.allCases) { mode in
                    Button { Task { await systemTheme.set(mode) } } label: {
                        VStack(spacing: 8) {
                            ThemePreview(mode: mode == .automatic ? "system" : mode.rawValue).frame(width: 100, height: 58)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(systemTheme.state.mode == mode ? accent : .clear, lineWidth: 3).padding(-4))
                            Text(mode.title).font(.callout).fontWeight(systemTheme.state.mode == mode ? .semibold : .regular)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(LF("Theme: %@", mode.title))
                        .accessibilityAddTraits(systemTheme.state.mode == mode ? .isSelected : [])
                        .disabled(systemTheme.isChanging || !systemTheme.canChange)
                }
            }
            HelpText(L("Changes the appearance of macOS and all apps that follow it. Automatic uses the system schedule."))
            ErrorText(error: systemTheme.error)
            if !systemTheme.canChange {
                HelpText(L("System appearance cannot be changed on this macOS version. Use System Settings."))
            }
            HStack {
                if systemTheme.isChanging { ProgressView().controlSize(.small) }
                Spacer()
                Button(L("System Settings…")) { SystemTheme.openSettings() }
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
            Divider()
            SettingToggle(title: "Liquid Glass", subtitle: L("Use system glass for navigation and actions."), value: $liquidGlass)
            if reduceTransparency || contrast == .increased {
                HelpText(L("System accessibility settings take priority. Surfaces stay opaque for clarity."))
            } else if #unavailable(macOS 26.0) {
                HelpText(L("This macOS version uses standard translucent materials. Liquid Glass requires macOS 26 or later."))
            }
        }
    }
}

private struct ThemePreview: View {
    let mode: String
    var body: some View {
        GeometryReader { _ in
            ZStack {
                Color(nsColor: .systemBlue)
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
    @AppStorage(AppLanguage.preferenceKey) private var language = "system"
    var body: some View {
        QuickPanel(model: model, maximumHeight: maximumHeight, onHeightChange: onHeightChange)
            .id(language)
            .environment(\.locale, Locale(identifier: AppLanguage.resolve(language)))
            .padding(.top, 10)
            .modifier(QuickPanelMaterial(arrowX: anchor.arrowX))
            .clipShape(StatusPanelShape(arrowX: anchor.arrowX))
            .overlay(StatusPanelShape(arrowX: anchor.arrowX).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .environment(\.toolAccent, AppAccent.resolve(accent).readableColor)
            .tint(AppAccent.resolve(accent).color)
            .modifier(ToolAppearance())
    }
}

private struct QuickPanelMaterial: ViewModifier {
    @Environment(\.toolGlassEnabled) private var glass
    let arrowX: CGFloat
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass {
            content.glassEffect(.regular, in: StatusPanelShape(arrowX: arrowX))
        } else if glass {
            content.background(.regularMaterial, in: StatusPanelShape(arrowX: arrowX))
        } else { content.background(StatusPanelShape(arrowX: arrowX).fill(Theme.surface)) }
    }
}
