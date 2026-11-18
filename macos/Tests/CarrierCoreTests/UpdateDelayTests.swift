import Foundation
import Testing
@testable import CarrierCore

@Test func aReleaseIsOfferedOnlyOnceItIsOldEnoughForTheChosenDelay() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let daysAgo = { (days: Double) in now.addingTimeInterval(-days * 86_400) }
    #expect(updateIsOldEnough(published: daysAgo(0), now: now, delayDays: 0))
    #expect(updateIsOldEnough(published: daysAgo(2), now: now, delayDays: 3) == false)
    #expect(updateIsOldEnough(published: daysAgo(3), now: now, delayDays: 3))
    #expect(updateIsOldEnough(published: daysAgo(29.9), now: now, delayDays: 30) == false)
    // a release with no date is offered: there is nothing to wait out
    #expect(updateIsOldEnough(published: nil, now: now, delayDays: 30))
}

@Test func theUpdateDelayIsOneOfTheDaysOfferedAndStartsAtNone() {
    let defaults = UserDefaults(suiteName: "update-delay-\(UUID().uuidString)")!
    let store = AppPreferences(defaults: defaults)
    #expect(store.updateDelayDays == 0)
    store.updateDelayDays = 7
    #expect(AppPreferences(defaults: defaults).updateDelayDays == 7)
    store.updateDelayDays = 5
    #expect(store.updateDelayDays == 0)
    defaults.set(99, forKey: AppPreferences.updateDelayKey)
    #expect(store.updateDelayDays == 0)
    #expect(updateDelayChoices == [0, 1, 3, 7, 14, 30])
}
