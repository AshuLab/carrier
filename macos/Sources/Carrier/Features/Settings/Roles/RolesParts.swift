import CarrierCore
import CarrierUI
import SwiftUI

// The pieces of the Roles page that are not rows of a form: the card at the top of the first screen, the rail of roles under it, and the top of a
// role's screen (its picture and where it sits in an epic). RolesTab.swift puts them together.

/// The avatar of a role as the page draws it everywhere: the bot's picture (by `appIds` of the registry) and the mark of the account it runs on.
func roleAvatar(_ row: RoleRow, page: RolesPage, icons: [String: String], size: CGFloat) -> RoleAvatar {
    var appId: String?
    if case .forge(let bot) = row.identity { appId = page.bots.appIds[bot] }
    return RoleAvatar(
        identity: row.identity, appId: appId, account: row.fields.provider,
        icon: row.fields.provider.flatMap { icons[$0] }, size: size, off: row.off && row.drafting == false
    )
}

/// The card at the top of the first screen: whether the roles of an epic are set up, and what is in the way, with a button to the role to fix.
struct RolesStatusCard: View {
    let readiness: RolesReadiness
    let open: (RoleSlot) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Tokens.Space.s14) {
            Glyph(readiness.tone == .ready ? .check : .exclamation, size: 18, bold: true).foregroundStyle(.white)
                .frame(width: 34, height: 34).background(Circle().fill(readiness.tone == .ready ? Color.green : Color.orange)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                Text(readiness.title).scaledFont(15, weight: .bold)
                ForEach(readiness.notes, id: \.self) { note in
                    Text(note).scaledFont(12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let fix = readiness.problems.first {
                    Button { open(fix.role) } label: { Label(Copy.rolesOpenRole(role: fix.title), icon: .arrowRight).labelStyle(.titleAndIcon) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).padding(.top, Tokens.Space.s4)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, Tokens.Space.s4).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

/// The roles in the order an epic goes through them, joined by a rail that says what passes from one to the next: the author opens the pull
/// request, the reviewers (the Reviewer and the extra ones, one step in parallel when there are extras) ask for changes and the author answers until the review passes, and then the lead reviewer. One row of the form with the
/// rail drawn through it (separate rows would break the line at every edge). Each role is a button that opens its screen.
struct EpicRail: View {
    let page: RolesPage
    let readiness: RolesReadiness
    let icons: [String: String]
    /// On a repo's screen: the roles the repo has its own settings for; every row then says whether it is one of them or follows Roles. nil on Roles itself.
    var own: Set<RoleSlot>?
    let open: (RoleSlot) -> Void

    /// The title of the group the rows are in, which the search finds them by.
    static var group: String { Copy.rolesRailGroup() }
    static let groupID = "how-an-epic-runs"

    var body: some View {
        VStack(spacing: Tokens.Space.none) {
            // the extra reviewers are drawn with the Reviewer, in one step, and not at their place in the list
            ForEach(Array(page.rows.filter { $0.slot.isExtra == false }.enumerated()), id: \.element.id) { index, row in
                if index > 0 { link(into: row) }
                if row.slot == .reviewer {
                    reviewersStep
                } else {
                    railRow(row)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
    }

    private func railRow(_ row: RoleRow) -> some View {
        RoleRailRow(
            row: row, needsAttention: readiness.problems.contains { $0.role == row.slot }, own: own.map { $0.contains(row.slot) },
            avatar: roleAvatar(row, page: page, icons: icons, size: 38), action: { open(row.slot) }
        )
    }

    /// The Reviewer alone, or with the extra reviewers as one step in parallel.
    @ViewBuilder private var reviewersStep: some View {
        let reviewers = page.rows.filter { $0.slot == .reviewer || $0.slot.isExtra }
        if reviewers.count > 1 {
            ParallelStep(caption: Copy.rolesRailParallel()) {
                ForEach(reviewers) { railRow($0) }
            }
        } else {
            ForEach(reviewers) { railRow($0) }
        }
    }

    /// What passes on to `next`: the line is dashed while the Lead reviewer is off.
    @ViewBuilder private func link(into next: RoleRow) -> some View {
        if next.slot == .reviewer {
            RailLink(dashed: false) {
                FlowLayout(spacing: Tokens.Space.s8) {
                    Text(Copy.rolesRailOpens())
                    StatusChip(text: Copy.rolesRailAsks(), tint: .secondary)
                }
            }
        } else {
            RailLink(dashed: next.off) { Text(next.off ? Copy.rolesRailLeadOff() : Copy.rolesRailPasses(rounds: page.leadRounds)) }
        }
    }
}

private struct RoleRailRow: View {
    @Environment(\.pieceTheme) private var theme
    let row: RoleRow
    let needsAttention: Bool
    /// Whether the repo has settings of its own for the role (a repo's screen), nil on Roles.
    var own: Bool?
    let avatar: RoleAvatar
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Tokens.Space.s12) {
                avatar
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(row.title()).fontWeight(.medium)
                    Text(row.what).scaledFont(11).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                trailing
                if let own { StatusChip(text: own ? Copy.rolesOwn() : Copy.rolesSameAsEverywhere(), tint: own ? theme.accent : .secondary) }
                Glyph(.chevronRight, size: 13, bold: true).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Tokens.Space.s8).frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: Tokens.Radius.tile, style: .continuous).fill(Color.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .settingsAnchored(row.id, group: EpicRail.groupID)
    }

    @ViewBuilder private var trailing: some View {
        if row.off {
            StatusChip(text: Copy.rolesOff(), tint: .secondary)
        } else if needsAttention {
            StatusChip(text: Copy.rolesNeedsAttention(), tint: .orange)
        } else {
            let model = [row.fields.model, row.fields.effort].compactMap { $0 }.filter { $0.isEmpty == false }.joined(separator: " \u{00b7} ")
            VStack(alignment: .trailing, spacing: Tokens.Space.s1) {
                Text(model.isEmpty ? Copy.rolesNoModel() : model).scaledFont(12).foregroundStyle(model.isEmpty ? .secondary : .primary)
                Text(row.fields.profile ?? Copy.rolesNoIdentity()).scaledFont(12).foregroundStyle(.secondary)
            }
            .lineLimit(1).truncationMode(.middle).frame(maxWidth: 250, alignment: .trailing)
        }
    }
}

/// The stretch of the rail between two roles: a line through the middle of a column as wide as the avatars, and under it what goes on.
/// Roles that run at the same time: a tinted box around their rows, under a line that says so.
private struct ParallelStep<Content: View>: View {
    @Environment(\.pieceTheme) private var theme
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            Text(caption).scaledFont(11.5, weight: .medium).foregroundStyle(theme.accent)
                .padding(.horizontal, Tokens.Space.s8).padding(.top, Tokens.Space.s8).padding(.bottom, Tokens.Space.s2)
            content
        }
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.tile, style: .continuous).fill(theme.accent.opacity(0.07)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(caption)
    }
}

private struct RailLink<Caption: View>: View {
    let dashed: Bool
    @ViewBuilder let caption: Caption

    var body: some View {
        HStack(spacing: Tokens.Space.s12) {
            // the line goes 8 points past the link on each side, to reach the avatars the rows leave that much room around
            RailLine().stroke(.tertiary, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [3, 4] : []))
                .frame(width: 38).padding(.vertical, -Tokens.Space.s8)
            caption.scaledFont(11.5).foregroundStyle(.secondary)
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
    let page: RolesPage
    let icons: [String: String]
    private let store = ForgeAvatarStore.shared

    var body: some View {
        HStack(spacing: Tokens.Space.s16) {
            roleAvatar(row, page: page, icons: icons, size: 64)
            VStack(alignment: .leading, spacing: Tokens.Space.s3) {
                Text(name).scaledFont(16, weight: .bold).lineLimit(1).truncationMode(.middle)
                Text(row.headline()).scaledFont(12).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: Tokens.Space.s6) {
                    source
                    if let type = row.type { StatusChip(text: Copy.rolesExtraType(type: type), tint: .secondary) }
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.vertical, Tokens.Space.s6)
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        switch row.identity {
        case .forge(let bot): bot
        case .gh: Copy.rolesIdentityGh()
        case .missing: row.fields.profile ?? Copy.rolesUnknownIdentity()
        case .unset: Copy.rolesNoIdentityYet()
        }
    }

    @ViewBuilder private var source: some View {
        switch row.identity {
        case .forge(let bot):
            StatusChip(text: store.image(for: page.bots.appIds[bot]) == nil ? Copy.rolesInitials() : Copy.rolesPicture(), tint: .secondary)
        case .gh: StatusChip(text: Copy.rolesOwnAccount(), tint: .secondary)
        case .missing: StatusChip(text: Copy.rolesNotInForge(), tint: .orange)
        case .unset: EmptyView()
        }
    }
}

/// Where the role sits among the roles of an epic, in a row of the form under `RoleHero`: every other role is a link.
struct RoleFlowStrip: View {
    let current: RoleSlot
    let rows: [RoleRow]
    let open: (RoleSlot) -> Void

    var body: some View {
        FlowLayout(spacing: Tokens.Space.s8) {
            Text(Copy.rolesInAnEpic()).scaledFont(11.5).foregroundStyle(.secondary)
            ForEach(rows) { row in
                // the Author and the reviewers go back and forth; the reviewers are side by side and then it goes on to the lead
                if row.slot == .reviewer {
                    Glyph(.exchange, size: 11).foregroundStyle(.tertiary).accessibilityHidden(true)
                } else if row.slot == .lead {
                    Glyph(.arrowRight, size: 11).foregroundStyle(.tertiary).accessibilityHidden(true)
                }
                if row.slot == current {
                    Text(row.title()).scaledFont(12, weight: .medium).padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s2)
                        .background(Capsule().fill(.tint.opacity(0.18))).overlay(Capsule().strokeBorder(.tint, lineWidth: 1.5))
                        .accessibilityAddTraits(.isSelected)
                } else {
                    // a role that is off says so in words, not only in a lighter button
                    Button { open(row.slot) } label: { Text(row.off ? Copy.rolesRoleOff(role: row.title()) : row.title()) }
                        .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                }
            }
        }
        .frame(minHeight: 28)
    }
}
