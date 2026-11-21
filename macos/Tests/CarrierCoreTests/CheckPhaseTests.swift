import Testing

@testable import CarrierCore

@Test func aCheckTheyAskedForShowsHowItEnded() {
    #expect(CheckPhase.idle.moving(checking: true, failed: false, asked: true) == .checking)
    #expect(CheckPhase.checking.moving(checking: false, failed: false, asked: true) == .done)
    #expect(CheckPhase.checking.moving(checking: false, failed: true, asked: true) == .failed)
    // a result stays while the next check has not begun
    #expect(CheckPhase.done.moving(checking: false, failed: false, asked: true) == .done)
}

@Test func aCheckThePageRanByItselfEndsAtRest() {
    #expect(CheckPhase.checking.moving(checking: false, failed: false, asked: false) == .idle)
    #expect(CheckPhase.checking.moving(checking: false, failed: true, asked: false) == .idle)
    #expect(CheckPhase.idle.moving(checking: false, failed: true, asked: true) == .idle)
}

@Test func onlyRestAndFailureTakeAClick() {
    #expect(CheckPhase.idle.accepts)
    #expect(CheckPhase.failed.accepts)
    #expect(CheckPhase.checking.accepts == false)
    #expect(CheckPhase.done.accepts == false)
}

@Test func theDoctorThatDidNotAnswerIsAFailedCheck() {
    #expect(DoctorState.unknown("no").failedToAnswer)
    #expect(DoctorState.refused("no").failedToAnswer)
    #expect(DoctorState.checks([]).failedToAnswer == false)
    #expect(DoctorState.running.failedToAnswer == false)
}
