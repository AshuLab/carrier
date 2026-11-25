import CarrierCore
import SwiftUI

// The pieces of the Agents page that are not rows of a form: the card at the top of the first screen, the rail of roles under it, and the top of a
// role's screen (its picture and where it sits in an epic). AgentsTab.swift puts them together.

/// The avatar of a role as the page draws it everywhere: the bot's picture (by `appIds` of the registry) and the mark of the account it runs on.
func roleAvatar(_ row: RoleRow, page: AgentsPage, icons: [String: String], size: CGFloat) -> RoleAvatar {
    var appId: String?
    if case .forge(let bot) = row.identity { appId = page.bots.appIds[bot] }
    return RoleAvatar(
        identity: row.identity, appId: appId, account: row.fields.provider,
        icon: row.fields.provider.flatMap { icons[$0] }, size: size, off: row.off && row.drafting == false
    )
}

/// The card at the top of the first screen: whether the roles of an epic are set up, and what is in the way, with a button to the role to fix.
struct AgentsStatusCard: View {
    let readiness: AgentsReadiness
    let open: (AgentRole) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s14) {
            Glyph(readiness.tone == .ready ? .check : .exclamation, size: 18, bold: true).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(readiness.tone == .ready ? Color.green : Color.orange)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(readiness.title).font(.scaled(15).weight(.bold))
                ForEach(readiness.notes, id: \.self) { note in
                    Text(note).font(.scaled(12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let fix = readiness.fix {
                    Button { open(fix) } label: { Label("Open \(fix.title)", icon: .arrowRight).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).padding(.top, Tokens.Space.s4)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, Tokens.Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// The three roles in the order an epic goes through them, joined by a rail that says what passes from one to the next: the author opens the pull
/// request, the reviewer asks for changes and the author answers until the review passes, and then the lead reviewer. One row of the form with the
/// rail drawn through it (separate rows would break the line at every edge). Each role is a button that opens its screen.
struct EpicRail: View {
    let page: AgentsPage
    let readiness: AgentsReadiness
    let icons: [String: String]
    /// On a repo's screen: the roles the repo has its own settings for; every row then says whether it is one of them or follows Agents. nil on Agents itself.
    var own: Set<AgentRole>?
    let open: (AgentRole) -> Void

    /// The title of the group the rows are in, which the search finds them by.
    static let group = "How an epic runs"
    static let groupID = "how-an-epic-runs"

    var body: some View {
        VStack(spacing: Tokens.Space.none) {
            ForEach(Array(page.rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 { link(into: row) }
                RoleRailRow(
                    row: row, needsAttention: readiness.problems.contains { $0.role == row.role }, own: own.map { $0.contains(row.role) },
                    avatar: roleAvatar(row, page: page, icons: icons, size: 38), action: { open(row.role) }
                )
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
    }

    /// What passes on to `next`: the line is dashed while the Lead reviewer is off.
    @ViewBuilder private func link(into next: RoleRow) -> some View {
        if next.role == .reviewer {
            RailLink(dashed: false) {
                FlowLayout(spacing: Tokens.Space.s8) {
                    Text("Opens the pull request")
                    StatusChip(text: "\u{21BA} asks for changes, the author answers", tint: .secondary)
                }
            }
        } else {
            RailLink(dashed: next.off) { Text(next.off ? "Lead reviewer is off" : "When the review passes") }
        }
    }
}

private struct RoleRailRow: View {
    let row: RoleRow
    let needsAttention: Bool
    /// Whether the repo has settings of its own for the role (a repo's screen), nil on Agents.
    var own: Bool?
    let avatar: RoleAvatar
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s12) {
                avatar
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(row.title).fontWeight(.medium)
                    Text(row.what).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                trailing
                if let own { StatusChip(text: own ? "Own" : "Same as everywhere", tint: own ? Color.themeAccent : .secondary) }
                Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Tokens.Space.s8).frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.tile, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .settingsAnchored(row.role.rawValue, group: EpicRail.groupID)
    }

    @ViewBuilder private var trailing: some View {
        if row.off {
            StatusChip(text: "Off", tint: .secondary)
        } else if needsAttention {
            StatusChip(text: "Needs attention", tint: .orange)
        } else {
            let model = [row.fields.model, row.fields.effort].compactMap { $0 }.filter { $0.isEmpty == false }.joined(separator: " \u{00b7} ")
            VStack(alignment: .trailing, spacing: Tokens.Space.s1) {
                Text(model.isEmpty ? "No model" : model).font(.scaled(12)).foregroundStyle(model.isEmpty ? .secondary : .primary)
                Text(row.fields.profile ?? "No identity").font(.scaled(12)).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 250, alignment: .trailing)
        }
    }
}

/// The stretch of the rail between two roles: a line through the middle of a column as wide as the avatars, and under it what goes on.
private struct RailLink<Caption: View>: View {
    let dashed: Bool
    @ViewBuilder let caption: Caption

    var body: some View {
        HStack(spacing: Tokens.Space.s12) {
            // the line goes 8 points past the link on each side, to reach the avatars the rows leave that much room around
            RailLine().stroke(.tertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 4] : []))
                .frame(width: 38).padding(.vertical, -8)
            caption.font(.scaled(11.5)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.Space.s8).frame(minHeight: 34)
    }
}

private struct RailLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

/// The top of a role's screen: its picture and who it works as, and under them the three roles of an epic in order with this one marked; the others
/// are links, so a person goes from one to the next without going back.
struct RoleHero: View {
    let row: RoleRow
    let page: AgentsPage
    let icons: [String: String]
    private let store = ForgeAvatarStore.shared

    var body: some View {
        HStack(spacing: Tokens.Space.s16) {
            roleAvatar(row, page: page, icons: icons, size: 64)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(name).font(.scaled(16).weight(.bold)).lineLimit(1).truncationMode(.middle)
                Text(row.headline).font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                source
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, Tokens.Space.s6)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        switch row.identity {
        case .forge(let bot): bot
        case .gh: "Your gh login"
        case .missing: row.fields.profile ?? "Unknown identity"
        case .unset: "No identity yet"
        }
    }

    @ViewBuilder private var source: some View {
        switch row.identity {
        case .forge(let bot):
            StatusChip(text: store.image(for: page.bots.appIds[bot]) == nil ? "Initials" : "Picture from the bot\u{2019}s GitHub App", tint: .secondary)
        case .gh: StatusChip(text: "Your own account", tint: .secondary)
        case .missing: StatusChip(text: "Not in Agent Forge", tint: .orange)
        case .unset: EmptyView()
        }
    }
}

/// Where the role sits among the three, in a row of the form under `RoleHero`.
struct RoleFlowStrip: View {
    let current: AgentRole
    let rows: [RoleRow]
    let open: (AgentRole) -> Void

    var body: some View {
        FlowLayout(spacing: Tokens.Space.s8) {
            Text("In an epic").font(.scaled(11.5)).foregroundStyle(.secondary)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Glyph(index == 1 ? .exchange : .arrowRight, size: 11).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                if row.role == current {
                    Text(row.title).font(.scaled(12, weight: .medium)).padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s2)
                        .background(Capsule().fill(Color.themeAccent.opacity(0.18))).overlay(Capsule().strokeBorder(Color.themeAccent, lineWidth: 1.5))
                        .accessibilityAddTraits(.isSelected)
                } else {
                    // a role that is off says so in words, not only in a lighter button
                    Button { open(row.role) } label: { Text(row.off ? "\(row.title) \u{00b7} Off" : row.title) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
        }
        .frame(minHeight: 28)
    }
}
