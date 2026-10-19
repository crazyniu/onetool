// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct BrandWordmark: View {
    var size: CGFloat = 25
    var body: some View {
        HStack(spacing: 2) {
            Image(nsImage: BrandGlyph.wordmark).renderingMode(.template)
                .resizable().scaledToFit().frame(width: size * 0.72, height: size * 1.2)
            Text("Tool").font(.system(size: size, weight: .semibold, design: .rounded))
        }.foregroundStyle(Color(nsColor: .labelColor))
            .accessibilityElement(children: .ignore).accessibilityLabel("1Tool")
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
        case .system: return "跟随系统"
        case .blue: return "科技蓝"
        case .purple: return "紫色"
        case .pink: return "粉色"
        case .red: return "红色"
        case .orange: return "橙色"
        case .yellow: return "黄色"
        case .green: return "绿色"
        case .graphite: return "石墨色"
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
        ToolSection(title: "外观") {
            HStack(alignment: .top, spacing: 16) {
                Text("主题").frame(width: 64, alignment: .leading).padding(.top, 20)
                ForEach([("light", "浅色"), ("dark", "深色"), ("system", "自动")], id: \.0) { value, title in
                    Button { scheme = value } label: {
                        VStack(spacing: 8) {
                            ThemePreview(mode: value).frame(width: 100, height: 58)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(scheme == value ? accent : .clear, lineWidth: 3).padding(-4))
                            Text(title).font(.callout).fontWeight(scheme == value ? .semibold : .regular)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("主题：" + title)
                        .accessibilityAddTraits(scheme == value ? .isSelected : [])
                }
            }
            Divider().padding(.vertical, 4)
            HStack(spacing: 10) {
                Text("主色调").frame(width: 64, alignment: .leading)
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
                    }.buttonStyle(.plain).help(choice.title).accessibilityLabel("主色调：" + choice.title)
                        .accessibilityAddTraits(AppAccent.resolve(accentName) == choice ? .isSelected : [])
                }
            }
            HelpText("自动主题跟随 macOS 外观。主色调用于按钮、滑块和选中状态。")
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
                Color.blue.opacity(0.20).frame(width: 18)
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
    var body: some View {
        QuickPanel(model: model, maximumHeight: maximumHeight, onHeightChange: onHeightChange)
            .padding(.top, 10)
            .background(StatusPanelShape(arrowX: anchor.arrowX).fill(Theme.canvas))
            .clipShape(StatusPanelShape(arrowX: anchor.arrowX))
            .overlay(StatusPanelShape(arrowX: anchor.arrowX).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .environment(\.toolAccent, AppAccent.resolve(accent).color)
            .tint(AppAccent.resolve(accent).color)
            .preferredColorScheme(scheme == "dark" ? .dark : scheme == "light" ? .light : nil)
    }
}
