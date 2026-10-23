// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main struct CleanupStateChecks {
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: CleanupEngine.normalizedPath(fm.temporaryDirectory))
            .appendingPathComponent("onetool-cleanup-state-" + UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let cache = root.appendingPathComponent("Cache")
        try fm.createDirectory(at: cache, withIntermediateDirectories: true)
        let file = cache.appendingPathComponent("fixture")
        func write(_ count: Int) throws {
            try Data(repeating: 0x61, count: count).write(to: file)
            try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -10 * 86400)], ofItemAtPath: file.path)
        }
        let rule = CleanupRule(id: "fixture", name: "Fixture", root: cache, category: .developer)
        let model = Cleanup(makeEngine: { CleanupEngine(rules: [rule], stagingRoot: root.appendingPathComponent("Recovery")) },
                            filesInUse: { [] }, runningApplications: { [] })
        func waitForIdle() async throws {
            let deadline = Date().addingTimeInterval(10)
            while model.busy {
                guard Date() < deadline else { fatalError("Cleanup state test timed out") }
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
            print("PASS: " + message)
        }
        try write(4096)
        model.startScan()
        try await waitForIdle()
        let first = model.candidates.first!
        check(first.bytes > 0 && first.occupiedBytes == first.bytes, "initial scan publishes measured cache bytes")
        model.selected = [first.id]
        try write(128 * 1024)
        model.startScan()
        try await waitForIdle()
        check(model.candidates[0].bytes > first.bytes && model.selected.isEmpty, "manual rescan updates capacity and resets the old selection")
        model.selected = [first.id]
        model.cleanSelection(model.selectedCandidates, permanent: true)
        try await waitForIdle()
        check(model.result?.processedFiles == 1 && model.result?.outcome == .completed, "fixture cleanup retains its completion result")
        check(model.scan != nil && model.candidates.isEmpty && model.selected.isEmpty, "cleanup automatically rescans and publishes the empty cache")
        try write(8192)
        model.startScan()
        try await waitForIdle()
        check(model.result == nil && model.candidates[0].occupiedBytes > 0, "a later scan discovers regenerated caches and clears the old completion")
        print("PASS: \(count) cleanup state checks")
    }
}
