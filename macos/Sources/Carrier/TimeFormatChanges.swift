import CarrierCore
import SwiftUI

/// A view that writes an age or a time holds one: it draws again when Time format or Clock change in Settings, and the formatter reads
/// the new values by itself.
struct TimeFormatChanges: DynamicProperty {
    @AppStorage(AppPreferences.timeStyleKey) private var style = TimeStyle.relative.rawValue
    @AppStorage(AppPreferences.clockHoursKey) private var hours = ClockHours.system.rawValue
}
