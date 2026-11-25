import Testing
@testable import CarrierCore

// The numbers of the spec's alignment checklist (agent-output-spec.html, section 4b), pinned in one place.
@Test func theLogMetricsAreTheSpecsNumbers() {
    #expect(LogMetrics.iconColumn == 12)
    #expect(LogMetrics.skillRow == 30)
    #expect(LogMetrics.durationColumn == 44)
    #expect(LogMetrics.statusColumn == 14)
    #expect(LogMetrics.chevronColumn == 10)
}

@Test func theChevronTurnsInAFractionOfASecondAndNotUnderReduceMotion() {
    #expect(LogMetrics.chevronTurn(reduceMotion: false) == 0.12)
    #expect(LogMetrics.chevronTurn(reduceMotion: true) == nil)
}
