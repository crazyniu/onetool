// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct FinderPage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var service: RightClick
    @State private var tab = 0
    @State private var editing: SuperRightClickEntry?
    var body: some View {
        ToolSection(title: "") {
            SettingToggle(title: "启用超级右键", subtitle: "在 Finder 的文件、文件夹和空白处右键使用", value: $service.configuration.enabled)
            Divider()
            HStack(spacing: 10) {
                Image(systemName: service.extensionEnabled ? "checkmark.circle.fill" : "puzzlepiece.extension")
                    .foregroundStyle(service.extensionEnabled ? accent : .secondary)
                Text(service.extensionEnabled ? "Finder 扩展已启用" : "需要在系统设置中允许 Finder 扩展").font(.callout)
                Spacer()
                Button(service.extensionEnabled ? "管理扩展…" : "启用扩展…") { service.openExtensionSettings() }
            }
            HelpText("启用“1Tool 超级右键”后，打开一个新的 Finder 窗口。如果菜单未出现，可在扩展设置中关闭后重新开启。")
        }
        Picker("右键设置", selection: $tab) {
            Text("菜单项目").tag(0); Text("文件模板").tag(1); Text("目录与应用").tag(2)
        }.pickerStyle(.segmented).labelsHidden()
        if tab == 0 {
            ToolSection(title: "显示与顺序") {
                ForEach(service.configuration.visibleAndHiddenGroups) { group in
                    HStack {
                        Toggle(group.title(chinese: true), isOn: Binding(get: {
                            !service.configuration.hiddenGroups.contains(group)
                        }, set: { visible in
                            if visible { service.configuration.hiddenGroups.removeAll { $0 == group } }
                            else { service.configuration.hiddenGroups.append(group) }
                        })).toggleStyle(.checkbox)
                        Spacer()
                        Button { move(group, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(service.configuration.visibleAndHiddenGroups.first == group).help("上移").accessibilityLabel("上移" + group.title(chinese: true))
                        Button { move(group, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(service.configuration.visibleAndHiddenGroups.last == group).help("下移").accessibilityLabel("下移" + group.title(chinese: true))
                    }
                    if group != service.configuration.visibleAndHiddenGroups.last { Divider() }
                }
                Divider()
                Toggle("快捷操作中显示“显示／隐藏隐藏文件”", isOn: $service.configuration.showHiddenToggle).toggleStyle(.checkbox)
                HelpText("此操作切换 Finder 对隐藏文件的显示，并重新启动 Finder，不改变文件的隐藏属性。")
            }
        } else if tab == 1 {
            ToolSection(title: "新建文件模板") {
                if service.configuration.templates.isEmpty { HelpText("添加常用文件类型，右键时直接创建。") }
                ForEach(service.configuration.templates) { entry in
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                            HelpText("." + entry.value)
                        }
                        Spacer()
                        Button("编辑") { editing = entry }
                        removeButton("移除模板 " + entry.name) { service.configuration.templates.removeAll { $0.id == entry.id } }
                    }
                    if entry.id != service.configuration.templates.last?.id { Divider() }
                }
                Button("添加模板…", systemImage: "plus") { editing = SuperRightClickTemplatePreset.txt.entry }
                    .disabled(service.configuration.templates.count >= 32)
            }
            HelpText("文件创建前可以修改名称。已有文件不会被覆盖；Word 和 Excel 使用真实空白文档。")
        } else {
            ToolSection(title: "常用目录") {
                if service.configuration.directories.isEmpty { HelpText("把经常访问的目录放进右键菜单。") }
                ForEach($service.configuration.directories) { $entry in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("菜单名称", text: $entry.name).textFieldStyle(.plain).accessibilityLabel("目录菜单名称 " + entry.name)
                            HelpText(entry.value).lineLimit(1)
                        }
                        Spacer()
                        removeButton("移除目录 " + entry.name) { service.configuration.directories.removeAll { $0.id == entry.id } }
                    }
                }
                Button("添加目录…", systemImage: "plus") { service.addFolder() }.disabled(service.configuration.directories.count >= 32)
            }
            ToolSection(title: "快捷打开") {
                ForEach(service.availableApplications) { entry in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.value)).resizable().frame(width: 22, height: 22)
                        Text(entry.name)
                        Spacer()
                        Toggle("启用 " + entry.name, isOn: Binding(get: {
                            !service.configuration.disabledApplications.contains(entry.id)
                        }, set: { enabled in
                            service.configuration.disabledApplications.removeAll { $0 == entry.id }
                            if !enabled { service.configuration.disabledApplications.append(entry.id) }
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel("启用软件入口 " + entry.name)
                        if !service.detectedApplications.contains(where: { $0.value == entry.value }) {
                            removeButton("移除应用 " + entry.name) { service.configuration.applications.removeAll { $0.id == entry.id } }
                        }
                    }
                }
                HStack {
                    Button("刷新已安装软件", systemImage: "arrow.clockwise") { service.refreshApplications() }
                    Spacer()
                    Button("添加应用…", systemImage: "plus") { service.addApplication() }.disabled(service.configuration.applications.count >= 32)
                }
                HelpText("终端会切换到当前文件夹；编辑器与其他应用使用系统“打开”操作。")
            }
        }
        ErrorText(error: service.error)
        HStack {
            Button("在 Finder 中试用", systemImage: "folder") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
            Spacer()
            Button("刷新状态", systemImage: "arrow.clockwise") { service.refreshStatus() }
        }
        .onChange(of: service.configuration) { service.save() }
        .onAppear { service.refreshStatus(); service.refreshApplications() }
        .sheet(item: $editing) { entry in
            TemplateEditor(entry: entry) { saved in
                if let i = service.configuration.templates.firstIndex(where: { $0.id == saved.id }) { service.configuration.templates[i] = saved }
                else { service.configuration.templates.append(saved) }
                service.save()
            }
        }
    }
    private func move(_ group: SuperRightClickGroup, by offset: Int) {
        var groups = service.configuration.visibleAndHiddenGroups
        guard let index = groups.firstIndex(of: group), groups.indices.contains(index + offset) else { return }
        groups.swapAt(index, index + offset); service.configuration.order = groups
    }
    private func removeButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "minus.circle") }.buttonStyle(.borderless).help(title).accessibilityLabel(title)
    }
}

