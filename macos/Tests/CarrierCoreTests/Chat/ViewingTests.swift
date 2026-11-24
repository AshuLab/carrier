import Foundation
import Synchronization
import Testing
@testable import CarrierCore

@Test func aSleepingMacWinsThenAWindowOffScreenThenTheAppNotBeingInFront() {
    // every combination of (app in front, window on screen, asleep)
    let table: [(Bool, Bool, Bool, ViewingState)] = [
        (true, true, false, .focused), (false, true, false, .visible),
        (true, false, false, .hidden), (false, false, false, .hidden),
        (true, true, true, .asleep), (false, true, true, .asleep), (true, false, true, .asleep), (false, false, true, .asleep),
    ]
    for (appActive, windowShown, asleep, expected) in table {
        #expect(viewingState(appActive: appActive, windowShown: windowShown, asleep: asleep) == expected, "\(appActive) \(windowShown) \(asleep)")
    }
}

@MainActor @Test func viewingTellsThePaceAndEveryoneWatchingOnlyWhenSomethingChanged() {
    let viewing = Viewing()
    let pace = PollPace()
    let changes = Mutex(0)
    func watch() {
        withObservationTracking {
            _ = viewing.state
            _ = viewing.lowPower
        } onChange: { changes.withLock { $0 += 1 } }
    }

    #expect(viewing.state == .hidden && viewing.animates == false)
    watch()
    viewing.update(appActive: true, windowShown: true, asleep: false, lowPower: false, pace: pace)
    #expect(changes.withLock { $0 } == 1 && viewing.state == .focused && viewing.animates)
    #expect(pace.seconds == PollPace.attentiveSeconds && pace.looking)

    // the same inputs again: nobody is told
    watch()
    viewing.update(appActive: true, windowShown: true, asleep: false, lowPower: false, pace: pace)
    #expect(changes.withLock { $0 } == 1)

    // Low Power alone is a change, and it reaches the pace
    viewing.update(appActive: false, windowShown: false, asleep: false, lowPower: true, pace: pace)
    #expect(changes.withLock { $0 } == 2 && viewing.state == .hidden && viewing.lowPower && viewing.animates == false)
    #expect(pace.seconds == PollPace.lowPowerSeconds && pace.looking == false)
}

@Test func theBarOfTheMenuIconBouncesOnlyWhenTheSettingIsOnTheMacIsAwakeAndNotInLowPower() {
    // the window being hidden does not stop it: it is there to be seen with the window closed
    for state in [ViewingState.focused, .visible, .hidden] {
        #expect(iconAnimates(setting: true, state: state, lowPower: false), "\(state)")
        #expect(iconAnimates(setting: true, state: state, lowPower: true) == false, "\(state) in Low Power")
        #expect(iconAnimates(setting: false, state: state, lowPower: false) == false, "\(state) switched off")
    }
    #expect(iconAnimates(setting: true, state: .asleep, lowPower: false) == false)
}
