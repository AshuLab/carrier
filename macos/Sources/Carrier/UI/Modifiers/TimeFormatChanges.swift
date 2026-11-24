import CarrierCore
import SwiftUI

/// A view that writes an age or a time holds one: it draws again when Time format or Clock change in Settings, and it gives `format` to
/// `timeText`, so the defaults are read once for the view and not once for each time it writes.
struct TimeFormatChanges: DynamicProperty {
    @AppStorage(AppPreferences.timeStyleKey) private var style = TimeStyle.relative.rawValue
    @AppStorage(AppPreferences.clockHoursKey) private var hours = ClockHours.system.rawValue

    /// The format the two values say: a view reads it once instead of reading the defaults for every time it writes.
    var format: TimeFormat { TimeFormat(style: TimeStyle(rawValue: style) ?? .relative, hours: ClockHours(rawValue: hours) ?? .system) }
}
