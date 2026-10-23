import Testing
@testable import CarrierCore

// The numbers of the spec's alignment checklist (agent-output-spec.html, section 4b), pinned in one place.
@Test func theLogMetricsAreTheSpecsNumbers() {
    #expect(LogMetrics.iconColumn == 12)
    #expect(LogMetrics.titleColumn == 36)
    #expect(LogMetrics.groupRule == 17)
    #expect(LogMetrics.groupChildIcon == 30)
    #expect(LogMetrics.groupChildDetail == 54)
    #expect(LogMetrics.sliceRule == 19)
    #expect(LogMetrics.sliceChildIcon == 36)
    #expect(LogMetrics.sliceIndent + LogMetrics.titleColumn == 60)
    #expect(LogMetrics.callLine == 26)
    #expect(LogMetrics.groupLine == 28)
    #expect(LogMetrics.sliceLine == 28)
    #expect(LogMetrics.skillRow == 28)
    #expect(LogMetrics.durationColumn == 44)
    #expect(LogMetrics.statusColumn == 14)
    #expect(LogMetrics.chevronColumn == 10)
}

@Test func theChevronTurnsInAFractionOfASecondAndNotUnderReduceMotion() {
    #expect(LogMetrics.chevronTurn(reduceMotion: false) == 0.12)
    #expect(LogMetrics.chevronTurn(reduceMotion: true) == nil)
}
