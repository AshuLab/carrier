import CarrierCore
import SwiftUI

/// Where the conversation's scroll view is and which feed rows it shows, kept out of the view's own state: the view is drawn again for what
/// it reads, and a scroll or a position set to follow the feed is no reason to lay the whole feed out again.
@MainActor @Observable final class ScrollState {
    var position = ScrollPosition()
    var visible: Set<String> = []
}

/// `scrollPosition` reads the position as it is applied, so applied in the view's own body it would draw the whole feed at each change; here
/// the read is this modifier's.
struct ScrollsWith: ViewModifier {
    let scroll: ScrollState

    func body(content: Content) -> some View {
        @Bindable var scroll = scroll
        content.scrollPosition($scroll.position)
    }
}

/// The timeline at the edge. It reads the rows on screen here, so a scroll draws it and not the conversation.
struct TimelineOverlay: View {
    let markers: [TurnMarker]
    let scroll: ScrollState

    var body: some View {
        ConversationTimeline(markers: markers, current: turns(showing: scroll.visible, in: markers)) { id in
            withAnimation(.smooth(duration: 0.3)) { scroll.position.scrollTo(id: id, anchor: .top) }
        }
    }
}
