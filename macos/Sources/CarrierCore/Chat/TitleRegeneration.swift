import Foundation
import Observation

/// What a click on "Regenerate title" looks like while the host writes the new one: the session's title is shown waiting (the row shimmers) for at least `minimum`,
/// so the click is seen to do something even when the model answers at once, and for as long as the model takes when that is longer. Then the new title takes
/// the old one's place (the row rolls it in) and is held here, for a few seconds, until the host's list says it too: the list is read on its own beat and would
/// show the old title for a moment after the wait ended.
@MainActor @Observable public final class TitleRegeneration {
    public static let shared = TitleRegeneration()

    /// The sessions whose title is being written.
    public private(set) var waiting: Set<String> = []
    private var fresh: [String: String] = [:]
    /// The title each waiting session had when the click came: the list may bring the new one while the wait lasts, and the shimmer must still run on the old.
    private var held: [String: String] = [:]
    @ObservationIgnored private let minimum: Duration
    @ObservationIgnored private let keeps: Duration
    @ObservationIgnored private let sleep: (Duration) async -> Void

    public init(minimum: Duration = .seconds(2), keeps: Duration = .seconds(10), sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        (self.minimum, self.keeps, self.sleep) = (minimum, keeps, sleep)
    }

    /// What the row's title says now: the old one all the while the new one is being written, then the new one until the list has caught up with it, else the list's.
    public func title(of row: SessionRow) -> String { held[row.id] ?? fresh[row.id] ?? row.title }

    /// Runs `write` (the host's request) with the title shown waiting (`current` is what it says now), and answers what the host refused, in words, or nil. A
    /// session already waiting is left alone.
    public func regenerate(_ id: String, showing current: String, write: () async -> (title: String?, refusal: String?)) async -> String? {
        guard waiting.contains(id) == false else { return nil }
        held[id] = current
        waiting.insert(id)
        let began = ContinuousClock.now
        let result = await write()
        let spent = ContinuousClock.now - began
        if spent < minimum { await sleep(minimum - spent) }
        // the old title goes and the new one comes in the same change, which is what the row rolls
        held[id] = nil
        if let title = result.title {
            fresh[id] = title
            Task {
                await sleep(keeps)
                if fresh[id] == title { fresh[id] = nil }
            }
        }
        waiting.remove(id)
        return result.refusal
    }
}
