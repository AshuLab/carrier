import CarrierCore
import SwiftUI

/// A provider's logo in the text colour, from the bundled icons; the local servers have none and get a computer.
struct UsageProviderMark: View {
    /// `Claude`, `Codex`, `Antigravity` or `Local`.
    let title: String
    var size: CGFloat = 16

    var body: some View {
        if ProviderMark.image(title.lowercased()) != nil {
            ProviderMark(name: title.lowercased(), size: size).foregroundStyle(.primary).accessibilityHidden(true)
        } else {
            Glyph(.desktop, size: size - 3).foregroundStyle(.secondary).accessibilityHidden(true)
        }
    }
}
