import SwiftUI
import CarrierCore

/// A `TimelineView` that ticks every `period` seconds while someone can see the window and not at all while nobody can: the clocks of "Working
/// for 1m 23s" and the like have nothing to show a hidden window. Outside the window (Settings' previews) nobody says who looks, and it ticks.
struct TickingTimeline<Content: View>: View {
    let every: TimeInterval
    @ViewBuilder let content: (TimelineViewDefaultContext) -> Content
    @Environment(Viewing.self) private var viewing: Viewing?

    var body: some View {
        TimelineView(LookingSchedule(period: every, paused: viewing?.animates == false), content: content)
    }
}

/// A `TimelineView` for an animation: at most 30 frames a second, and none while nobody can see the window. These are slow, ambient motions
/// (a light that goes round, a spark that dims), where 30 looks the same as 60 for half the work, and they run for as long as an agent works.
struct MovingTimeline<Content: View>: View {
    @ViewBuilder let content: (TimelineViewDefaultContext) -> Content
    @Environment(Viewing.self) private var viewing: Viewing?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: viewing?.animates == false), content: content)
    }
}

/// Ticks every `period` seconds from the start, or only the start while `paused`.
struct LookingSchedule: TimelineSchedule {
    let period: TimeInterval
    let paused: Bool

    func entries(from start: Date, mode: TimelineScheduleMode) -> Entries { Entries(pending: start, period: period, paused: paused) }

    struct Entries: Sequence, IteratorProtocol {
        var pending: Date?
        let period: TimeInterval
        let paused: Bool

        mutating func next() -> Date? {
            guard let current = pending else { return nil }
            pending = paused ? nil : current.addingTimeInterval(period)
            return current
        }
    }
}
