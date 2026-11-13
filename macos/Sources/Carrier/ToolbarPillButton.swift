import SwiftUI

/// A word with its icon for a glass pill of the toolbar: 12 pt type, the pill's height, a quiet fill under the pointer, the count of what is
/// applied as a small accent capsule, and the icon turning while `spinning`. The caller puts the glass on the pill (`.glassEffect(.regular,
/// in: .capsule)`, on the button or on the row of buttons that share one) and hides the toolbar's own (`sharedBackgroundVisibility(.hidden)`):
/// the toolbar's glass is taller than these labels need and cannot be made smaller.
struct ToolbarPillButton: View {
    static let height: CGFloat = 28

    let title: String
    let icon: String
    var badge = 0
    var spinning = false
    /// The icon's own colour (Stop's red); the words keep the text colour.
    var iconTint: Color?
    let action: () -> Void
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.scaled(11, weight: .medium)).foregroundStyle(iconTint ?? .primary).symbolEffect(.rotate, options: .repeating, isActive: spinning)
                Text(title).font(.scaled(12, weight: .medium))
                if badge > 0 {
                    Text("\(badge)").font(.scaled(10, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.themeAccent))
                        .accessibilityLabel("\(badge) filters applied")
                }
            }
            .padding(.horizontal, 11).frame(height: Self.height)
            .background(Capsule().fill(Color.primary.opacity(hovered && enabled ? 0.1 : 0)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain).onHover { hovered = $0 }
        .opacity(enabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.12), value: hovered)
    }
}
