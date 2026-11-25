import CarrierCore
import SwiftUI

/// The Feedback pieces of `Carrier/UI/` in the states their catalog entries list.
struct PiecesGalleryFeedback: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GalleryEntry("BannerView") {
                GalleryState(.error) { banner(.red, copy: true, retry: true) }
                GalleryState(.warning) { banner(.orange, copy: false, retry: true) }
                GalleryState(.record) { banner(.red, copy: true, retry: false) }
            }
            GalleryEntry("EmptyStateView", "EmptyStateActionStyle") {
                GalleryState(.empty) { EmptyStateView(icon: .archive, title: sample(.title), line: sample(.detail)).frame(width: 320, height: 210) }
                GalleryState(.withActions) {
                    EmptyStateView(icon: .archive, title: sample(.title), line: sample(.detail), action: (sample(.action), {}), actionStyle: .secondary).frame(width: 320, height: 250)
                }
                GalleryState(.withIcon) {
                    EmptyStateView(icon: .archive, title: sample(.title), line: sample(.detail), action: (sample(.action), {}), actionIcon: .plus, actionStyle: .accentGlass).frame(width: 320, height: 250)
                }
            }
            GalleryEntry("LoadingStateView") {
                GalleryState(.loading) { LoadingStateView(title: sample(.title), line: sample(.detail)).frame(width: 320, height: 210) }
            }
            GalleryEntry("GlowEdge") {
                GalleryState(.working) { glow(waiting: false, moves: true) }
                GalleryState(.waiting) { glow(waiting: true, moves: true) }
                GalleryState(.still) { glow(waiting: false, moves: false) }
            }
            GalleryEntry("ProblemLine") {
                GalleryState(.error) { ProblemLine(text: sample(.problem), announces: false) }
            }
            GalleryEntry("RollingTitle") {
                GalleryState(.normal) { RollingTitle(text: sample(.title), waiting: false) }
                GalleryState(.waiting) { RollingTitle(text: sample(.title), waiting: true) }
            }
            GalleryEntry("Shimmer") {
                GalleryState(.normal) { Text(sample(.title)).foregroundStyle(.secondary).modifier(Shimmer(active: false)) }
                GalleryState(.working) { Text(sample(.title)).foregroundStyle(.secondary).modifier(Shimmer(active: true)) }
            }
        }
    }

    private func banner(_ tint: Color, copy: Bool, retry: Bool) -> some View {
        BannerView(
            title: sample(.title), detail: sample(.detail), hint: sample(.hint), tint: tint, copyDetails: copy ? {} : nil, retry: retry ? {} : nil
        )
        .frame(width: 520)
    }

    private func glow(waiting: Bool, moves: Bool) -> some View {
        GlowEdge(color: .accentColor, waiting: waiting, moves: moves).frame(width: 150, height: 54)
    }
}
