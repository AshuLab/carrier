import SwiftUI

/// The line between two rows of a card: a whole point tall and quiet, where the system's Divider is a grey hairline that stands out on the dark themes.
struct SettingsDivider: View {
    /// A line between two columns (the Usage page's cards) instead of two rows.
    var vertical = false

    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.07)).frame(width: vertical ? 1 : nil, height: vertical ? nil : 1).accessibilityHidden(true)
    }
}
