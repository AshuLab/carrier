import CarrierCore
import SwiftUI

/// The small outlined capsule beside a session's title (its workspace, "Archived").
struct RowTag: View {
    let text: String

    var body: some View {
        Text(text).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            .padding(.horizontal, Tokens.Space.tight).padding(.vertical, Tokens.Space.hair).background(Capsule().strokeBorder(Color.secondary.opacity(0.5)))
    }
}
