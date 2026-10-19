// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct QuickPanel: View {
    let model: AppModel
    let maximumHeight: () -> CGFloat
    let onHeightChange: (CGFloat) -> Void
    @State private var panelHeight: CGFloat = 480
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    BrandWordmark(size: 20)
                    Spacer()
                    OpenMainButton(title: "打开设置", page: .awake).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small)
                }
                Divider()
                HStack {
                    Label("防止休眠", systemImage: "cup.and.saucer")
                    Spacer()
                    Toggle("防止休眠", isOn: Binding(get: { model.awake.isActive }, set: {
                        if $0 { model.awake.start() } else { model.awake.stop() }
                    })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if let end = model.awake.endDate {
                    HStack { Text("结束时间").foregroundStyle(.secondary); Spacer(); Text(end, style: .time).monospacedDigit() }.font(.caption)
                }
                HStack {
                    ForEach([30, 60, 120, 240, 480], id: \.self) { minutes in
                        Button(minutes < 60 ? "\(minutes) 分" : "\(minutes / 60) 时") { model.awake.start(minutes: Double(minutes)) }
                            .font(.system(size: 12)).foregroundStyle(.primary).frame(maxWidth: .infinity)
                    }
                    Button { model.awake.start() } label: { Image(systemName: "infinity") }
                        .help("无限防休眠").accessibilityLabel("无限防休眠")
                }
                ErrorText(error: model.awake.error)
                Divider()
                HStack { Label("屏幕亮度", systemImage: "display"); Spacer(); OpenMainButton(title: "管理", page: .displays).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small) }
                if model.displays.scanning { ProgressView().controlSize(.small) }
                ForEach(model.displays.screens) { screen in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(screen.name).lineLimit(1); Spacer(); Text(screen.method.rawValue).foregroundStyle(.secondary).font(.system(size: 11)) }
                        LevelSlider(title: screen.name + "亮度", value: Binding(get: {
                            model.displays.screens.first(where: { $0.id == screen.id })?.level ?? screen.level
                        }, set: { model.displays.set(screen.id, level: $0) }), disabled: model.displays.scanning || screen.method == .unavailable)
                        ErrorText(error: screen.error)
                    }.font(.caption)
                }
                if model.keyboard.supported {
                    Divider()
                    Label("键盘背光", systemImage: "keyboard")
                    LevelSlider(title: "键盘背光", value: Binding(get: { model.keyboard.level }, set: { model.keyboard.set($0) }))
                    ErrorText(error: model.keyboard.error)
                }
                Divider()
                HStack { Label(model.input.currentName, systemImage: "character.cursor.ibeam").lineLimit(1); Spacer(); OpenMainButton(title: "输入法", page: .input).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small) }.font(.caption)
                HStack {
                    OpenMainButton(title: "更换图标…", page: .appearance).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small)
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }.buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small)
                }.font(.caption)
            }.padding(16)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(key: PanelContentHeight.self, value: geometry.size.height)
                    }
                }
        }.frame(width: 365, height: panelHeight)
            .background(Theme.canvas)
            .foregroundStyle(.primary)
            .onPreferenceChange(PanelContentHeight.self) { contentHeight in
                guard contentHeight > 0 else { return }
                let height = ceil(min(contentHeight, maximumHeight()))
                if abs(panelHeight - height) > 0.5 {
                    panelHeight = height
                    onHeightChange(height)
                }
            }
            .onAppear { model.refresh(); model.displays.refresh() }
    }
}

private struct PanelContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
