import CarrierCore
import SwiftUI

/// A session's title in the sidebar: it rolls when it changes (the new words come in from below and the old ones leave above, as the words of a run's line
/// do) and, while the host writes a new one, it shimmers and goes quiet, so a click on "Regenerate title" is seen to be doing something.
struct RollingTitle: View {
    let text: String
    let waiting: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            Text(text).lineLimit(1).truncationMode(.tail).id(text)
                .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .move(edge: .top).combined(with: .opacity)))
        }
        .clipped()
        // a title that waits is quieter, so the shimmer (which lights it) is seen on it
        .opacity(waiting ? 0.55 : 1)
        .modifier(Shimmer(active: waiting && reduceMotion == false))
        .animation(.smooth(duration: 0.45), value: text)
        .animation(.easeOut(duration: 0.25), value: waiting)
        .accessibilityLabel(waiting ? "\(text), writing a new title" : text)
    }
}
