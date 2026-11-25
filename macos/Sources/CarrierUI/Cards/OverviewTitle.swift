import CarrierCore
import SwiftUI

/// A Carrier home section's title, above the card it heads: the name and, small, what it counts.
public struct OverviewTitle: View {
    let title: String
    var detail: String?

    public init(title: String, detail: String? = nil) { self.title = title; self.detail = detail }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
            Text(title).scaledFont(15, weight: .semibold)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        // in line with the content inside the card below, which the card pads by 14
        .padding(.leading, Tokens.Space.s14)
    }
}
