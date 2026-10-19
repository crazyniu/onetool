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
                    BrandLogo(size: 32)
                    Spacer()
                    OpenMainButton(title: L("Open Settings"), page: .awake).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small)
                }
                Divider()
                HStack {
                    Label(L("Keep Awake"), systemImage: "cup.and.saucer")
                    Spacer()
                    Toggle(L("Keep Awake"), isOn: Binding(get: { model.awake.isActive }, set: {
                        if $0 { model.awake.startPreferredSession() } else { model.awake.stop() }
                    })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
                if let end = model.awake.endDate {
                    HStack { Text(L("Ends At")).foregroundStyle(.secondary); Spacer(); Text(end, style: .time).monospacedDigit() }.font(.caption)
                }
                AwakeDurationPicker(awake: model.awake)
                ErrorText(error: model.awake.error)
                Divider()
                HStack { Label(L("Display Brightness"), systemImage: "display"); Spacer(); OpenMainButton(title: L("Manage"), page: .displays).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small) }
                if model.displays.scanning { ProgressView().controlSize(.small) }
                ForEach(model.displays.screens) { screen in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(screen.title).lineLimit(1); Spacer(); Text(screen.method.title).foregroundStyle(.secondary).font(.system(size: 11)) }
                        LevelSlider(title: LF("%@ Brightness", screen.title), value: Binding(get: {
                            model.displays.screens.first(where: { $0.id == screen.id })?.level ?? screen.level
                        }, set: { model.displays.set(screen.id, level: $0) }), disabled: model.displays.scanning || screen.method == .unavailable)
                        ErrorText(error: screen.error)
                    }.font(.caption)
                }
                if model.keyboard.supported {
                    Divider()
                    Label(L("Keyboard Backlight"), systemImage: "keyboard")
                    LevelSlider(title: L("Keyboard Backlight"), value: Binding(get: { model.keyboard.level }, set: { model.keyboard.set($0) }))
                    ErrorText(error: model.keyboard.error)
                }
                Divider()
                HStack { Label(model.input.currentName, systemImage: "globe").lineLimit(1); Spacer(); OpenMainButton(title: L("Input Sources"), page: .input).buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small) }.font(.caption)
                HStack {
                    Spacer()
                    Button(L("Quit")) { NSApp.terminate(nil) }.buttonStyle(.bordered).foregroundStyle(.primary).controlSize(.small)
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
