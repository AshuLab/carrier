import Foundation
import Testing
@testable import CarrierCore

private func footer(_ state: ConnectionState?, dirty: Bool = true, valid: Bool = true, missing: [String] = []) -> BehaviorFooter {
    behaviorFooter(state: state, dirty: dirty, valid: valid, startMissing: missing)
}

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

private func running() throws -> ConnectionState {
    .running(try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json"))))
}

@Test func aStoppedCarrierGetsAPlainSave() {
    for state in [ConnectionState.stopped, .incompatible, nil] {
        let stopped = footer(state)
        #expect(stopped.offersRestart == false && stopped.canSave && stopped.canRestart == false)
        #expect(stopped.message == "Carrier is stopped.")
    }
    #expect(footer(.stopped, dirty: false).message == "Carrier reads these when it starts.")
}

@Test func nothingIsSavedWithoutChangesOrWithBadValues() {
    #expect(footer(.stopped, dirty: false).canSave == false)
    #expect(footer(.stopped, valid: false).canSave == false)
}

@Test func aRunningCarrierGetsSaveAndRestartAndSaveOnly() throws {
    let state = try running()
    let dirty = footer(state)
    #expect(dirty.offersRestart && dirty.canSave && dirty.canRestart)
    #expect(dirty.message == "Carrier is running with the old values.")
    #expect(footer(state, dirty: false).canRestart == false)
    #expect(footer(state, valid: false).canRestart == false)
}

@Test func restartIsOffWhenStartCarrierIsNotReadyAndSaysWhy() throws {
    let blocked = footer(try running(), missing: ["node", "carrier"])
    #expect(blocked.canSave && blocked.canRestart == false)
    #expect(blocked.message == "Carrier is running with the old values. Restart is off: Start Carrier needs node, carrier.")
}

@Test func theWarningNamesTheEpicsOnlyWhenThereAreAndTheQuestionIsOn() {
    #expect(restartWarning(epics: 0, asks: true) == nil)
    #expect(restartWarning(epics: 2, asks: false) == nil)
    #expect(restartWarning(epics: 1, asks: true) == "Restart interrupts 1 running epic. It resumes from where it was when Carrier starts again.")
    #expect(restartWarning(epics: 2, asks: true)?.hasPrefix("Restart interrupts 2 running epics. They resume") == true)
}
