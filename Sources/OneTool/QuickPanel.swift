// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct QuickPanel: View {
    let model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 17) {
                HStack {
                    Text("1Tool").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Spacer()
                    OpenMainButton(title: "打开设置", page: .awake).buttonStyle(.borderless)
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
                    ForEach([5, 10, 30, 60, 120], id: \.self) { minutes in
                        Button(minutes < 60 ? "\(minutes) 分" : "\(minutes / 60) 时") { model.awake.start(minutes: Double(minutes)) }
                            .font(.system(size: 11)).frame(maxWidth: .infinity)
                    }
                }
                ErrorText(error: model.awake.error)
                Divider()
                HStack { Label("屏幕亮度", systemImage: "display"); Spacer(); OpenMainButton(title: "管理", page: .displays).buttonStyle(.borderless) }
                if model.displays.scanning { ProgressView().controlSize(.small) }
                ForEach(model.displays.screens) { screen in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(screen.name).lineLimit(1); Spacer(); Text(screen.method.rawValue).foregroundStyle(.secondary).font(.system(size: 10)) }
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
                HStack { Label(model.input.currentName, systemImage: "character.cursor.ibeam").lineLimit(1); Spacer(); OpenMainButton(title: "输入法", page: .input).buttonStyle(.borderless) }.font(.caption)
                HStack {
                    OpenMainButton(title: "更换图标…", page: .appearance).buttonStyle(.borderless)
                    Spacer()
                    Button("退出") { NSApp.terminate(nil) }.buttonStyle(.borderless)
                }.font(.caption)
            }.padding(20)
        }.frame(width: 365).frame(maxHeight: 660)
            .onAppear { model.refresh(); model.displays.refresh() }
    }
}
