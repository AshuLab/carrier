import CarrierCore
import SwiftUI

/// The card that opens beside a session's row when the pointer rests on it, like an epic's (`EpicCardView`): the whole title, the last
/// thing the agent wrote, the facts of where it works and when it last moved, and what the row's third line says: its pull request, the
/// lines it changed and what the agent waits for.
struct SessionPeekView: View {
    let card: SessionPeek

    /// The violet of the ring for work in hand, deeper on light, where the ring's own pale one has about 2:1 against the card.
    private static let working = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.79, green: 0.63, blue: 1.0, alpha: 1) : NSColor(red: 0.42, green: 0.22, blue: 0.72, alpha: 1)
    })

    /// The colours of the row's own words: violet while it writes, cyan while it waits for what it started, orange for what needs the person, green for Done.
    private var tone: Color {
        switch card.tone {
        case .quiet: .secondary
        case .working: Self.working
        case .background: SessionRowView.backgroundWork
        case .attention: SessionRowView.attention
        case .done: SessionRowView.done
        }
    }

    /// The most of the tasks it waits for that the card lists, and "+n" for the rest.
    private static let tasksShown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ProjectIcon(name: card.name, colorKey: projectColorKey(card.name), working: card.tone == .working || card.tone == .background, background: card.tone == .background)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(.scaled(14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(card.subtitle).font(SidebarMetrics.detail).fontWeight(card.tone == .quiet ? .regular : .medium).foregroundStyle(tone)
                }
            }
            if let message = card.lastMessage {
                Text(message).font(SidebarMetrics.detail).foregroundStyle(.secondary).lineLimit(4)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            }
            CardFactsGrid(facts: card.facts) {
                if let pullRequest = card.pullRequest {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Pull request").foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            SessionPullRequestChip(pr: pullRequest)
                            if let diff = card.diff { DiffText(diff: diff) }
                        }
                    }
                } else if let diff = card.diff {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Changes").foregroundStyle(.secondary)
                        DiffText(diff: diff)
                    }
                }
                if card.background.isEmpty == false {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Waiting on").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(card.background.prefix(Self.tasksShown), id: \.id) { task in
                                HStack(spacing: 6) {
                                    Circle().fill(SessionRowView.backgroundWork).frame(width: 6, height: 6).accessibilityHidden(true)
                                    Text(task.name).font(.scaled(10.5, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                                }
                            }
                            if card.background.count > Self.tasksShown {
                                Text("+\(card.background.count - Self.tasksShown) more").font(.scaled(11)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Text(card.timeline).font(.scaled(11.5)).foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
    }
}
