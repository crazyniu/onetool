// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct FinderPage: View {
    @Environment(\.toolAccent) private var accent
    @Bindable var service: RightClick
    @State private var tab = 0
    @State private var editing: SuperRightClickEntry?
    var body: some View {
        ToolSection(title: "") {
            SettingToggle(title: L("Enable Finder Actions"), subtitle: L("Right-click a file, folder, or empty space in Finder"), value: $service.configuration.enabled)
            Divider()
            HStack(spacing: 10) {
                Image(systemName: service.extensionEnabled ? "checkmark.circle.fill" : "puzzlepiece.extension")
                    .foregroundStyle(service.extensionEnabled ? accent : .secondary)
                Text(service.extensionEnabled ? L("Finder Extension Enabled") : L("Allow the Finder extension in System Settings")).font(.callout)
                Spacer()
                Button(service.extensionEnabled ? L("Manage Extension…") : L("Enable Extension…")) { service.openExtensionSettings() }
            }
            if !service.extensionEnabled {
                HelpText(L("Enable the 1Tool Finder extension, then open a new Finder window. If actions are missing, turn the extension off and on again."))
            }
        }
        Picker(L("Finder Action Settings"), selection: $tab) {
            Text(L("Menu Items")).tag(0); Text(L("File Templates")).tag(1); Text(L("Folders & Apps")).tag(2)
        }.pickerStyle(.segmented).labelsHidden()
        if tab == 0 {
            ToolSection(title: L("Visibility & Order")) {
                ForEach(service.configuration.visibleAndHiddenGroups) { group in
                    HStack {
                        Toggle(group.title(), isOn: Binding(get: {
                            !service.configuration.hiddenGroups.contains(group)
                        }, set: { visible in
                            if visible { service.configuration.hiddenGroups.removeAll { $0 == group } }
                            else { service.configuration.hiddenGroups.append(group) }
                        })).toggleStyle(.checkbox)
                        Spacer()
                        Button { move(group, by: -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(service.configuration.visibleAndHiddenGroups.first == group).help(L("Move Up")).accessibilityLabel(LF("Move Up: %@", group.title()))
                        Button { move(group, by: 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(service.configuration.visibleAndHiddenGroups.last == group).help(L("Move Down")).accessibilityLabel(LF("Move Down: %@", group.title()))
                    }
                    if group != service.configuration.visibleAndHiddenGroups.last { Divider() }
                }
                Divider()
                Toggle(L("Include Show / Hide Hidden Files"), isOn: $service.configuration.showHiddenToggle).toggleStyle(.checkbox)
                HelpText(L("Toggle hidden-file visibility and relaunch Finder. File attributes are not changed."))
            }
        } else if tab == 1 {
            ToolSection(title: L("New File Templates")) {
                if service.configuration.templates.isEmpty { HelpText(L("Add file types to create them from the context menu.")) }
                ForEach(service.configuration.templates) { entry in
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name)
                            HelpText("." + entry.value)
                        }
                        Spacer()
                        Button(L("Edit")) { editing = entry }
                        removeButton(LF("Remove template %@", entry.name)) { service.configuration.templates.removeAll { $0.id == entry.id } }
                    }
                    if entry.id != service.configuration.templates.last?.id { Divider() }
                }
                Button(L("Add Template…"), systemImage: "plus") { editing = SuperRightClickTemplatePreset.txt.entry }
                    .disabled(service.configuration.templates.count >= 32)
            }
            HelpText(L("Choose a name before creating a file. Existing files are never overwritten. Word and Excel use blank documents."))
        } else {
            ToolSection(title: L("Favorite Folders")) {
                if service.configuration.directories.isEmpty { HelpText(L("Keep frequently used folders in your context menu.")) }
                ForEach($service.configuration.directories) { $entry in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(accent)
                        VStack(alignment: .leading, spacing: 3) {
                            TextField(L("Menu Name"), text: $entry.name).textFieldStyle(.plain).accessibilityLabel(LF("Folder menu name: %@", entry.name))
                            HelpText(entry.value).lineLimit(1)
                        }
                        Spacer()
                        removeButton(LF("Remove folder %@", entry.name)) { service.configuration.directories.removeAll { $0.id == entry.id } }
                    }
                }
                Button(L("Add Folder…"), systemImage: "plus") { service.addFolder() }.disabled(service.configuration.directories.count >= 32)
            }
            ToolSection(title: L("Open With")) {
                ForEach(service.availableApplications) { entry in
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.value)).resizable().frame(width: 22, height: 22)
                        Text(entry.name)
                        Spacer()
                        Toggle(LF("Enable %@", entry.name), isOn: Binding(get: {
                            !service.configuration.disabledApplications.contains(entry.id)
                        }, set: { enabled in
                            service.configuration.disabledApplications.removeAll { $0 == entry.id }
                            if !enabled { service.configuration.disabledApplications.append(entry.id) }
                        })).labelsHidden().toggleStyle(.switch).controlSize(.small).accessibilityLabel(LF("Enable app action: %@", entry.name))
                        if !service.detectedApplications.contains(where: { $0.value == entry.value }) {
                            removeButton(LF("Remove app %@", entry.name)) { service.configuration.applications.removeAll { $0.id == entry.id } }
                        }
                    }
                }
                HStack {
                    Button(L("Refresh Installed Apps"), systemImage: "arrow.clockwise") { service.refreshApplications() }
                    Spacer()
                    Button(L("Add App…"), systemImage: "plus") { service.addApplication() }.disabled(service.configuration.applications.count >= 32)
                }
                HelpText(L("Terminals open at the current folder. Editors and other apps use the system Open action."))
            }
        }
        ErrorText(error: service.error)
        HStack {
            Button(L("Try in Finder"), systemImage: "folder") { NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser) }
            Spacer()
            Button(L("Refresh Status"), systemImage: "arrow.clockwise") { service.refreshStatus() }
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
            Text(L("File Templates")).font(.title2).fontWeight(.semibold)
            Picker(L("Preset"), selection: $preset) {
                Text(L("Custom")).tag(SuperRightClickTemplatePreset.custom)
                ForEach(SuperRightClickTemplatePreset.allCases.filter { $0 != .custom }) { item in Text(item.title).tag(item) }
            }.onChange(of: preset) {
                guard preset != .custom else { return }
                let id = entry.id; entry = preset.entry; entry.id = id
            }
            TextField(L("Menu Name"), text: $entry.name).textFieldStyle(.roundedBorder)
            TextField(L("Extension, such as txt"), text: $entry.value).textFieldStyle(.roundedBorder)
            if !SuperRightClickTemplates.isOffice(entry.value) {
                Text(L("Initial Content")).font(.callout)
                TextEditor(text: $entry.content).font(.system(.body, design: .monospaced)).frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
            } else { HelpText(L("Uses the blank Office document bundled with the app.")) }
            HStack {
                Spacer()
                Button(L("Cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L("Save")) {
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
