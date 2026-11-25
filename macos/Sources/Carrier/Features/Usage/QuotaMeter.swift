import CarrierCore
import SwiftUI

extension QuotaBar {
    /// The bar of a meter's `shape`.
    init(shape: MeterShape, height: CGFloat = 8) { self.init(solid: shape.solid, hatched: shape.hatched, height: height) }
}

extension QuotaPercent {
    /// The number of a meter's `shape`.
    init(shape: MeterShape) { self.init(used: shape.used) }
}

/// A quota with its name and percent above its bar: the provider rows' meters. Only the Usage page draws it.
struct QuotaMeter: View {
    let label: String
    let shape: MeterShape

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s5) {
            HStack {
                Text(label).font(.scaled(11)).foregroundStyle(.secondary)
                Spacer()
                QuotaPercent(shape: shape)
            }
            QuotaBar(shape: shape)
        }
    }
}
