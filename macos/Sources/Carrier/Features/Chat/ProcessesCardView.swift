import CarrierCore
import CarrierUI
import SwiftUI

/// The background processes of the session, as a grey notice over the message box: how many run and their names on one line, Stop (Stop all with
/// more than one) and a chevron that opens the card in place to a row for each, with its own name, how long it has run and its Stop. Nothing is
/// asked of the person, so it has no ring, no glow and no shimmer, and the only timers that tick are the rows' own. The host's `stopTask` is what
/// both Stops use (`ProcessesCard.stop` is nil for a host that cannot, and then there is no Stop at all).
struct ProcessesCardView: View {
    let card: ProcessesCard
    /// Stops them all, one at a time.
    let stopAll: () -> Void
    /// Stops one of them.
    let stopOne: (String) -> Void
    @State private var open = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NoticeCard(symbol: .terminal, tint: .gray, title: card.title, detail: card.names, inline: true) {
            if let stop = card.stop {
                Button(stop, action: stopAll).buttonStyle(NoticeActionStyle()).help(card.stopHelp ?? "").accessibilityLabel(card.stopHelp ?? stop)
            }
            Button { toggle() } label: { LogChevron(open: open).frame(width: 16, height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain).accessibilityLabel(card.spoken)
                .accessibilityHint(open ? Copy.chatProcessesHintHide() : Copy.chatProcessesHintShow())
        } below: {
            if open { rows.transition(reduceMotion ? .opacity : .reveal) }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: open)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: card.processes.map(\.id))
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.3)) { open.toggle() }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            ForEach(card.processes, id: \.id) { process in
                HStack(spacing: Tokens.Space.s10) {
                    Text(process.name).scaledFont(11.5, design: .monospaced).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Tokens.Space.s8)
                    if let started = process.startedAt {
                        TickingTimeline(every: 1) { context in
                            Text(workingElapsed(Int(context.date.timeIntervalSince(started)))).scaledFont(11.5).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    if card.stopsEach {
                        Button(Copy.chatStop()) { stopOne(process.id) }.buttonStyle(NoticeActionStyle(quiet: true))
                            .help(Copy.chatStopTask(name: process.name)).accessibilityLabel(Copy.chatStopTask(name: process.name))
                    }
                }
                .frame(minHeight: 28)
                .accessibilityElement(children: .contain)
            }
        }
        .padding(.top, Tokens.Space.s4)
    }
}
