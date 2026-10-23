// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI
import Charts

struct CleanupAppGroup: Identifiable {
    let name: String
    let items: [CleanupCandidate]
    var id: String { name }
    var bytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var occupiedBytes: Int64 { items.reduce(0) { $0 + $1.occupiedBytes } }
    var eligibleIDs: Set<String> { Set(items.filter { !$0.files.isEmpty }.map(\.id)) }
    static func groups(_ candidates: [CleanupCandidate]) -> [Self] {
        Dictionary(grouping: candidates, by: { $0.rule.owner }).map { Self(name: $0.key, items: $0.value) }
            .sorted { $0.occupiedBytes == $1.occupiedBytes ? $0.name < $1.name : $0.occupiedBytes > $1.occupiedBytes }
    }
}
private func cleanupSize(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

struct CleanupPage: View {
    @Bindable var cleanup: Cleanup
    @Environment(\.toolAccent) private var accent
    @Environment(\.scenePhase) private var scenePhase
    @State private var expanded = Set<String>()
    @State private var filter: CleanupCategory?
    @State private var storage = CleanupEngine.storage()
    private var total: Int64 { storage?.total ?? 0 }
    private var available: Int64 { storage?.available ?? 0 }
    private var eligible: Int64 { cleanup.candidates.reduce(0) { $0 + $1.bytes } }
    private var groups: [CleanupAppGroup] { CleanupAppGroup.groups(cleanup.candidates.filter { filter == nil || $0.rule.category == filter }) }
    var body: some View {
        overview
        if let result = cleanup.result { completion(result) }
        if let scan = cleanup.scan {
            if groups.contains(where: { $0.occupiedBytes > 0 }) { comparison }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Choose What to Clean")).font(.system(size: 16, weight: .semibold))
                    Text(LF("Scanned at %@", scan.date.formatted(date: .omitted, time: .shortened))).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                ChoiceMenu(title: L("Filter"), value: filter?.title ?? L("All Sources"), width: 145) {
                    Button(L("All Sources")) { filter = nil }
                    ForEach(CleanupCategory.allCases) { category in Button(category.title) { filter = category } }
                }
            }.padding(.top, 4)
            if scan.incomplete {
                ToolSection(title: L("Scan Incomplete")) {
                    HelpText(L("Some locations could not be fully inspected. Review the paths below, check access, then scan again."))
                    PermissionHelpButton()
                }
            }
            if groups.isEmpty {
                if filter != nil {
                    ContentUnavailableView {
                        Label(L("No Results in This Category"), systemImage: "line.3.horizontal.decrease.circle")
                    } actions: { Button(L("Show All Sources")) { filter = nil } }
                } else {
                    ContentUnavailableView(L("No Eligible Caches Found"), systemImage: "internaldrive", description: Text(L("No eligible old caches found. Your files are protected.")))
                }
            }
            ForEach(groups) { group in appGroup(group) }
        } else if cleanup.result == nil && !cleanup.busy {
            VStack(alignment: .leading, spacing: 22) {
                ForEach(CleanupCategory.allCases) { category in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: category.symbol).font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 24)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(category.title).fontWeight(.medium)
                            HelpText(L(category == .browsers ? "Web caches older than one day; running apps are skipped." : category == .developer ? "Rebuildable downloads and modules older than seven days." : "Diagnostic and application logs older than thirty days."))
                        }
                    }
                }
            }.padding(.horizontal, 4).padding(.vertical, 12)
        }
        ErrorText(error: cleanup.error)
        Label { HelpText(L("Documents, chat history, login data, installed apps and pending updates are protected.")) } icon: {
            Image(systemName: "lock.shield").foregroundStyle(.secondary)
        }.padding(.vertical, 4)
        .onChange(of: cleanup.busy) { _, busy in
            if !busy { storage = CleanupEngine.storage() }
        }
        .task {
            storage = CleanupEngine.storage()
            if cleanup.result == nil && cleanup.selected.isEmpty { cleanup.startScan(preservingSelection: true) }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            storage = CleanupEngine.storage()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            storage = CleanupEngine.storage()
            if let scan = cleanup.scan, Date().timeIntervalSince(scan.date) > 60,
               cleanup.selected.isEmpty, cleanup.result == nil {
                cleanup.startScan(preservingSelection: true)
            }
        }
    }
    private var overview: some View {
        ToolSection(title: "") {
            HStack(spacing: 26) {
                ZStack {
                    Chart {
                        SectorMark(angle: .value("Bytes", max(0, total - available - eligible)), innerRadius: .ratio(0.82), angularInset: 1.3)
                            .foregroundStyle(Color.primary.opacity(0.14))
                        if eligible > 0 {
                            SectorMark(angle: .value("Bytes", eligible), innerRadius: .ratio(0.82), angularInset: 1.3).foregroundStyle(accent)
                        }
                        SectorMark(angle: .value("Bytes", max(0, available)), innerRadius: .ratio(0.82), angularInset: 1.3)
                            .foregroundStyle(Color.primary.opacity(0.045))
                    }.chartLegend(.hidden).frame(width: 136, height: 136).accessibilityHidden(true)
                    VStack(spacing: 3) {
                        Text(storage.map { $0.usedFraction.formatted(.percent.precision(.fractionLength(1)).locale(AppLanguage.locale)) } ?? "—")
                            .font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(L("Used")).font(.caption).foregroundStyle(.secondary)
                    }
                }.accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Storage Overview")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(cleanup.scan != nil ? cleanupSize(eligible) : storage != nil ? cleanupSize(available) : "—").font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text(L(cleanup.scan == nil ? "Available" : "Reclaimable")).font(.callout).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 14) {
                        Label((storage != nil ? cleanupSize(available) : "—") + " " + L("Available"), systemImage: "circle").foregroundStyle(.secondary)
                        Text(LF("Total %@", storage != nil ? cleanupSize(total) : "—")).foregroundStyle(.tertiary)
                    }.font(.caption)
                    HStack(spacing: 10) {
                        if cleanup.busy {
                            ProgressView().controlSize(.small)
                            Text(L(cleanup.cleaning ? "Cleaning…" : "Scanning…")).font(.callout).foregroundStyle(.secondary)
                            Spacer()
                            Button(L("Cancel")) { cleanup.cancel() }
                        } else {
                            Button(cleanup.scan == nil ? L("Scan Storage") : L("Scan Again"), systemImage: "arrow.clockwise") { cleanup.startScan() }
                                .modifier(PrimaryAction())
                            if cleanup.scan != nil { Text(LF("%d sources", CleanupAppGroup.groups(cleanup.candidates).count)).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(4)
            if cleanup.busy && !cleanup.cleaning { HelpText(L("Checking cache age and files in use…")) }
        }
    }
    private var comparison: some View {
        let top = Array(groups.filter { $0.occupiedBytes > 0 }.prefix(5))
        return ToolSection(title: L("Scanned Cache Usage")) {
            HelpText(L("Includes recent and protected files in scanned locations. Only eligible files can be cleaned."))
            Chart(top) { group in
                BarMark(x: .value(L("Used"), group.occupiedBytes), y: .value(L("Source"), group.name), width: .ratio(0.46))
                    .foregroundStyle(accent).cornerRadius(3)
                    .annotation(position: .trailing, alignment: .leading) { Text(cleanupSize(group.occupiedBytes)).font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit() }
                    .accessibilityLabel(group.name).accessibilityValue(LF("%@ used · %@ reclaimable", cleanupSize(group.occupiedBytes), cleanupSize(group.bytes)))
            }.chartXAxis(.hidden).chartYAxis { AxisMarks { _ in AxisValueLabel().font(.system(size: 11)) } }
                .chartXScale(domain: 0...max(1, Double(top.first?.occupiedBytes ?? 1) * 1.3))
                .frame(height: CGFloat(top.count * 29))
        }
    }
    private func appGroup(_ group: CleanupAppGroup) -> some View {
        let all = !group.eligibleIDs.isEmpty && group.eligibleIDs.isSubset(of: cleanup.selected)
        let partial = !all && !group.eligibleIDs.isDisjoint(with: cleanup.selected)
        return ToolSection(title: "") {
            HStack(spacing: 12) {
                Button {
                    if all { cleanup.selected.subtract(group.eligibleIDs) } else { cleanup.selected.formUnion(group.eligibleIDs) }
                } label: {
                    Image(systemName: all ? "checkmark.square.fill" : partial ? "minus.square.fill" : "square")
                        .font(.system(size: 17)).foregroundStyle(all || partial ? accent : .secondary)
                }.buttonStyle(.plain).disabled(group.eligibleIDs.isEmpty || cleanup.busy)
                    .accessibilityLabel(LF("Select %@", group.name)).accessibilityValue(L(all ? "Selected" : partial ? "Partially Selected" : "Not Selected"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.name).font(.system(size: 14, weight: .semibold))
                    Text(LF("%d cache locations", group.items.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(cleanupSize(group.occupiedBytes) + " " + L("Used")).font(.system(size: 14, weight: .medium)).monospacedDigit()
                    Text(group.bytes > 0 ? cleanupSize(group.bytes) + " " + L("Reclaimable") : L("Protected")).font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    if expanded.contains(group.id) { expanded.remove(group.id) } else { expanded.insert(group.id) }
                } label: { Image(systemName: expanded.contains(group.id) ? "chevron.up" : "chevron.down").frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel(LF("Details: %@", group.name)).help(L("Details"))
            }
            if expanded.contains(group.id) {
                Divider()
                ForEach(group.items) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Toggle(item.rule.name, isOn: Binding(get: { cleanup.selected.contains(item.id) }, set: {
                                if $0 { cleanup.selected.insert(item.id) } else { cleanup.selected.remove(item.id) }
                            })).labelsHidden().toggleStyle(.checkbox).disabled(item.files.isEmpty || cleanup.busy).accessibilityLabel(item.rule.name)
                            Text(item.rule.name).font(.callout).lineLimit(1)
                            Spacer()
                            Text(cleanupSize(item.bytes)).font(.callout).monospacedDigit().foregroundStyle(.secondary)
                        }
                        Text(item.rule.root.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                        if let note = item.note { Label(L(note), systemImage: "shield.lefthalf.filled").font(.caption).foregroundStyle(.secondary) }
                        if !item.uninspectedPaths.isEmpty {
                            Text(item.uninspectedPaths.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            PermissionHelpButton().controlSize(.small)
                        }
                        HStack {
                            HelpText(LF("%d eligible · %d protected", item.files.count, item.skippedFiles))
                            Spacer()
                            Button(L("Reveal in Finder"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([item.rule.root]) }.controlSize(.small)
                        }
                        if !item.files.isEmpty {
                            DisclosureGroup(L("Show Files")) {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(item.files.prefix(12).enumerated()), id: \.offset) { _, file in
                                        HStack {
                                            Text(String(file.url.path.dropFirst(item.rule.root.path.count + 1))).lineLimit(1).truncationMode(.middle)
                                            Spacer()
                                            Text(cleanupSize(file.allocated)).monospacedDigit()
                                        }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                                    }
                                    if item.files.count > 12 { Text(LF("%d more files", item.files.count - 12)).font(.caption).foregroundStyle(.tertiary) }
                                }.padding(.top, 6)
                            }.font(.caption)
                        }
                    }.padding(.vertical, 4)
                    if item.id != group.items.last?.id { Divider() }
                }
            }
        }
    }
    private func completion(_ result: CleanupResult) -> some View {
        ToolSection(title: L(result.outcome == .completed ? "Cleanup Complete" : result.outcome == .cancelled ? "Cleanup Cancelled" : result.outcome == .partial ? "Cleanup Partially Completed" : "Cleanup Failed")) {
            Label(LF("Processed %d files · %@", result.processedFiles, cleanupSize(result.processedBytes)), systemImage: result.outcome == .completed ? "checkmark.circle" : "exclamationmark.circle").font(.headline)
            if result.remainingFiles > 0 { HelpText(LF("%d files were not processed", result.remainingFiles)) }
            if result.permanent {
                HelpText(LF("Available space increased by %@", cleanupSize(max(0, result.freeDelta))))
            } else if result.failures.isEmpty && result.processedFiles > 0 {
                HelpText(L("Moved to Trash. Space is released when you empty Trash."))
            } else if !result.recoveredFolders.isEmpty {
                HelpText(L("Review the recovery locations below. Some files may remain in Cleanup Recovery."))
            }
            if result.skippedFiles > 0 { HelpText(LF("%d changed or busy files were skipped", result.skippedFiles)) }
            ForEach(result.recoveredFolders, id: \.path) { folder in
                Button(L("Show Recoverable Files"), systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }.help(folder.path)
            }
            if !result.failures.isEmpty {
                Text(LF("%d items need attention", result.failures.count)).foregroundStyle(.orange)
                Text(result.failures.prefix(20).joined(separator: "\n")).font(.caption).textSelection(.enabled)
                PermissionHelpButton()
            }
        }
    }
}

/// Kept outside the scrolling results, so the selection and action stay visible.
struct CleanupActions: View {
    @Bindable var cleanup: Cleanup
    @State private var pending: CleanupConfirmation?
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(LF("Selected %@", cleanupSize(cleanup.selectedBytes))).font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    Text(LF("%d cache locations", cleanup.selectedCandidates.count)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L("Deselect All")) { cleanup.selected = [] }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(cleanup.selected.isEmpty)
                Button(cleanup.permanent ? L("Delete Selected…") : L("Move to Trash…"), systemImage: cleanup.permanent ? "trash.slash" : "trash") { pending = CleanupConfirmation(candidates: cleanup.selectedCandidates, permanent: cleanup.permanent) }
                    .modifier(PrimaryAction()).disabled(cleanup.selectedCandidates.isEmpty)
            }
            HStack {
                Toggle(L("Delete Permanently"), isOn: $cleanup.permanent).toggleStyle(.checkbox).font(.caption)
                Spacer()
                Text(L(cleanup.permanent ? "Cannot be undone" : "Recoverable from Trash")).font(.caption).foregroundStyle(.secondary)
            }
        }.modifier(ToolActionBar())
            .disabled(cleanup.busy)
            .sheet(item: $pending) { selection in
                VStack(alignment: .leading, spacing: 16) {
                    Label(L(selection.permanent ? "Delete Permanently" : "Move to Trash"), systemImage: selection.permanent ? "trash.slash" : "trash")
                        .font(.title2).fontWeight(.semibold)
                    Text(LF("Selected %@", cleanupSize(selection.candidates.reduce(0) { $0 + $1.bytes }))).font(.headline)
                    HelpText(L(selection.permanent ? "Cannot be undone" : "Recoverable from Trash"))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(selection.candidates) { item in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(item.rule.owner).fontWeight(.medium); Spacer(); Text(cleanupSize(item.bytes)).monospacedDigit() }
                                    Text(item.rule.root.path).font(.caption).textSelection(.enabled)
                                    Text(LF("%d files", item.files.count)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 260)
                    HelpText(L("Files are checked again before cleanup. Changed or busy files are skipped."))
                    HStack {
                        Spacer()
                        Button(L("Cancel"), role: .cancel) { pending = nil }.keyboardShortcut(.cancelAction)
                        Button(L(selection.permanent ? "Delete Permanently" : "Move to Trash"), role: .destructive) {
                            pending = nil
                            cleanup.cleanSelection(selection.candidates, permanent: selection.permanent)
                        }
                    }
                }.padding(24).frame(width: 520)
            }
    }
}
private struct CleanupConfirmation: Identifiable {
    let id = UUID()
    let candidates: [CleanupCandidate]
    let permanent: Bool
}
