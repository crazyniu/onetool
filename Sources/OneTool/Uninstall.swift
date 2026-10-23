// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable final class AppUninstaller {
    private(set) var apps: [UninstallApp] = []
    private(set) var plan: UninstallPlan?
    private(set) var result: UninstallResult?
    private(set) var busy = false
    private(set) var removing = false
    private(set) var loaded = false
    private(set) var error: String?
    private(set) var inventoryProblems: [UninstallProblem] = []
    private(set) var scanProblem: UninstallProblem?
    private(set) var inspectedApp: UninstallApp?
    private(set) var needsRescan = false
    var selected = Set<String>()
    private let engine: UninstallEngine
    init(engine: UninstallEngine = .init()) { self.engine = engine }
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var inventory: Task<UninstallInventory, Error>?
    @ObservationIgnored private var scanner: Task<UninstallPlan, Error>?
    @ObservationIgnored private var remover: Task<UninstallResult, Error>?
    var selectedItems: [UninstallItem] { plan?.items.filter { selected.contains($0.id) && $0.issue == nil } ?? [] }
    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.bytes } }
    var canUninstall: Bool { !busy && !needsRescan && plan.map { selected.contains($0.app.id) && $0.appItem?.issue == nil && $0.appItem != nil } == true }
    func refresh() {
        guard !busy else { return }
        busy = true; error = nil; scanProblem = nil; result = nil; plan = nil; inspectedApp = nil; selected = []
        let engine = engine
        inventory = Task.detached(priority: .utility) { try engine.inventory(cancelled: { Task.isCancelled }) }
        task = Task {
            defer { busy = false; inventory = nil }
            do {
                let value = try await inventory!.value
                apps = value.apps; inventoryProblems = value.problems; loaded = true
            }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func inspect(_ app: UninstallApp) {
        guard !busy else { return }
        busy = true; error = nil; scanProblem = nil; inspectedApp = app; result = nil; plan = nil; selected = []; needsRescan = false
        let installed = apps, engine = engine
        scanner = Task.detached(priority: .utility) { try engine.scan(app, installed: installed, cancelled: { Task.isCancelled }) }
        task = Task {
            defer { busy = false; scanner = nil }
            do {
                let value = try await scanner!.value
                plan = value
                if let item = value.appItem, item.issue == nil { selected = [app.id] }
            } catch is CancellationError { }
            catch { scanProblem = .capture(error, at: app.url) }
        }
    }
    func rescan() {
        guard !busy else { return }
        if let app = inspectedApp, FileManager.default.fileExists(atPath: app.id) { inspect(app) } else { refresh() }
    }
    func addApp() {
        guard !busy else { return }
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.applicationBundle]; picker.canChooseDirectories = false
        picker.canChooseFiles = true; picker.allowsMultipleSelection = false
        picker.prompt = L("Inspect App")
        picker.begin { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            Task { @MainActor in
                guard let self else { return }
                guard let app = UninstallEngine.application(at: url) else {
                    self.error = L("Choose a valid application bundle without symbolic links."); return
                }
                if !self.apps.contains(where: { $0.id == app.id }) { self.apps.append(app) }
                self.inspect(app)
            }
        }
    }
    func back() { guard !busy else { return }; plan = nil; inspectedApp = nil; scanProblem = nil; selected = []; error = nil }
    func cancel() { inventory?.cancel(); scanner?.cancel(); remover?.cancel() }
    func uninstall() {
        guard canUninstall, let plan else { return }
        busy = true; removing = true; error = nil; result = nil
        let selection = selected, engine = engine
        remover = Task.detached(priority: .utility) {
            // Refresh installed copies before acting, including those added since the preview.
            let inventory = try engine.inventory(cancelled: { Task.isCancelled })
            if selection.count > 1, let problem = inventory.problems.first { throw problem }
            var installed = inventory.apps
            if !installed.contains(where: { $0.id == plan.app.id }) { installed.append(plan.app) }
            return try engine.uninstall(plan, selected: selection, installed: installed, cancelled: { Task.isCancelled })
        }
        task = Task {
            defer { busy = false; removing = false; remover = nil }
            do {
                let value = try await remover!.value
                result = value
                needsRescan = !value.problems.isEmpty
                if value.moved.contains(plan.app.url) {
                    apps.removeAll { $0.id == plan.app.id }; self.plan = nil; selected = []
                }
            } catch is CancellationError { }
            catch {
                if let problem = error as? UninstallProblem { scanProblem = problem; needsRescan = true }
                else { self.error = error.localizedDescription }
            }
        }
    }
}

