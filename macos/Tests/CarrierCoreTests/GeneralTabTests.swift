import Testing
@testable import CarrierCore

private final class StubLoginItem: LoginItem {
    var status: LoginItemStatus
    /// what the status reads after a successful register()
    var afterRegister: LoginItemStatus
    var failure: Error?
    var registers = 0
    var unregisters = 0
    var settingsOpened = 0

    init(_ status: LoginItemStatus, afterRegister: LoginItemStatus = .enabled) {
        self.status = status
        self.afterRegister = afterRegister
    }

    func register() throws {
        registers += 1
        if let failure { throw failure }
        status = afterRegister
    }

    func unregister() throws {
        unregisters += 1
        status = .notRegistered
    }

    func openSystemSettings() { settingsOpened += 1 }
}

private struct Refused: Error, CustomStringConvertible { var description: String { "refused" } }

@Test func theRowFollowsTheStatusTheSystemReports() {
    #expect(OpenAtLogin(item: StubLoginItem(.enabled), bundled: true).isOn)
    #expect(OpenAtLogin(item: StubLoginItem(.notRegistered), bundled: true).isOn == false)

    let waiting = OpenAtLogin(item: StubLoginItem(.requiresApproval), bundled: true)
    #expect(waiting.isOn == false)
    #expect(waiting.needsApproval)
    #expect(waiting.note == "Carrier is waiting for your approval in Login Items")
    waiting.openSystemSettings()
}

@Test func aBundleNeverRegisteredReadsNotFoundAndTheSwitchStillWorks() {
    let item = StubLoginItem(.notFound)
    let row = OpenAtLogin(item: item, bundled: true)
    #expect(row.enabled)
    #expect(row.isOn == false)
    #expect(row.note == nil)

    row.set(true)
    #expect(item.registers == 1)
    #expect(row.isOn)

    row.set(false)
    #expect(item.unregisters == 1)
    #expect(row.isOn == false)
}

@Test func turningItOnRegistersAndReadsTheStatusAgain() {
    let item = StubLoginItem(.notRegistered, afterRegister: .requiresApproval)
    let row = OpenAtLogin(item: item, bundled: true)
    row.set(true)
    #expect(row.isOn == false)
    #expect(row.needsApproval)
}

@Test func aRegisterThatThrowsShowsTheErrorUnderTheSwitch() {
    let item = StubLoginItem(.notFound)
    item.failure = Refused()
    let row = OpenAtLogin(item: item, bundled: true)
    row.set(true)
    #expect(row.isOn == false)
    #expect(row.note?.isEmpty == false)
    row.refresh()
    #expect(row.note?.isEmpty == false)
}

@Test func aRegisterThatStillReadsNotFoundSaysToMoveTheApp() {
    let row = OpenAtLogin(item: StubLoginItem(.notFound, afterRegister: .notFound), bundled: true)
    row.set(true)
    #expect(row.note == "Carrier can't register itself from here, move it to /Applications and try again")
}

@Test func withoutABundleTheRowIsDisabledAndNothingIsRegistered() {
    let item = StubLoginItem(.notFound)
    let row = OpenAtLogin(item: item, bundled: false)
    #expect(row.enabled == false)
    #expect(row.note == "Only available from Carrier.app")
    row.set(true)
    #expect(item.registers == 0)
}

private let idle = PanelSnapshot(
    now: 0, slots: .init(busy: 0, total: 2), queue: [], epics: [], startedAt: 0, repos: 1, nextCheckAt: nil,
    problem: nil, paused: false, done: []
)

@Test func theStopQuestionHonoursItsSwitch() {
    let busy = PanelSnapshot(
        now: 0, slots: .init(busy: 1, total: 2), queue: [],
        epics: [PanelEpic(repo: "a/b", issue: 1, status: .running, stage: .ship, round: nil, maxReviews: 3, blockers: 0, stageSince: 0, lastActivityAt: nil, issueUrl: "u", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: nil, executionId: nil)],
        startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: []
    )
    #expect(busy.stopNeedsConfirmation)
    #expect(asksBeforeStopping(busy, switchOn: true))
    #expect(asksBeforeStopping(busy, switchOn: false) == false)
    // nothing running: no question whatever the switch says
    #expect(asksBeforeStopping(idle, switchOn: true) == false)
}
