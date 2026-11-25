import CarrierCore
import CarrierUI
import SwiftUI

/// The Chips of `CarrierUI/` in the states their catalog entries list.
struct PiecesGalleryChips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("Badge") {
                GalleryState(.normal) { Badge(text: sample(.label), icon: .check, tint: .green) }
                GalleryState(.warning) { Badge(text: sample(.label), icon: .exclamation, tint: .orange) }
                GalleryState(.info) { Badge(text: sample(.label), icon: .info, tint: .indigo) }
            }
            GalleryEntry("ChosenMark") {
                GalleryState(.selected) { ChosenMark() }
            }
            GalleryEntry("PullRequestChip") {
                GalleryState(.normal) { PullRequestChip(number: PiecesGalleryData.pullRequest, dot: nil, link: nil) }
                GalleryState(.open) { PullRequestChip(number: PiecesGalleryData.pullRequest, dot: .green, link: nil) }
                GalleryState(.withLink) { PullRequestChip(number: PiecesGalleryData.pullRequest, dot: .purple, link: PiecesGalleryData.link) }
            }
            GalleryEntry("StatusChip") {
                GalleryState(.normal) { StatusChip(text: sample(.label), tint: .green) }
                GalleryState(.warning) { StatusChip(text: sample(.label), tint: .orange) }
                GalleryState(.error) { StatusChip(text: sample(.label), tint: .red) }
            }
        }
    }
}
