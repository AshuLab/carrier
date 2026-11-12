import Foundation
import Testing
@testable import CarrierCore

/// Waits for the status to have its answer in.
@MainActor private func answered(_ status: ReloadStatus) async {
    for _ in 0..<1000 where status.pending { try? await Task.sleep(for: .milliseconds(2)) }
}

private func config(_ json: String = #"{"repos":[]}"#) throws -> String {
    let path = NSTemporaryDirectory() + "carrier-reload-\(UUID().uuidString).json"
    try Data(json.utf8).write(to: URL(fileURLWithPath: path))
    return path
}

/// An engine that answers `answers` in order, each of them when its gate opens; records the order it was asked in.
private final class GatedEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = 0
    private var gates: [DispatchSemaphore]
    private let answers: [ReloadOutcome]

    init(answers: [ReloadOutcome], gated: Set<Int> = []) {
        self.answers = answers
        gates = answers.indices.map { _ in DispatchSemaphore(value: 0) }
        for index in answers.indices where !gated.contains(index) { gates[index].signal() }
    }

    var calls: Int { lock.withLock { asked } }
    func open(_ index: Int) { gates[index].signal() }

    var reload: Reload {
        {
            let mine = self.lock.withLock { () -> Int in self.asked += 1; return self.asked - 1 }
            self.gates[mine].wait()
            return self.answers[mine]
        }
    }
}

@MainActor @Test func aSaveIsFollowedByOneAskOfTheEngineAndTheAnswerIsKept() async throws {
    let engine = GatedEngine(answers: [.refused("limits.maxReviews: bad")])
    let status = ReloadStatus(reload: engine.reload)
    let path = try config()
    let result = saveConfig(path: path, unusable: "no", edit: { $0 }, reload: { MainActor.assumeIsolated { status.ask() }; return .asked })
    #expect(result == .saved && status.pending)
    await answered(status)
    #expect(engine.calls == 1 && status.outcome == .refused("limits.maxReviews: bad"))
    #expect(status.words == "Saved, but Carrier kept its settings: limits.maxReviews: bad")
}

@MainActor @Test func aSaveThatWroteNothingAsksNothing() async throws {
    let engine = GatedEngine(answers: [.applied])
    let status = ReloadStatus(reload: engine.reload)
    let result = saveConfig(path: NSTemporaryDirectory() + "carrier-missing-\(UUID().uuidString).json", unusable: "no", edit: { $0 }, reload: { MainActor.assumeIsolated { status.ask() }; return .asked })
    #expect(result == .failed("no") && status.pending == false)
    try await Task.sleep(for: .milliseconds(30))
    #expect(engine.calls == 0 && status.outcome == nil)
}

@MainActor @Test func theAnswerToAnOlderSaveIsDroppedWhenANewerOneWasMade() async throws {
    // the first ask is held by the engine; the second is answered first, and the late refusal of the first must not show
    let engine = GatedEngine(answers: [.refused("old"), .applied], gated: [0])
    let status = ReloadStatus(reload: engine.reload)
    let first = status.ask()
    while engine.calls < 1 { try await Task.sleep(for: .milliseconds(2)) }
    let second = status.ask()
    await second.value
    #expect(status.outcome == .applied && status.pending == false)
    engine.open(0)
    await first.value
    #expect(status.outcome == .applied && status.words == nil)
}

@MainActor @Test func anAppliedAnswerClearsTheRefusalOfBefore() async {
    let engine = GatedEngine(answers: [.refused("bad"), .applied])
    let status = ReloadStatus(reload: engine.reload)
    await status.ask().value
    #expect(status.words != nil)
    await status.ask().value
    #expect(status.words == nil)
}

@MainActor @Test func anEngineThatDoesNotListReloadOrDidNotAnswerIsSaidSoAndNobodyToAskIsNot() {
    #expect(reloadWords(.nobody) == nil && reloadWords(.applied) == nil && reloadWords(.asked) == nil)
    #expect(reloadWords(.unsupported)?.hasPrefix("Saved. This Carrier does not apply it while it runs") == true)
    #expect(reloadWords(.noAnswer)?.contains("did not answer") == true)
}
