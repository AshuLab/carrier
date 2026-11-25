import CarrierCore
import CarrierUI
import SwiftUI

/// The card that opens beside a session's row when the pointer rests on it, like an epic's (`EpicCardView`): the whole title, the last
/// thing the agent wrote, the facts of where it works and when it last moved, and what the row's third line says: its pull request, the
/// lines it changed and what the agent waits for.
struct SessionPeekView: View {
    let card: SessionPeek

    /// The violet of the ring for work in hand, deeper on light, where the ring's own pale one has about 2:1 against the card.
    private static let working = Color(Tokens.Status.working)

    /// The colours of the row's own words: violet while it writes, cyan while it waits for what it started, orange for what needs the person, green for Done.
    private var tone: Color {
        switch card.tone {
        case .quiet: .secondary
        case .working: Self.working
        case .background: Color.backgroundWork
        case .attention: SessionRowView.attention
        case .done: Color.sessionDone
        }
    }

    /// The most of the tasks it waits for that the card lists, and "+n" for the rest.
    private static let tasksShown = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s12) {
            HStack(alignment: .top, spacing: Tokens.Space.s10) {
                ProjectIcon(base: card.base, name: card.name, colorKey: projectColorKey(card.name), working: card.tone == .working || card.tone == .background, background: card.tone == .background)
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    Text(card.title).scaledFont(14, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                    Text(card.subtitle).sidebarFont(.detail).fontWeight(card.tone == .quiet ? .regular : .medium).foregroundStyle(tone)
                }
            }
            if let message = card.lastMessage {
                Text(message).sidebarFont(.detail).foregroundStyle(.secondary).lineLimit(4)
                    .padding(Tokens.Space.s8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(Color.primary.opacity(0.06)))
            }
            CardFactsGrid(facts: card.facts) {
                if let pullRequest = card.pullRequest {
                    GridRow(alignment: .firstTextBaseline) {
                        Text(Copy.chatPeekPullRequest()).foregroundStyle(.secondary)
                        HStack(spacing: Tokens.Space.s8) {
                            SessionPullRequestChip(pr: pullRequest)
                            if let diff = card.diff { DiffText(diff: diff) }
                        }
                    }
                } else if let diff = card.diff {
                    GridRow(alignment: .firstTextBaseline) {
                        Text(Copy.chatPeekChanges()).foregroundStyle(.secondary)
                        DiffText(diff: diff)
                    }
                }
                if card.background.isEmpty == false {
                    GridRow(alignment: .firstTextBaseline) {
                        Text(Copy.chatPeekWaitingOn()).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                            ForEach(card.background.prefix(Self.tasksShown), id: \.id) { task in
                                HStack(spacing: Tokens.Space.s6) {
                                    Circle().fill(Color.backgroundWork).frame(width: 6, height: 6).accessibilityHidden(true)
                                    Text(task.name).scaledFont(10.5, design: .monospaced).lineLimit(1).truncationMode(.tail)
                                }
                            }
                            if card.background.count > Self.tasksShown {
                                Text(Copy.chatPeekMoreTasks(count: card.background.count - Self.tasksShown)).scaledFont(11).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            Text(card.timeline).scaledFont(11.5).foregroundStyle(.tertiary)
        }
        .padding(Tokens.Space.s14)
        .frame(width: 320, alignment: .leading)
    }
}
