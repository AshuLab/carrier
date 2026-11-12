import Foundation
import Testing
@testable import CarrierCore

private func running() throws -> ConnectionState {
    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    return .running(try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json"))))
}

@Test func anEngineThatListsReloadAppliesTheSettingsToTheNextEpic() throws {
    #expect(settingsNote(state: try running(), canReload: true) == "Carrier applies it to the next epic")
}

@Test func anEngineThatDoesNotListReloadKeepsTheOldText() throws {
    #expect(settingsNote(state: try running(), canReload: false) == "Carrier reads it when it starts")
}

@Test func withNoEngineTheOldTextStaysWhateverTheLastHelloListed() {
    for state in [ConnectionState.stopped, .incompatible(update: nil), nil] {
            #expect(settingsNote(state: state, canReload: true) == "Carrier reads it when it starts")
    }
}
