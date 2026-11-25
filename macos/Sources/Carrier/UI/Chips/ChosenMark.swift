import CarrierCore
import SwiftUI

/// The mark of the chosen row of a list: a white tick on a disc of the accent colour, so the tick reads on it.
struct ChosenMark: View {
    var body: some View {
        Glyph(.check, size: 9, bold: true).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(.tint))
            .accessibilityElement(children: .ignore).accessibilityLabel("Chosen")
    }
}
