import CarrierCore
import SwiftUI

/// A state as a 16 pt round mark with a white symbol: `checkmark` green for ready, `exclamationmark` yellow for a warning, `xmark` orange for a
/// failure. Next to a spinner (`ProgressView().controlSize(.mini)` in the same 16 pt) for what is still being looked at.
struct StatusMark: View {
    let symbol: AppIcon
    let color: Color
    let label: String

    var body: some View {
        Glyph(symbol, size: 10, bold: true).foregroundStyle(.white)
            .frame(width: 16, height: 16).background(Circle().fill(color)).accessibilityElement(children: .ignore).accessibilityLabel(label)
    }
}
