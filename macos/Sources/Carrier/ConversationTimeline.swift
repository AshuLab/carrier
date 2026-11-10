import CarrierCore
import SwiftUI

/// A column of ticks at the left edge of the conversation, one per turn, to move around a long one: the turns on screen are in the theme's colour,
/// the column rests as thin marks and opens up when the pointer is over it, the ticks near the pointer growing like the Dock's icons; a tick under the pointer says what the turn was in a card beside the column, and a click scrolls there. More turns than fit scroll
/// inside the column, which fades out at both ends so it never grows, and keeps the first turn on screen in the middle.
struct ConversationTimeline: View {
    let markers: [TurnMarker]
    /// The turns on screen.
    let current: Set<String>
    let select: (String) -> Void
    @State private var hovered: String?
    /// Whether the pointer is over the column: it rests as thin marks and opens up under the pointer.
    @State private var expanded = false

    private let pitch: CGFloat = 11
    private let height: CGFloat = 240

    var body: some View {
        let shown = markers.first { $0.id == hovered }
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(markers.enumerated()), id: \.element.id) { index, marker in
                        tick(marker, index: index).id(marker.id)
                    }
                }
                .padding(.vertical, 22)
            }
            .scrollClipDisabled(false)
            .frame(width: 34, height: min(height, CGFloat(markers.count) * pitch + 44))
            // the ends fade out, so a long conversation does not make the column taller
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.16), .init(color: .black, location: 0.84), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .onChange(of: current, initial: true) { _, turns in
                guard let id = markers.first(where: { turns.contains($0.id) })?.id else { return }
                withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { expanded = inside } }
        .overlay(alignment: .leading) {
            card(shown).offset(x: 42).allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Conversation timeline")
    }

    /// The width of a tick: like the Dock, the one under the pointer is the longest and its neighbours follow a bell curve around it.
    private func width(at index: Int) -> CGFloat {
        guard expanded else { return 7 }
        guard let under = markers.firstIndex(where: { $0.id == hovered }) else { return 14 }
        let distance = Double(index - under)
        return 14 + 12 * exp(-distance * distance / 6)
    }

    private func tick(_ marker: TurnMarker, index: Int) -> some View {
        let active = current.contains(marker.id)
        let over = marker.id == hovered
        return Button { select(marker.id) } label: {
            Capsule()
                .fill(active ? Color.themeAccent : Color.primary.opacity(over ? 0.7 : 0.28))
                .frame(width: width(at: index), height: 2.5)
                .frame(width: 34, height: pitch, alignment: .leading)
                .padding(.leading, 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(duration: 0.22, bounce: 0.2)) { hovered = inside ? marker.id : (hovered == marker.id ? nil : hovered) } }
        .accessibilityLabel(marker.title)
    }

    /// What the turn was: the person's message over the start of the answer. Always laid out, so it fades in and out.
    private func card(_ marker: TurnMarker?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(marker?.title ?? "").font(.scaled(12, weight: .semibold)).lineLimit(1)
            if marker?.preview.isEmpty == false {
                Text(marker?.preview ?? "").font(.scaled(12)).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(width: 280, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .opacity(marker == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.15), value: marker?.id)
    }
}
