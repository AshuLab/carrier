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

@Test func aStopCutsTheWaitShortAndEveryWaitAfterItSaysStop() async {
    let flag = StopFlag()
    // not set: the wait is the whole time and says to go on
    #expect(flag.wait(0.05) == true && flag.isSet == false)
    let started = ContinuousClock.now
    // the wait is a minute and the limit half of it: a wait that was not cut short fails, and a runner too busy to start a task for several
    // seconds does not
    let waiting = Task.detached { flag.wait(60) }
    try? await Task.sleep(for: .milliseconds(50))
    flag.set()
    #expect(await waiting.value == false)
    #expect(ContinuousClock.now - started < .seconds(30))
    // once it is set, a wait returns at once and says stop
    let again = ContinuousClock.now
    #expect(flag.wait(60) == false && flag.isSet)
    #expect(ContinuousClock.now - again < .seconds(1))
}
