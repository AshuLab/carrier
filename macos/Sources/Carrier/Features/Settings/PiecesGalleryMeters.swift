import CarrierCore
import SwiftUI

/// The Meters of `Carrier/UI/` in the states their catalog entries list.
struct PiecesGalleryMeters: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GalleryEntry("QuotaBar") {
                GalleryState(.empty) { QuotaBar(solid: 0, hatched: 0).frame(width: 200) }
                GalleryState(.normal) { QuotaBar(solid: 0.3, hatched: 0.2).frame(width: 200) }
                GalleryState(.high) { QuotaBar(solid: 0.7, hatched: 0.25).frame(width: 200) }
            }
            GalleryEntry("QuotaPercent") {
                GalleryState(.normal) { QuotaPercent(used: 0.3) }
                GalleryState(.high) { QuotaPercent(used: 0.93) }
            }
            GalleryEntry("SegmentedProgress") {
                GalleryState(.normal) { SegmentedProgress(done: 3, total: 6).frame(width: 200) }
                GalleryState(.done) { SegmentedProgress(done: 6, total: 6).frame(width: 200) }
                GalleryState(.long) { SegmentedProgress(done: 30, total: 40).frame(width: 200) }
            }
            GalleryEntry("SpinningRing", "RingLayer", "RingHostView") {
                GalleryState(.working) { SpinningRing() }
                GalleryState(.warning) { SpinningRing(diameter: 24, lineWidth: 3, color: .systemOrange) }
            }
            GalleryEntry("SpinningGlyph") {
                GalleryState(.working) { SpinningGlyph(symbol: .refresh, diameter: 16).frame(width: 16, height: 16) }
            }
            GalleryEntry("WorkingRing", "WorkingRingHostView") {
                GalleryState(.working) { WorkingRing().frame(width: ProjectIcon.size, height: ProjectIcon.size) }
                GalleryState(.waiting) { WorkingRing(background: true).frame(width: ProjectIcon.size, height: ProjectIcon.size) }
                GalleryState(.finished) { WorkingRing(finished: true).frame(width: ProjectIcon.size, height: ProjectIcon.size) }
            }
        }
    }
}
