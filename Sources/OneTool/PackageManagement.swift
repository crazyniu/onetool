// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct PackageManagementPage: View {
    let manager: PackageManager
    @State private var query = ""
    @State private var installing = false
    @State private var onlyUpdates = false
    @State private var request: PackageRequest?
    private var visiblePackages: [ManagedPackage] {
        manager.packages.filter { (!onlyUpdates || (manager.updateState.isKnown && $0.outdated)) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
            environmentSection
            if manager.busy {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(manager.activity).font(.callout).lineLimit(3)
                }
                HelpText(L("Keep 1Tool open until the operation finishes."))
            }
            if let message = manager.message { Text(message).font(.callout).foregroundStyle(.secondary) }
            if let issue = manager.issue { PackageIssueHelp(manager: manager, issue: issue) }
            if manager.loaded { packageSection }
            if let warning = manager.inventoryWarning {
                ToolSection(title: L("Package Warnings")) {
                    HelpText(L("Some packages have dependency problems. Available packages are still shown; the inventory may be incomplete."))
                    DisclosureGroup(L("Error Details")) { Text(warning).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            if !manager.log.isEmpty {
                ToolSection(title: "") {
                    DisclosureGroup(L("Operation Log")) {
                        ScrollView([.horizontal, .vertical]) {
                            Text(manager.log).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 180).padding(.top, 8)
                    }
                }
            }
        }
        .task { if !manager.attempted { manager.refresh() } }
        .sheet(isPresented: $installing) { PackageInstallSheet(manager: manager) }
        .sheet(item: $request) { pending in
            PackageConfirmationSheet(request: pending, provider: manager.provider) {
                manager.perform(pending)
                request = nil
            }
        }
    }

    private var environmentSection: some View {
        ToolSection(title: "") {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(manager.provider == .brew ? L("Formula & Cask") : manager.selectedEnvironment.map { "Node \($0.nodeVersion) · npm \($0.npmVersion)" } ?? L("Global npm Packages")).fontWeight(.semibold)
                    if let path = manager.globalPrefix ?? manager.executable {
                        Text((manager.provider == .npm ? L("Global Prefix") + ": " : "") + path)
                            .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(2).truncationMode(.middle).help(path)
                    } else if manager.attempted && !manager.busy {
                        HelpText(LF("%@ was not found. Install it or choose its executable, then refresh.", manager.provider.title))
                        Link(L("Installation Guide"), destination: URL(string: manager.provider == .brew ? "https://brew.sh" : "https://nodejs.org/en/download")!)
                    }
                }
                Spacer(minLength: 8)
                HStack(alignment: .center, spacing: Layout.rowSpacing) {
                    Menu {
                        Button(L("Choose Executable…")) { manager.chooseExecutable() }
                        Button(L("Detect Automatically")) { manager.detectAutomatically() }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton).fixedSize()
                        .accessibilityLabel(L("Package Manager Settings"))
                    Button(L("Refresh"), systemImage: "arrow.clockwise") { manager.refresh() }
                }.controlSize(.regular).fixedSize().disabled(manager.busy)
            }
            if manager.environments.count > 1 {
                Picker(L("npm Environment"), selection: Binding(get: { manager.selectedEnvironmentID ?? "" }, set: { manager.selectEnvironment($0) })) {
                    ForEach(manager.environments) { environment in Text(environment.title).tag(environment.id) }
                }.disabled(manager.busy).help(manager.environmentTitle ?? "")
            }
            if manager.provider == .npm {
                DisclosureGroup(L("Environment Details")) {
                    VStack(alignment: .leading, spacing: 8) {
                        if let path = manager.executable { Text("npm: " + path).font(.caption.monospaced()).textSelection(.enabled) }
                        if let path = manager.selectedEnvironment?.engine.nodeExecutable { Text("Node: " + path).font(.caption.monospaced()).textSelection(.enabled) }
                        HelpText(L("Manage global packages for the selected npm installation. Project dependencies are managed in their projects."))
                        ForEach(manager.environmentWarnings, id: \.self) { warning in HelpText(warning) }
                        if !manager.otherManagers.isEmpty {
                            HelpText(L("Other package managers were detected. Their direct packages are listed here for identification and are managed by their own tools."))
                            ForEach(manager.otherManagers, id: \.self) { summary in Text(summary).font(.caption).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                        }
                    }.padding(.top, 6)
                }
            }
        }
    }

    private var packageSection: some View {
        ToolSection(title: LF("Installed Packages (%d)", manager.packages.count)) {
            HStack(spacing: 10) {
                TextField(L("Filter installed packages"), text: $query).textFieldStyle(.roundedBorder)
                Button(L("Install Package"), systemImage: "plus") { installing = true }.disabled(!manager.canManage)
            }
            ViewThatFits(in: .horizontal) {
                HStack { updateButtons; Spacer(); updatesToggle }
                VStack(alignment: .leading, spacing: 8) { HStack { updateButtons; Spacer() }; updatesToggle }
            }
            updateTimestamp
            if visiblePackages.isEmpty {
                if onlyUpdates && !manager.updateState.isKnown {
                    HelpText(manager.updateState.explanation)
                } else {
                    HelpText(manager.packages.isEmpty ? L("No packages installed.") : onlyUpdates && query.isEmpty ? L("No updates available.") : L("No matching packages."))
                }
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visiblePackages) { package in
                        PackageRow(package: package, enabled: manager.canManage, updatesKnown: manager.updateState.isKnown, outcome: manager.outcomes[package.id]) { action in
                            propose(action, packages: [package])
                        }
                        if package.id != visiblePackages.last?.id { Divider() }
                    }
                }
            }
        }
    }

    private var updateButtons: some View {
        Group {
            Button(L("Check for Updates"), systemImage: "arrow.triangle.2.circlepath") { manager.checkUpdates() }
                .disabled(!manager.canManage)
            Button(manager.updateState.isKnown ? LF("Upgrade All (%d)", manager.upgradable.count) : L("Upgrade All")) { propose(.upgrade, packages: manager.upgradable) }
                .disabled(!manager.canManage || manager.upgradable.isEmpty)
        }
    }
    private var updatesToggle: some View { Toggle(L("Updates Only"), isOn: $onlyUpdates).toggleStyle(.checkbox).fixedSize() }
    @ViewBuilder private var updateTimestamp: some View {
        if let date = manager.checkedAt { Text(LF("Checked at %@", date.formatted(date: .omitted, time: .shortened))).font(.caption).foregroundStyle(.secondary) }
        else if !onlyUpdates { Text(manager.updateState.explanation).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
    private func propose(_ action: PackageAction, packages: [ManagedPackage]) {
        request = PackageRequest(action: action, packages: packages, environmentID: manager.environmentID, environmentTitle: manager.environmentTitle)
    }
}

private struct PackageInstallSheet: View {
    let manager: PackageManager
    @State private var name = ""
    @State private var brewKind = PackageKind.formula
    @State private var request: PackageRequest?
    @Environment(\.dismiss) private var dismiss
    private var kind: PackageKind { manager.provider == .npm ? .npm : brewKind }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        Group {
            if let request {
                PackageConfirmationSheet(request: request, provider: manager.provider) { manager.perform(request); dismiss() }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Install Package")).font(.title2).fontWeight(.semibold)
                    if let title = manager.environmentTitle { HelpText(title) }
                    if manager.provider == .brew {
                        Picker(L("Package Type"), selection: $brewKind) {
                            Text("Formula").tag(PackageKind.formula); Text("Cask").tag(PackageKind.cask)
                        }
                    }
                    TextField(manager.provider == .brew ? L("Package name, e.g. wget") : L("Package name, e.g. @scope/package"), text: $name)
                        .textFieldStyle(.roundedBorder).accessibilityLabel(L("Package Name")).onSubmit { review() }
                    HelpText(L("Enter an exact package name. Installation may download dependencies and run the package's install scripts."))
                    HStack {
                        Spacer()
                        Button(L("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                        Button(L("Install")) { review() }.buttonStyle(.borderedProminent).disabled(!manager.canManage || !PackageEngine.validName(trimmedName, kind: kind))
                    }
                }.padding(24).frame(width: 540)
            }
        }
    }
    private func review() {
        guard manager.canManage, PackageEngine.validName(trimmedName, kind: kind) else { return }
        request = PackageRequest(action: .install, packages: [.init(name: trimmedName, kind: kind, version: "", outdated: false)],
                                 environmentID: manager.environmentID, environmentTitle: manager.environmentTitle)
    }
}

struct PackageConfirmationSheet: View {
    let request: PackageRequest
    let provider: PackageProvider
    let confirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    private var note: String {
        switch request.action {
        case .install: return L("Install the following packages and their required dependencies?")
        case .uninstall: return provider == .npm ? L("Uninstall the following global packages?") : L("Uninstall the following packages? Homebrew dependency checks remain enabled.")
        case .upgrade: return provider == .npm ? L("Upgrade these global packages to latest? This can include major version changes.") : L("Upgrade the following packages and their required dependencies?")
        }
    }
    private func packageDetail(_ package: ManagedPackage) -> String {
        var detail = package.kind.title
        if !package.version.isEmpty {
            detail.append(" · ")
            detail.append(package.version)
        }
        if request.action == .upgrade {
            detail.append(" → ")
            detail.append(package.latest ?? "latest")
        }
        return detail
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.action.title).font(.title2).fontWeight(.semibold)
            Text(note).fixedSize(horizontal: false, vertical: true)
            if let environment = request.environmentTitle { Text(environment).font(.caption.monospaced()).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            Text(LF("%d packages selected", request.packages.count)).font(.callout).foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(request.packages) { package in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(package.name).fontWeight(.medium).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text(packageDetail(package))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if package.id != request.packages.last?.id { Divider() }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
            }.frame(height: min(300, CGFloat(request.packages.count) * 65 + 24))
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Spacer()
                Button(L("Cancel"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.action.title, role: request.action == .uninstall ? .destructive : nil) { confirm(); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540)
    }
}

/// The main window places this in its shared bottom safe-area container.
struct PackageOperationStatus: View {
    let manager: PackageManager
    @State private var showDetails = false
    @State private var retry: PackageRequest?
    var body: some View {
        if manager.hasStatus {
            HStack(spacing: 12) {
                if manager.busy { ProgressView().controlSize(.small) }
                else { Image(systemName: manager.issue == nil ? "checkmark.circle" : "exclamationmark.triangle").foregroundStyle(manager.issue == nil ? Color.secondary : .red) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(manager.statusTitle).font(.callout).lineLimit(2).help(manager.statusTitle)
                    if manager.operationCount > 0 && (manager.activePackageID != nil || manager.lastFailedRequest != nil) {
                        Text(LF("%d of %d packages completed", manager.completedCount, manager.operationCount)).font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let issue = manager.issue {
                    Button(L("Details")) { showDetails = true }
                        .popover(isPresented: $showDetails) { PackageIssueHelp(manager: manager, issue: issue).padding(16).frame(width: 510) }
                    if let pending = manager.lastFailedRequest, manager.canManage {
                        Button(L("Retry")) { retry = pending }
                    } else if manager.updateState == .failed && manager.canManage {
                        Button(L("Check for Updates")) { manager.checkUpdates() }
                    }
                    Button(L("Refresh")) { manager.refresh() }.disabled(manager.busy)
                }
            }.sheet(item: $retry) { pending in
                    PackageConfirmationSheet(request: pending, provider: manager.provider) { manager.perform(pending); retry = nil }
                }
        }
    }
}

private struct PackageIssueHelp: View {
    let manager: PackageManager
    let issue: PackageIssue
    var body: some View {
        ToolSection(title: "") {
            Label(issue.title, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.red)
            HelpText(issue.guidance(for: manager.provider))
            if let path = issue.path { Text(path).font(.caption.monospaced()).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            HStack {
                if let command = manager.terminalCommand {
                    Button(L("Copy Command"), systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(command, forType: .string)
                    }
                }
                Button(L("Open Terminal"), systemImage: "terminal") {
                    if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") {
                        NSWorkspace.shared.openApplication(at: app, configuration: .init())
                    }
                }
                Button(L("Refresh")) { manager.refresh() }.disabled(manager.busy)
            }
            if issue.kind == .administrator || issue.kind == .directoryAccess { PermissionHelpButton() }
            DisclosureGroup(L("Error Details")) {
                ScrollView { Text(issue.details).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
            }
        }
    }
}

private struct PackageRow: View {
    let package: ManagedPackage
    let enabled: Bool
    let updatesKnown: Bool
    let outcome: PackageOutcome?
    let action: (PackageAction) -> Void
    private var packageDetail: String {
        var detail = package.kind.title
        detail.append(" · ")
        detail.append(package.version)
        if updatesKnown && package.outdated {
            detail.append(" → ")
            detail.append(package.latest ?? L("Update Available"))
        }
        return detail
    }
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: package.kind == .cask ? "app.dashed" : "shippingbox").foregroundStyle(.secondary).frame(width: 22)
            VStack(alignment: .leading, spacing: 4) {
                Text(package.name).fontWeight(.medium).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text(packageDetail)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if package.pinned { Text(L("Pinned in Homebrew")).font(.caption).foregroundStyle(.secondary) }
                if let outcome {
                    HStack(spacing: 6) {
                        if outcome == .running { ProgressView().controlSize(.mini) }
                        Text(outcome == .running ? L("Operation in progress…") : outcome == .completed ? L("Operation completed.") : L("Package operation failed"))
                            .font(.caption).foregroundStyle(outcome == .failed ? .red : .secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            if updatesKnown && package.outdated && !package.pinned {
                Button(L("Upgrade")) { action(.upgrade) }.help(LF("Upgrade %@", package.name))
            }
            Button(L("Uninstall"), role: .destructive) { action(.uninstall) }.help(LF("Uninstall %@", package.name))
        }.padding(.vertical, 10).disabled(!enabled)
    }
}
