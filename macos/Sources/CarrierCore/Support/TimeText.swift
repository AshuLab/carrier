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
/// "Oct 28 " for older, as `now` sees them. The words and the day follow `locale` (and `bundle`'s language).
public func timeText(
    _ date: Date, now: Date, style: TimeStyle, hours: ClockHours, locale: Locale, timeZone: TimeZone = .current, bundle: Bundle? = nil
) -> String {
    switch style {
    case .relative:
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return Copy.timeNow(bundle: bundle, locale: locale)
        case ..<3600: return Copy.timeMinutes(count: seconds / 60, bundle: bundle, locale: locale)
        case ..<86400: return Copy.timeHours(count: seconds / 3600, bundle: bundle, locale: locale)
        default: return Copy.timeDays(count: seconds / 86400, bundle: bundle, locale: locale)
        }
    case .clock:
        let time = clockTime(date, hours: hours, locale: locale, timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return Copy.timeYesterday(time: time, bundle: bundle, locale: locale)
        }
        let day = clockFormatters.string(from: date, key: "day|\(locale.identifier)|\(timeZone.identifier)") {
            let day = DateFormatter()
            (day.locale, day.timeZone) = (locale, timeZone)
            day.setLocalizedDateFormatFromTemplate("MMMd")
            return day
        }
        return Copy.timeDayAndTime(day: day, time: time, bundle: bundle, locale: locale)
    }
}

public func timeText(_ date: Date, now: Date, format: TimeFormat = .stored(), bundle: Bundle? = nil) -> String {
    timeText(date, now: now, style: format.style, hours: format.hours, locale: format.locale, timeZone: format.timeZone, bundle: bundle)
}

/// The time of day alone, for a range ("14:02–14:09") that is a clock whatever the Time format says.
public func clockTime(_ date: Date, hours: ClockHours, locale: Locale, timeZone: TimeZone = .current) -> String {
    // `hourCycle` is in the key: when the person changes "24-hour time" in the system with no change of region, `.system` is not stale
    let key = "\(hours.rawValue)|\(locale.identifier)|\(locale.hourCycle)|\(timeZone.identifier)"
    return clockFormatters.string(from: date, key: key) {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        switch hours {
        case .h24, .h12:
            // the pattern is the person's choice, the digits and the AM/PM marks are the locale's
            (formatter.locale, formatter.dateFormat) = (locale, hours == .h24 ? "HH:mm" : "h:mm a")
        case .system:
            formatter.locale = locale
            formatter.setLocalizedDateFormatFromTemplate("jmm")
        }
        return formatter
    }
}

/// The formatters a clock time is written with, made once per clock, locale and zone: making one costs far more than writing with it.
/// They never leave the class, so nothing outside can change one that others share.
private final class ClockFormatters: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [String: DateFormatter] = [:]

    func string(from date: Date, key: String, make: () -> DateFormatter) -> String {
        lock.withLock {
            if let formatter = made[key] { return formatter.string(from: date) }
            let formatter = make()
            made[key] = formatter
            return formatter.string(from: date)
        }
    }
}
private let clockFormatters = ClockFormatters()

/// The time of day of the engine's time `ms`, in `time`'s clock and zone.
func clockTime(_ ms: Int, time: TimeFormat) -> String {
    clockTime(Date(ms: ms), hours: time.hours, locale: time.locale, timeZone: time.timeZone)
}

extension Date {
    /// The date of the engine's time, ms since the epoch.
    public init(ms: Int) { self.init(timeIntervalSince1970: Double(ms) / 1000) }
}

/// How long ago an event was, "2m 05s ago", or the time of the event when Time format is clock. `ms` is the engine's time.
public func agoText(_ ms: Int, now: Int, format: TimeFormat = .stored(), bundle: Bundle? = nil) -> String {
    format.style == .relative
        ? Copy.timeAgo(duration: formatDuration(now - ms), bundle: bundle, locale: format.locale)
        : timeText(Date(ms: ms), now: Date(ms: now), format: format, bundle: bundle)
}

/// The formatters of the spoken ages, one for each language: `NSCache` is safe from any thread.
private let spokenAges = NSCache<NSString, RelativeDateTimeFormatter>()

/// What a screen reader says for an age, "5 minutes ago"; it is for the ear, so it does not follow Time format, but it does follow the language.
public func spokenAge(_ date: Date, now: Date, locale: Locale = .current) -> String {
    let key = locale.identifier as NSString
    let formatter = spokenAges.object(forKey: key) ?? {
        let made = RelativeDateTimeFormatter()
        (made.unitsStyle, made.locale) = (.full, locale)
        spokenAges.setObject(made, forKey: key)
        return made
    }()
    return formatter.localizedString(for: min(date, now), relativeTo: now)
}

/// The Updates page's "Last checked" line: the clock time of the last check, or "Never" when the updater has not checked yet.
public func updateCheckedText(_ date: Date?, now: Date, format: TimeFormat = .stored(), bundle: Bundle? = nil) -> String {
    guard let date else { return Copy.timeNever(bundle: bundle, locale: format.locale) }
    return timeText(date, now: now, style: .clock, hours: format.hours, locale: format.locale, timeZone: format.timeZone, bundle: bundle)
}
