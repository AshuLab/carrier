import Foundation

// The one place that turns a date into an age or into a clock text (docs/specs/settings-app-group.md, Display in General). A duration, how long
// something ran, is not a time: `formatDuration` keeps its form and does not follow the setting.

/// How a time reads: as an age ("11m") or as the clock time of the event ("14:32").
public enum TimeStyle: String { case relative, clock }

/// The clock of a clock time: the Mac's own, or 12 or 24 hours.
public enum ClockHours: String, CaseIterable { case system, h12, h24 }

/// What a call site needs to write a time: the two preferences and where the time is read.
public struct TimeFormat: Equatable {
    public var style: TimeStyle
    public var hours: ClockHours
    public var locale: Locale
    public var timeZone: TimeZone

    public init(style: TimeStyle = .relative, hours: ClockHours = .system, locale: Locale = .current, timeZone: TimeZone = .current) {
        (self.style, self.hours, self.locale, self.timeZone) = (style, hours, locale, timeZone)
    }

    /// The same, as a clock time whatever the style: for a time that is a point in the day and cannot read as an age.
    var asClock: TimeFormat {
        var format = self
        format.style = .clock
        return format
    }

    /// The saved preferences, read in the Mac's locale and time zone.
    public static func stored(in defaults: UserDefaults = .standard) -> TimeFormat {
        let preferences = AppPreferences(defaults: defaults)
        return TimeFormat(style: preferences.timeStyle, hours: preferences.clockHours)
    }
}

/// `relative`: "now", "5m", "3h", "2d". `clock`: the time of the event, "14:32" or "2:32 PM", with "Yesterday " before it for yesterday and
/// "Oct 28 " for older, as `now` sees them.
public func timeText(_ date: Date, now: Date, style: TimeStyle, hours: ClockHours, locale: Locale, timeZone: TimeZone = .current) -> String {
    switch style {
    case .relative:
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    case .clock:
        let time = clockTime(date, hours: hours, locale: locale, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday \(time)"
        }
        let day = DateFormatter()
        (day.locale, day.timeZone, day.dateFormat) = (Locale(identifier: "en_US_POSIX"), timeZone, "MMM d")
        return "\(day.string(from: date)) \(time)"
    }
}

public func timeText(_ date: Date, now: Date, format: TimeFormat = .stored()) -> String {
    timeText(date, now: now, style: format.style, hours: format.hours, locale: format.locale, timeZone: format.timeZone)
}

/// The time of day alone, for a range ("14:02–14:09") that is a clock whatever the Time format says.
public func clockTime(_ date: Date, hours: ClockHours, locale: Locale, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = timeZone
    switch hours {
    case .h24, .h12:
        (formatter.locale, formatter.dateFormat) = (Locale(identifier: "en_US_POSIX"), hours == .h24 ? "HH:mm" : "h:mm a")
    case .system:
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("jmm")
    }
    return formatter.string(from: date)
}

/// The time of day of the engine's time `ms`, in `time`'s clock and zone.
func clockTime(_ ms: Int, time: TimeFormat) -> String {
    clockTime(Date(ms: ms), hours: time.hours, locale: time.locale, timeZone: time.timeZone)
}

extension Date {
    /// The date of the engine's time, ms since the epoch.
    public init(ms: Int) { self.init(timeIntervalSince1970: Double(ms) / 1000) }
}

/// How long ago an event was, "2m 05s ago", or the time of the event when Time format is clock. `ms` is the engine's time.
public func agoText(_ ms: Int, now: Int, format: TimeFormat = .stored()) -> String {
    format.style == .relative
        ? "\(formatDuration(now - ms)) ago"
        : timeText(Date(ms: ms), now: Date(ms: now), format: format)
}

private let spokenAges: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
}()

/// What a screen reader says for an age, "5 minutes ago"; it is for the ear, so it does not follow Time format.
public func spokenAge(_ date: Date, now: Date) -> String { spokenAges.localizedString(for: min(date, now), relativeTo: now) }
