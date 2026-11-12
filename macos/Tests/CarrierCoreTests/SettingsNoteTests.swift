import Foundation
import Testing
@testable import CarrierCore

private func running() throws -> ConnectionState {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    return .running(try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json"))))
}

@Test func anEngineThatListsReloadAppliesTheSettingsToTheNextEpic() throws {
    #expect(settingsNote(state: try running(), canReload: true, outcome: nil) == "Carrier applies this repo to the next epic")
    #expect(settingsNote(state: try running(), canReload: true, outcome: .applied, repo: "a/b") == "Carrier applies a/b to the next epic")
}

@Test func anEngineThatDoesNotListReloadKeepsTheOldText() throws {
    #expect(settingsNote(state: try running(), canReload: false, outcome: .unsupported) == "Carrier reads this repo when it starts")
}

@Test func withNoEngineTheOldTextStaysWhateverTheLastHelloListed() {
    for state in [ConnectionState.stopped, .incompatible(update: nil), nil] {
        #expect(settingsNote(state: state, canReload: true, outcome: .nobody) == "Carrier reads this repo when it starts")
    }
}

@Test func aRefusedSaveMakesTheRepoNotInUseWhateverTheEngineCanDo() throws {
    let words = "Not in use: Carrier kept its previous settings"
    #expect(settingsNote(state: try running(), canReload: true, outcome: .refused("repos.1.name: bad")) == words)
    #expect(settingsNote(state: .stopped, canReload: false, outcome: .refused("x")) == words)
}

@Test func anEngineThatDidNotAnswerMayHaveAppliedItSoTheRepoIsNotSaidToBeKept() throws {
    let words = "Carrier did not answer: it will read this repo when it starts"
    #expect(settingsNote(state: try running(), canReload: true, outcome: .noAnswer) == words)
}

@Test func theNewSessionSaysTheSameThingsOfTheRepoItAdded() {
    #expect(addedRepoNote("a/b", outcome: .applied) == (text: "Carrier applies a/b to the next epic", failed: false))
    for outcome in [ReloadOutcome.nobody, .unsupported] {
        #expect(addedRepoNote("a/b", outcome: outcome) == (text: "Carrier reads a/b when it starts", failed: false))
    }
    #expect(addedRepoNote("a/b", outcome: .refused("bad")).failed && addedRepoNote("a/b", outcome: .refused("bad")).text.hasSuffix("kept its settings: bad"))
    #expect(addedRepoNote("a/b", outcome: .noAnswer).failed)
}
