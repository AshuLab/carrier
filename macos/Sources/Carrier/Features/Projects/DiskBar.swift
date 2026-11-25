import AppKit
import CarrierCore
import SwiftUI

/// The bar of a project's disk: one segment for each folder, as wide as its share, in the colour of its dot.
struct DiskBar: View {
    let shares: [DiskShare]
    let color: (String) -> Color

    var body: some View {
        GeometryReader { geometry in
            let room = geometry.size.width - CGFloat(shares.count - 1)
            HStack(spacing: Tokens.Space.s1) {
                ForEach(shares) { share in color(share.id).frame(width: max(2, room * share.fraction)) }
            }
            .frame(width: geometry.size.width, alignment: .leading)
            .background(Color.primary.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
        .frame(height: 8).accessibilityHidden(true)
    }
}
