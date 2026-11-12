import Testing
@testable import CarrierCore

@Test func theAppAsksSlowlyUntilSomeoneIsLookingAndNeverLessOftenThanTheHostNeedsToKeepSessionsAwake() {
    let pace = PollPace()
    #expect(pace.seconds == PollPace.backgroundSeconds)
    pace.set(attentive: true)
    #expect(pace.seconds == PollPace.attentiveSeconds)
    pace.set(attentive: false)
    #expect(pace.seconds == PollPace.backgroundSeconds)
    // the host closes a session nobody asked about for a minute
    #expect(PollPace.backgroundSeconds < 60 && PollPace.attentiveSeconds < PollPace.backgroundSeconds)
}