extension SuperRightClickConfiguration {
    var visibleAndHiddenGroups: [SuperRightClickGroup] {
        var seen = Set<SuperRightClickGroup>()
        return (order + SuperRightClickGroup.allCases).filter { seen.insert($0).inserted }
    }
}

struct TemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entry: SuperRightClickEntry
    @State private var preset: SuperRightClickTemplatePreset = .custom
    let save: (SuperRightClickEntry) -> Void
    init(entry: SuperRightClickEntry, save: @escaping (SuperRightClickEntry) -> Void) {
        _entry = State(initialValue: entry)
        _preset = State(initialValue: SuperRightClickTemplatePreset(rawValue: SuperRightClickTemplates.normalizedExtension(entry.value)) ?? .custom)
        self.save = save
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("文件模板").font(.title2).fontWeight(.semibold)
            Picker("预设", selection: $preset) {
                Text("自定义").tag(SuperRightClickTemplatePreset.custom)
                ForEach(SuperRightClickTemplatePreset.allCases.filter { $0 != .custom }) { item in Text(item.title).tag(item) }
            }.onChange(of: preset) {
                guard preset != .custom else { return }
                let id = entry.id; entry = preset.entry; entry.id = id
            }
            TextField("菜单名称", text: $entry.name).textFieldStyle(.roundedBorder)
            TextField("扩展名，例如 txt", text: $entry.value).textFieldStyle(.roundedBorder)
            if !SuperRightClickTemplates.isOffice(entry.value) {
                Text("初始内容").font(.callout)
                TextEditor(text: $entry.content).font(.system(.body, design: .monospaced)).frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            } else { HelpText("使用随应用提供的空白 Office 文档。") }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存") {
                    entry.name = entry.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    entry.value = SuperRightClickTemplates.normalizedExtension(entry.value)
                    if SuperRightClickTemplates.isOffice(entry.value) { entry.content = "" }
                    save(entry); dismiss()
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || entry.name.utf8.count > 255 || !SuperRightClickTemplates.validExtension(entry.value) || entry.content.utf8.count > 64 * 1024)
            }
        }.padding(26).frame(width: 440)
    }
}
