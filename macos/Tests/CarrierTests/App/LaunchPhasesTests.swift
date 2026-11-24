import Testing
@testable import Carrier

@MainActor private final class Order {
    var ran: [String] = []
}

@MainActor @Test func whatWaitsForTheFirstFrameRunsOnceItIsDrawnInTheOrderItWasQueued() {
    let phases = LaunchPhases()
    let order = Order()
    phases.afterFirstFrame { order.ran.append("one") }
    phases.afterFirstFrame { order.ran.append("two") }
    #expect(order.ran.isEmpty && phases.drawn == false)
    phases.fire()
    #expect(order.ran == ["one", "two"] && phases.drawn)
}

@MainActor @Test func whatIsQueuedAfterTheFirstFrameRunsAtOnce() {
    let phases = LaunchPhases()
    let order = Order()
    phases.fire()
    phases.afterFirstFrame { order.ran.append("late") }
    #expect(order.ran == ["late"])
}

@MainActor @Test func aSecondFireRunsNothingAgain() {
    let phases = LaunchPhases()
    let order = Order()
    phases.afterFirstFrame { order.ran.append("once") }
    phases.fire()
    phases.fire()
    #expect(order.ran == ["once"])
}

@MainActor @Test func theRunLoopFiresItAfterTheWindowIsOrderedAndTheTimerOfAWindowlessLaunchDoesNotRunItTwice() async {
    let phases = LaunchPhases()
    let order = Order()
    phases.afterFirstFrame { order.ran.append("drawn") }
    phases.windowOrdered()
    // the observer runs when the main run loop is about to sleep: no clock is asserted, only that it comes
    for _ in 0..<5000 where phases.drawn == false { try? await Task.sleep(for: .milliseconds(2)) }
    #expect(phases.drawn && order.ran == ["drawn"])
    phases.fire()
    #expect(order.ran == ["drawn"])
}
