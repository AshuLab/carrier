import Foundation

/// How long after a release the app waits before it offers it by itself (Settings > About > Update delay): the days a person can choose, 0 being none.
public let updateDelayChoices = [0, 1, 3, 7, 14, 30]

/// A choice that is not one of the days offered reads as none, so a stray value never holds an update back.
public func clampedUpdateDelay(_ days: Int) -> Int { updateDelayChoices.contains(days) ? days : 0 }

/// Whether a release has been out long enough to be offered by itself. A release with no date cannot be told apart, so it is offered;
/// `Check now` and a critical update do not ask this at all.
public func updateIsOldEnough(published: Date?, now: Date, delayDays: Int) -> Bool {
    guard delayDays > 0, let published else { return true }
    return now.timeIntervalSince(published) >= Double(delayDays) * 86_400
}
