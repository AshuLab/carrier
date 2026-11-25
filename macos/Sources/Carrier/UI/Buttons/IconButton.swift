import CarrierCore
import SwiftUI

/// A 24-point button with an accessible name and a tooltip, drawn in `HoverFillButtonStyle`; `why` is the tooltip and the hint while it is
/// disabled. In a list row it runs its action and does not select the row.
struct IconButton: View {
    let icon: AppIcon
    let name: String
    var enabled = true
    var why: String?
    /// Shown after the name in the tooltip.
    var shortcut: String?
    /// Drawn while what the button opened is open.
    var pressed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Glyph(icon, size: 14).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(open: pressed))
        .disabled(enabled == false)
        .help(enabled ? name + (shortcut.map { " (\($0))" } ?? "") : why ?? name)
        .accessibilityLabel(name)
        .accessibilityHint(enabled ? "" : why ?? "")
        .accessibilityAddTraits(pressed ? .isSelected : [])
    }
}
