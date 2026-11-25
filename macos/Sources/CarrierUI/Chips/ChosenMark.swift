import CarrierCore
import SwiftUI

/// The mark of the chosen row of a list: a white tick on a disc of the accent colour, so the tick reads on it.
public struct ChosenMark: View {

    public init() {}
    public var body: some View {
        Glyph(.check, size: 9, bold: true).foregroundStyle(.white)
            .frame(width: 18, height: 18).background(Circle().fill(.tint))
            .accessibilityElement(children: .ignore).accessibilityLabel(Copy.pieceChosen())
    }
}
