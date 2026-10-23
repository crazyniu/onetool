// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

@MainActor @Observable final class Cleanup {
    private(set) var scan: CleanupScan?
    private(set) var result: CleanupResult?
    private(set) var busy = false
    private(set) var cleaning = false
    private(set) var progress = 0
    private(set) var error: String?
    var selected = Set<String>()
    var permanent = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var worker: Task<CleanupScan, Error>?
    @ObservationIgnored private var cleaner: Task<CleanupResult, Error>?
    @ObservationIgnored private let makeEngine: @Sendable () -> CleanupEngine
    @ObservationIgnored private let filesInUse: @Sendable () throws -> Set<String>
    @ObservationIgnored private let runningApplications: () -> Set<String>

    init(makeEngine: @escaping @Sendable () -> CleanupEngine = { .live() },
         filesInUse: @escaping @Sendable () throws -> Set<String> = { try CleanupEngine.openFiles() },
         runningApplications: @escaping () -> Set<String> = { Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)) }) {
        self.makeEngine = makeEngine
        self.filesInUse = filesInUse
        self.runningApplications = runningApplications
    }

    var selectedCandidates: [CleanupCandidate] { scan?.candidates.filter { selected.contains($0.id) && !$0.files.isEmpty } ?? [] }
    var selectedBytes: Int64 { selectedCandidates.reduce(0) { $0 + $1.bytes } }
    var candidates: [CleanupCandidate] { scan?.candidates ?? [] }
    func startScan(preservingSelection: Bool = false) {
        guard !busy else { return }
        busy = true; error = nil
        if !preservingSelection { result = nil; selected = [] }
        let engine = makeEngine()
        let filesInUse = self.filesInUse
        let apps = runningApplications()
        worker = Task.detached(priority: .utility) {
            try engine.scan(openFiles: filesInUse(), runningApps: apps, cancelled: { Task.isCancelled })
        }
        task = Task {
            defer { busy = false; worker = nil }
            do {
                scan = try await worker?.value
                selected.formIntersection(Set(candidates.filter { !$0.files.isEmpty }.map(\.id)))
            }
            catch is CancellationError { self.error = L("Scan cancelled. Scan again when you are ready.") }
            catch { self.error = L("Could not inspect open files. Nothing was changed.") }
        }
    }
    func cancel() { worker?.cancel(); cleaner?.cancel() }
    func cleanSelection(_ candidates: [CleanupCandidate], permanent: Bool) {
        guard !busy, !candidates.isEmpty else { return }
        let engine = makeEngine()
        let filesInUse = self.filesInUse
        let apps = runningApplications()
        busy = true; cleaning = true; progress = 0; error = nil; result = nil
        cleaner = Task.detached(priority: .utility) { [weak self] in
            try engine.clean(candidates, permanent: permanent, openFiles: filesInUse(), runningApps: apps,
                cancelled: { Task.isCancelled }, progress: { count in
                    Task { @MainActor [weak self] in self?.progress = count }
                })
        }
        task = Task {
            do { result = try await cleaner?.value; scan = nil; selected = [] }
            catch { self.error = error.localizedDescription }
            busy = false; cleaning = false; cleaner = nil
            if result != nil { startScan(preservingSelection: true) }
        }
    }
}

