import Testing
@testable import CarrierCore

private func call(_ arg: String = "solve:ship", status: CallStatus = .ok, ms: Int? = 80) -> ToolCall {
    var call = ToolCall(start: ChatEvent(id: 1, at: 1000, kind: "tool_start", callId: "c", tool: "Skill", arg: arg))
    call.status = status
    call.endedAt = ms.map { 1000 + $0 }
    return call
}

@Test func aDurationIsSpokenInWords() {
    #expect(spokenDuration(725, bundle: english.bundle, locale: english.locale) == "725 milliseconds")
    #expect(spokenDuration(1, bundle: english.bundle, locale: english.locale) == "1 millisecond")
    #expect(spokenDuration(2000, bundle: english.bundle, locale: english.locale) == "2 seconds")
    #expect(spokenDuration(1000, bundle: english.bundle, locale: english.locale) == "1 second")
    #expect(spokenDuration(5240, bundle: english.bundle, locale: english.locale) == "5.2 seconds")
    #expect(spokenDuration(125_000, bundle: english.bundle, locale: english.locale) == "2 minutes 5 seconds")
    #expect(spokenDuration(59_990, bundle: english.bundle, locale: english.locale) == "1 minute")
    #expect(spokenDuration(3_780_000, bundle: english.bundle, locale: english.locale) == "1 hour 3 minutes")
}

@Test func aSkillRowSaysItsNameItsOutcomeAndItsDuration() {
    #expect(callAccessibilityLabel(call(status: .failed, ms: 725), bundle: english.bundle, locale: english.locale) == "solve:ship, failed, 725 milliseconds")
    #expect(callAccessibilityLabel(call(ms: 2000), bundle: english.bundle, locale: english.locale) == "solve:ship, succeeded, 2 seconds")
    #expect(callAccessibilityLabel(call(status: .running, ms: nil), bundle: english.bundle, locale: english.locale) == "solve:ship, running")
    #expect(callAccessibilityLabel(call(status: .stopped, ms: nil), bundle: english.bundle, locale: english.locale) == "solve:ship, stopped")
    #expect(callAccessibilityLabel(call(ms: nil), bundle: english.bundle, locale: english.locale) == "solve:ship, succeeded")
}
