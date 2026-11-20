import Foundation
import Testing
@testable import Carrier

@Test func aLookingScheduleTicksEverySecondWhileSomeoneLooksAndOnlyOnceWhenNobodyDoes() {
    let start = Date(timeIntervalSinceReferenceDate: 1000)
    let running = Array(LookingSchedule(period: 1, paused: false).entries(from: start, mode: .normal).prefix(4))
    #expect(running == (0..<4).map { start.addingTimeInterval(Double($0)) })
    // paused it gives the start, so the view has something to draw, and then nothing
    #expect(Array(LookingSchedule(period: 1, paused: true).entries(from: start, mode: .normal)) == [start])
}
