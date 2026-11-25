import Foundation
import Testing
@testable import CarrierCore

private func running() throws -> ConnectionState {
    let fixtures = testPaths().fixtures
    return .running(try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json"))))
}

@Test func anEngineThatListsReloadAppliesTheSettingsToTheNextEpic() throws {
    #expect(settingsNote(state: try running(), canReload: true, outcome: nil, bundle: english.bundle, locale: english.locale) == "Carrier applies this repository to the next epic")
    #expect(settingsNote(state: try running(), canReload: true, outcome: .applied, repo: "a/b", bundle: english.bundle, locale: english.locale) == "Carrier applies a/b to the next epic")
}

@Test func anEngineThatDoesNotListReloadKeepsTheOldText() throws {
    #expect(settingsNote(state: try running(), canReload: false, outcome: .unsupported, bundle: english.bundle, locale: english.locale) == "Carrier reads this repository when it starts")
}

@Test func withNoEngineTheOldTextStaysWhateverTheLastHelloListed() {
    for state in [ConnectionState.stopped, .incompatible(update: nil), nil] {
        #expect(settingsNote(state: state, canReload: true, outcome: .nobody, bundle: english.bundle, locale: english.locale) == "Carrier reads this repository when it starts")
    }
}

@Test func aRefusedSaveMakesTheRepoNotInUseWhateverTheEngineCanDo() throws {
    let words = "Not in use: Carrier kept its previous settings"
    #expect(settingsNote(state: try running(), canReload: true, outcome: .refused(.words("repos.1.name: bad")), bundle: english.bundle, locale: english.locale) == words)
    // what an engine once said is not said of a Carrier that is stopped: it reads the file when it starts
    #expect(settingsNote(state: .stopped, canReload: false, outcome: .refused(.words("x")), bundle: english.bundle, locale: english.locale) == "Carrier reads this repository when it starts")
}

@Test func anEngineThatDidNotAnswerMayHaveAppliedItSoTheRepoIsNotSaidToBeKept() throws {
    let words = "Carrier did not answer: it may not have applied this repository"
    #expect(settingsNote(state: try running(), canReload: true, outcome: .noAnswer, bundle: english.bundle, locale: english.locale) == words)
}

@Test func theNewSessionSaysTheSameThingsOfTheRepoItAdded() {
    #expect(addedRepoNote("a/b", outcome: .applied, bundle: english.bundle, locale: english.locale) == (text: "Carrier applies a/b to the next epic", failed: false))
    for outcome in [ReloadOutcome.nobody, .unsupported] {
        #expect(addedRepoNote("a/b", outcome: outcome, bundle: english.bundle, locale: english.locale) == (text: "Carrier reads a/b when it starts", failed: false))
    }
    #expect(addedRepoNote("a/b", outcome: .refused(.words("bad")), bundle: english.bundle, locale: english.locale).failed && addedRepoNote("a/b", outcome: .refused(.words("bad")), bundle: english.bundle, locale: english.locale).text.hasSuffix("kept its settings: bad"))
    #expect(addedRepoNote("a/b", outcome: .noAnswer, bundle: english.bundle, locale: english.locale).failed)
}
