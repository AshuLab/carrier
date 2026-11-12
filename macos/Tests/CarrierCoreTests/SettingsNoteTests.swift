import Foundation
import Testing
@testable import CarrierCore

private func running() throws -> ConnectionState {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    return .running(try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json"))))
}

@Test func anEngineThatListsReloadAppliesTheSettingsToTheNextEpic() throws {
    #expect(settingsNote(state: try running(), canReload: true) == "Carrier applies this repo to the next epic")
}

@Test func anEngineThatDoesNotListReloadKeepsTheOldText() throws {
    #expect(settingsNote(state: try running(), canReload: false) == "Carrier reads this repo when it starts")
}

@Test func withNoEngineTheOldTextStaysWhateverTheLastHelloListed() {
    for state in [ConnectionState.stopped, .incompatible(update: nil), nil] {
            #expect(settingsNote(state: state, canReload: true) == "Carrier reads this repo when it starts")
    }
}

@Test func aSaveTheEngineDidNotApplyMakesTheRepoNotInUseWhateverTheEngineCanDo() throws {
    let words = "Not in use: Carrier kept its previous settings"
    #expect(settingsNote(state: try running(), canReload: true, kept: true) == words)
    #expect(settingsNote(state: .stopped, canReload: false, kept: true) == words)
}