private func uninstallSize(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

struct UninstallPage: View {
    @Bindable var uninstaller: AppUninstaller
    @State private var search = ""
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filtered: [UninstallApp] {
        uninstaller.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        HStack {
            if uninstaller.inspectedApp != nil {
                Button(L("All Applications"), systemImage: "chevron.left") { uninstaller.back() }.disabled(uninstaller.busy)
            } else {
                TextField(L("Search applications"), text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
            }
            Spacer()
            if uninstaller.busy {
                ProgressView().controlSize(.small)
                Button(L("Cancel")) { uninstaller.cancel() }
            } else {
                Button(L("Add App…"), systemImage: "plus") { uninstaller.addApp() }
                Button(L("Refresh"), systemImage: "arrow.clockwise") { uninstaller.refresh() }
            }
        }
        if let result = uninstaller.result { completion(result) }
        ErrorText(error: uninstaller.error)
        if let problem = uninstaller.scanProblem { problemView(problem) }
        ForEach(uninstaller.inventoryProblems) { problem in problemView(problem) }
        if uninstaller.busy && uninstaller.plan == nil {
            HelpText(L("Inspecting applications…"))
        } else if let plan = uninstaller.plan {
            appHeader(plan.app)
            if let item = plan.appItem, item.issue == nil, uninstaller.selected.contains(plan.app.id) {
                HelpText(L("The app is selected. Choose any related data you also want to remove. Personal settings and app data may be included."))
            } else {
                Label(L("This app cannot be uninstalled from this scan."), systemImage: "lock.shield").foregroundStyle(.secondary)
            }
            if plan.blockedItems.contains(where: { $0.problem?.kind != .protected }) {
                HelpText(L("Some paths were not inspected. This is not a complete list of related files."))
            }
            if !uninstaller.busy { Button(L("Scan App Again"), systemImage: "arrow.clockwise") { uninstaller.rescan() } }
            ForEach(plan.warnings, id: \.self) { HelpText($0) }
            ForEach(plan.items) { item in fileRow(item, appID: plan.app.id) }
        } else if !uninstaller.busy {
            if uninstaller.loaded && !uninstaller.apps.isEmpty && !query.isEmpty && filtered.isEmpty {
                ContentUnavailableView {
                    Label(L("No Matching Applications"), systemImage: "magnifyingglass")
                } description: {
                    Text(LF("No applications match “%@”.", query))
                } actions: {
                    Button(L("Clear Search")) { search = "" }
                }
            } else if uninstaller.apps.isEmpty {
                ContentUnavailableView {
                    Label(L(uninstaller.error != nil || !uninstaller.inventoryProblems.isEmpty ? "Applications Could Not Be Fully Inspected" : uninstaller.loaded ? "No Applications Found" : "Load Applications"), systemImage: "app.dashed")
                } description: {
                    Text(L(uninstaller.inventoryProblems.isEmpty ? "Refresh the list or choose Add App to inspect an application." : "Review the blocked paths above, then refresh the list."))
                } actions: {
                    Button(L("Refresh"), systemImage: "arrow.clockwise") { uninstaller.refresh() }
                }
            } else {
                HelpText(LF("%d applications", filtered.count))
                LazyVStack(spacing: 8) {
                    ForEach(filtered) { app in
                        Button { uninstaller.inspect(app) } label: { appHeader(app) }
                            .buttonStyle(.plain).accessibilityLabel(LF("Inspect %@", app.name))
                    }
                }
            }
        }
        HelpText(L("Shared app groups, system files and privileged helpers are preserved. Apps with drivers or background services may need their vendor uninstaller."))
        .task { if !uninstaller.loaded && !uninstaller.busy { uninstaller.refresh() } }
    }
    private func appHeader(_ app: UninstallApp) -> some View {
        ToolSection(title: "") {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 36, height: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Text(app.name).fontWeight(.semibold); if !app.version.isEmpty { Text(app.version).foregroundStyle(.secondary) } }
                    Text(app.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if let protection = UninstallEngine().protection(for: app) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary).help(L(protection)).accessibilityLabel(L(protection))
                } else if uninstaller.plan == nil { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
    }
    private func fileRow(_ item: UninstallItem, appID: String) -> some View {
        ToolSection(title: "") {
            HStack(alignment: .top, spacing: 12) {
                Toggle(item.url.lastPathComponent, isOn: Binding(get: { uninstaller.selected.contains(item.id) }, set: { value in
                    if value { uninstaller.selected.insert(item.id) } else { uninstaller.selected.remove(item.id) }
                })).labelsHidden().toggleStyle(.checkbox).disabled(item.id == appID || item.issue != nil || uninstaller.busy)
                    .accessibilityLabel(item.url.path)
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.url.lastPathComponent).fontWeight(.medium).textSelection(.enabled)
                    Text(L(item.category)).font(.caption).foregroundStyle(.secondary)
                    Text(item.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if item.nameMatch { HelpText(L("Matched by app name. Verify this folder belongs to this app before selecting it.")) }
                    if let problem = item.problem { problemView(problem, showPath: problem.url.path != item.url.path) }
                    else if let issue = item.issue { HelpText(L(issue)) }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(item.issue == nil ? uninstallSize(item.bytes) : "—").monospacedDigit().font(.callout)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } label: { Image(systemName: "folder") }
                        .buttonStyle(.borderless).help(L("Show in Finder")).accessibilityLabel(LF("Show %@ in Finder", item.url.lastPathComponent))
                }
            }
        }
    }
    private func problemView(_ problem: UninstallProblem, showPath: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HelpText(problem.message)
            if showPath { Text(problem.url.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
            if problem.kind == .permission {
                HelpText(L("File ownership, access rules or macOS privacy controls may block access. Full Disk Access is not confirmed by this error."))
                PermissionHelpButton()
            }
            if problem.kind != .protected && problem.kind != .linked && problem.kind != .unsupported {
                Button(L("Scan App Again"), systemImage: "arrow.clockwise") { uninstaller.rescan() }.disabled(uninstaller.busy)
            }
            if problem.kind == .inUse && !problem.detail.isEmpty { HelpText(problem.detail) }
            if !problem.detail.isEmpty && problem.kind != .protected && problem.kind != .inUse {
                DisclosureGroup(L("Error Details")) { Text(problem.detail).font(.caption).textSelection(.enabled) }
            }
        }
    }
    private func completion(_ result: UninstallResult) -> some View {
        ToolSection(title: result.moved.isEmpty ? L("No Files Moved") : L("Uninstall Result")) {
            if !result.moved.isEmpty {
                Text(LF("Moved %d items", result.moved.count)).fontWeight(.medium)
                HelpText(L(result.inTrash ? "Items are in the Trash. Space is released when you empty it." : "Files remain in Uninstall Recovery"))
                DisclosureGroup(L("Moved Items")) {
                    ForEach(result.moved, id: \.path) { Text($0.path).font(.caption).textSelection(.enabled) }
                }
            }
            if result.cancelled { HelpText(L("Uninstall cancelled. Review moved items and remaining files.")) }
            ForEach(result.failures, id: \.self) { HelpText($0) }
            ForEach(result.problems) { problem in problemView(problem) }
            if let recovery = result.recoveryURL {
                Text(recovery.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                Button(L("Show Recovery Folder"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([recovery]) }
            }
        }
    }
}

struct UninstallActions: View {
    @Bindable var uninstaller: AppUninstaller
    @State private var confirming = false
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(LF("%d items selected · %@", uninstaller.selectedItems.count, uninstallSize(uninstaller.selectedBytes))).fontWeight(.medium)
                Text(L(uninstaller.selectedItems.isEmpty ? "No Files Selected" : "Move to Trash · Recoverable")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if uninstaller.removing { ProgressView().controlSize(.small) }
            Button(L("Uninstall…"), systemImage: "trash") { confirming = true }
                .modifier(PrimaryAction()).disabled(!uninstaller.canUninstall)
        }.modifier(ToolActionBar())
            .sheet(isPresented: $confirming) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(LF("Uninstall %@?", uninstaller.plan?.app.name ?? "")).font(.title2).fontWeight(.semibold)
                    HelpText(L("The selected app and data will be moved to the Trash. Quit the app first. Review the paths below; app data may include settings, sessions and saved work."))
                    Text(LF("%d items selected · %@", uninstaller.selectedItems.count, uninstallSize(uninstaller.selectedBytes))).fontWeight(.medium)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(uninstaller.selectedItems) { item in Text(item.url.path).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }.frame(maxHeight: 240)
                    HelpText(L("A recovery manifest records original paths. Restore only to missing destinations after quitting the app."))
                    HStack {
                        Spacer()
                        Button(L("Cancel"), role: .cancel) { confirming = false }.keyboardShortcut(.cancelAction)
                        Button(L("Move to Trash"), role: .destructive) { confirming = false; uninstaller.uninstall() }.disabled(!uninstaller.canUninstall)
                    }
                }.padding(24).frame(width: 540)
            }
    }
}
