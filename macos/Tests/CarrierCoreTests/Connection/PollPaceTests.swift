import Foundation
import Testing
@testable import CarrierCore

@Test func theAppAsksSlowlyUntilSomeoneIsLookingAndNeverLessOftenThanTheHostNeedsToKeepSessionsAwake() {
    let pace = PollPace()
    #expect(pace.seconds == PollPace.backgroundSeconds && pace.looking == false)
    pace.set(.focused, lowPower: false)
    #expect(pace.seconds == PollPace.attentiveSeconds && pace.looking)
    for state in [ViewingState.visible, .hidden, .asleep] {
        pace.set(state, lowPower: false)
        #expect(pace.seconds == PollPace.backgroundSeconds, "\(state)")
        #expect(pace.looking == (state == .visible), "\(state)")
    }
    // the host closes a session nobody asked about for a minute
    #expect(PollPace.lowPowerSeconds < 60 && PollPace.backgroundSeconds < PollPace.lowPowerSeconds && PollPace.attentiveSeconds < PollPace.backgroundSeconds)
}

@Test func lowPowerModeAsksLessOftenExceptWhileThePersonIsInTheApp() {
    let pace = PollPace()
    pace.set(.focused, lowPower: true)
    #expect(pace.seconds == PollPace.attentiveSeconds)
    for state in [ViewingState.visible, .hidden, .asleep] {
        pace.set(state, lowPower: true)
        #expect(pace.seconds == PollPace.lowPowerSeconds, "\(state)")
    }
}

@Test func whatServesOnlyTheWindowPausesWhileNobodyCanSeeItAndNeverForAMinute() {
    let pace = PollPace()
    pace.set(.focused, lowPower: false)
    #expect(pace.windowSeconds == PollPace.attentiveSeconds)
    pace.set(.visible, lowPower: false)
    #expect(pace.windowSeconds == PollPace.backgroundSeconds)
    pace.set(.visible, lowPower: true)
    #expect(pace.windowSeconds == PollPace.lowPowerSeconds)
    for state in [ViewingState.hidden, .asleep] {
        pace.set(state, lowPower: false)
        #expect(pace.windowSeconds == conversationPause && pace.windowSeconds < 60, "\(state)")
    }
}

@Test func aStopCutsTheWaitShortAndEveryWaitAfterItSaysStop() async {
    let flag = StopFlag()
    // not set: the wait is the whole time and says to go on
    #expect(flag.wait(0.05) == true && flag.isSet == false)
    let started = ContinuousClock.now
    // the wait is a minute and the limit half of it: a wait that was not cut short fails, and a runner too busy to start a task for several
    // seconds does not
    // on a thread of its own: the wait blocks, and a blocked thread of Swift Concurrency's pool is one less for everything else
    let waiting = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Thread.detachNewThread { continuation.resume(returning: flag.wait(60)) }
        }
    }
    try? await Task.sleep(for: .milliseconds(50))
    flag.set()
    #expect(await waiting.value == false)
    #expect(ContinuousClock.now - started < .seconds(30))
    // once it is set, a wait returns at once and says stop
    let again = ContinuousClock.now
    #expect(flag.wait(60) == false && flag.isSet)
    #expect(ContinuousClock.now - again < .seconds(1))
}

@Test func aWakeCutsOneWaitShortAndKeepsGoing() async {
    let flag = StopFlag()
    // a wake that comes before the wait makes it return at once, once, and with the flag still down
    flag.wake()
    let began = ContinuousClock.now
    #expect(flag.wait(60) == true && flag.isSet == false)
    #expect(ContinuousClock.now - began < .seconds(1))
    // and only once: the wait after it is the whole time (a wait never takes less than it was asked, whatever the load)
    let second = ContinuousClock.now
    #expect(flag.wait(0.2) == true)
    #expect(ContinuousClock.now - second >= .milliseconds(190))
    // one that comes during the wait
    let waiting = Task {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            Thread.detachNewThread { continuation.resume(returning: flag.wait(60)) }
        }
    }
    try? await Task.sleep(for: .milliseconds(50))
    flag.wake()
    #expect(await waiting.value == true)
    #expect(ContinuousClock.now - began < .seconds(30))
}
