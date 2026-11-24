import Foundation
import Testing
@testable import CarrierCore

/// Waits for the status to have its answer in.
@MainActor private func answered(_ status: ReloadStatus) async {
    for _ in 0..<1000 where status.pending { try? await Task.sleep(for: .milliseconds(2)) }
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

@MainActor @Test func anAskOfTheEngineKeepsItsAnswerAndSaysWhyItRefused() async throws {
    let engine = GatedEngine(answers: [.refused(.words("limits.maxReviews: bad"))])
    let status = ReloadStatus(reload: engine.reload)
    _ = status.ask()
    #expect(status.pending)
    await answered(status)
    #expect(engine.calls == 1 && status.outcome == .refused(.words("limits.maxReviews: bad")))
    #expect(status.words == "Saved, but Carrier kept its settings: limits.maxReviews: bad")
}

@MainActor @Test func theAnswerToAnOlderSaveIsDroppedWhenANewerOneWasMade() async throws {
    // the first ask is held by the engine; the second is answered first, and the late refusal of the first must not show
    let engine = GatedEngine(answers: [.refused(.words("old")), .applied], gated: [0])
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
    let engine = GatedEngine(answers: [.refused(.words("bad")), .applied])
    let status = ReloadStatus(reload: engine.reload)
    await status.ask().value
    #expect(status.words != nil)
    await status.ask().value
    #expect(status.words == nil)
}

@MainActor @Test func twoEqualRefusalsInARowAreTwoAnswersSoThePageSaysTheSecondAgain() async {
    let engine = GatedEngine(answers: [.refused(.words("same")), .refused(.words("same"))])
    let status = ReloadStatus(reload: engine.reload)
    await status.ask().value
    await status.ask().value
    #expect(status.outcome == .refused(.words("same")) && status.answers == 2)
}

@MainActor @Test func anEngineThatDoesNotListReloadOrDidNotAnswerIsSaidSoAndNobodyToAskIsNot() {
    #expect(reloadWords(.nobody) == nil && reloadWords(.applied) == nil)
    #expect(reloadWords(.unsupported) == nil)
    #expect(reloadWords(.noAnswer)?.contains("did not answer") == true)
}

@MainActor @Test func aStoppedOrRestartedCarrierStartsWithoutTheAnswerOfTheOneBefore() async {
    let engine = GatedEngine(answers: [.refused(.words("x")), .applied], gated: [1])
    let status = ReloadStatus(reload: engine.reload)
    status.ask()
    await answered(status)
    #expect(status.isProblem && status.words != nil)
    status.reset()
    #expect(status.outcome == nil && status.words == nil && status.pending == false)
    // an ask that was on its way when it was reset does not bring its answer back
    status.ask()
    status.reset()
    engine.open(1)
    try? await Task.sleep(for: .milliseconds(40))
    #expect(status.outcome == nil)
}

@Test func anOlderEnginesReadsItWhenItStartsIsAFactAndARefusalOrSilenceIsAProblem() {
    #expect(ReloadOutcome.unsupported.isProblem == false && ReloadOutcome.applied.isProblem == false && ReloadOutcome.nobody.isProblem == false)
    #expect(ReloadOutcome.refused(.words("x")).isProblem && ReloadOutcome.noAnswer.isProblem)
    #expect(reloadWords(.noAnswer)?.contains("may not have applied it") == true)
}
