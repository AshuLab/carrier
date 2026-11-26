import AppKit
import CarrierCore
import CarrierUI
import QuartzCore
import SwiftUI

/// A session in the sidebar: the project as an icon (its initials on a colour of its own, in a rounded square) that carries the state,
/// the title and under it where it works, and on the right the age of its last activity over the providers it has used. The two
/// lines on each side have the same height, so the age sits on the title's line and the providers on the second one.
struct SessionRowView: View {
    private let timeChanges = TimeFormatChanges()
    let row: SessionRow
    /// Outside the workspace order the group is not the workspace, so the second line says it.
    let showsWorkspace: Bool
    /// Pin and Archive take the age's place while the pointer is on the row. Only the sessions list asks for them: the Archive section draws
    /// this row inside a button, and Settings draws it as a preview.
    var hoverActions = false
    /// The sidebar's list gives its rows room around their lines and the third one, with the pull request; the Archive section keeps them compact.
    var roomy = false
    @State private var hovered = false
    @Environment(SessionActions.self) private var actions
    private let titles = TitleRegeneration.shared
    @AppStorage(Preference.sidebarPinned) private var pinnedStored
    @AppStorage(Preference.sidebarRowIcon) private var showsIcon
    @AppStorage(Preference.sidebarRowBranch) private var showsBranch
    @AppStorage(Preference.sidebarRowPullRequest) private var showsPullRequest
    @AppStorage(Preference.sidebarRowDiff) private var showsDiff
    @AppStorage(Preference.sidebarRowProviders) private var showsProviders
    @AppStorage(Preference.sidebarRowAge) private var showsAge
    @AppStorage(Preference.appearanceDensity) private var density
    private static let titleLine: CGFloat = 17, detailLine: CGFloat = 15, metaLine: CGFloat = 17
    /// Two buttons of 22 points and the gap between them.
    private static let actionsWidth: CGFloat = 46
    /// The orange of "Waiting for you" as text: the system's on dark, a deeper one on light, where the system's is too pale to read.
    static let attention = Color(Tokens.Status.attention)
    /// Whether the ring stays on after the agent stops, to go round once more in green when the turn ended unread (`finished`).
    @State private var ringKept = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale

    private var content: SessionRowContent {
        SessionRowContent(
            row, showsWorkspace: showsWorkspace,
            parts: SessionRowParts(icon: showsIcon, branch: showsBranch, providers: showsProviders, age: showsAge, pullRequest: showsPullRequest, diff: showsDiff), now: Date()
        )
    }

    private var pinned: Bool { pinnedIds(pinnedStored).contains(row.id) }

    private func togglePin() {
        let ids = pinnedIds(pinnedStored)
        pinnedStored = storedPins(pinned ? ids.subtracting([row.id]) : ids.union([row.id]))
    }

    /// What the host refuses (a session that is working) is told in an alert, as the context menu does.
    private func archive() {
        Task { if let refusal = await actions.archive(row.id) { tell(refusal) } }
    }

    private func place(_ place: SessionPlace) -> Text {
        switch place {
        case .branch(let name): Text("\(Image(inline: .gitBranch)) \(Text(name).font(textScale.font(11, design: .monospaced)))")
        case .baseFolder: Text("\(Image(inline: .folder)) \(Copy.sessionBaseFolder())")
        }
    }

    /// While the session waits for the person, the word takes the place of the time at the top right (`SessionTimeLabel`); with the time
    /// switched off it is the second line's, where it has always been.
    private func waitsAtTop(_ content: SessionRowContent) -> Bool { row.state == .waiting && content.age != nil }

    /// The same for "Done" (the turn ended and the session has not been opened since): the word takes the place of the time.
    private func doneAtTop(_ content: SessionRowContent) -> Bool { row.status == .unread && content.age != nil }

    @ViewBuilder private func detail(_ content: SessionRowContent) -> some View {
        if row.state == .waiting && waitsAtTop(content) == false {
            Text(Copy.sessionStatusNeedsYou()).fontWeight(.medium).foregroundStyle(Self.attention)
        } else if row.status == .unread && doneAtTop(content) == false {
            Text(Copy.sessionDone()).fontWeight(.medium).foregroundStyle(Color.sessionDone)
        } else {
            switch (content.workspace, content.place) {
            case (let workspace?, let placed?): Text("\(workspace) · \(place(placed))").foregroundStyle(.secondary)
            case (let workspace?, nil): Text(workspace).foregroundStyle(.secondary)
            case (nil, let placed?): place(placed).foregroundStyle(.secondary)
            case (nil, nil): Text("")
            }
        }
    }

    /// The time at the top right (`SessionTimeLabel`).
    private func ageOrStopwatch(_ content: SessionRowContent) -> some View { SessionTimeLabel(row: row, age: content.age) }

    /// The age, or the two buttons while the pointer is on the row. The age stays in the layout, hidden, so the column does not change its width as they come in.
    private func ageSlot(_ content: SessionRowContent) -> some View {
        ZStack(alignment: .trailing) {
            ageOrStopwatch(content).opacity(hoverActions && hovered ? 0 : 1)
            if hoverActions && hovered {
                HStack(spacing: Tokens.Space.s2) {
                    hoverButton(pinned ? .pinOff : .pin, pinned ? Copy.sessionUnpin() : Copy.sessionPin(), togglePin)
                    hoverButton(.archive, Copy.sessionArchive(), why: archiveBlock(row), archive)
                }
                .transition(.opacity)
            }
        }
        .sidebarFont(.detail).monospacedDigit().lineLimit(1).frame(height: Self.titleLine)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
        // room for the two buttons even while they are hidden, so the title does not move as the pointer comes in
        .frame(minWidth: hoverActions ? Self.actionsWidth : nil, alignment: .trailing)
    }

    var body: some View {
        let content = content
        // the third line, with the pull request and the lines changed, only where the list has room for it and the session has either
        let third = roomy && content.hasThirdLine
        HStack(alignment: .top, spacing: SidebarMetrics.inset) {
            if content.showsIcon {
                ProjectIcon(
                    base: row.base, name: row.workspace, colorKey: projectColorKey(row.base), working: row.isWorking, background: row.isWorking && row.state != .working,
                    finished: ringKept && !row.isWorking
                )
            }
            VStack(alignment: .leading, spacing: roomy ? density.sessionLineGap : SidebarMetrics.lineGap) {
                HStack(spacing: Tokens.Space.s4) {
                    RollingTitle(text: titles.title(of: row), waiting: titles.waiting.contains(row.id))
                        .sidebarFont(.item).fontWeight(row.state == .waiting ? .medium : .regular)
                    Spacer(minLength: 4)
                    ageSlot(content)
                }
                .frame(height: Self.titleLine)
                HStack(spacing: Tokens.Space.s4) {
                    detail(content).sidebarFont(.detail).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 4)
                    // with no third line the providers sit here; with one they go down to it
                    if third == false { ProviderMarks(names: content.providers) }
                }
                .frame(height: Self.detailLine)
                if third {
                    HStack(spacing: Tokens.Space.s8) {
                        SessionWorkPill(pr: content.pullRequest, diff: content.diff)
                        Spacer(minLength: 4)
                        ProviderMarks(names: content.providers)
                    }
                    .frame(height: Self.metaLine)
                }
            }
        }
        .padding(.horizontal, content.showsIcon ? (roomy ? density.sessionRowPadding - Tokens.Space.s2 : density.rowPadding) : SidebarMetrics.inset).padding(.vertical, roomy ? density.sessionRowPadding : density.rowPadding)
        .onChange(of: row.isWorking, initial: true) { _, working in if working { ringKept = true } }
        .onChange(of: row.status) { old, new in
            guard old == .working, ringKept else { return }
            // a turn that ended unread gets one fast green lap; anything else (it waits for the person, or they are looking at it) drops the ring now
            guard new == .unread, reduceMotion == false else { ringKept = false; return }
            Task { try? await Task.sleep(for: .seconds(1.2)); ringKept = false }
        }
        .onHover { hovered = $0 }
        .sessionContextMenu(row, inWindow: hoverActions)
        .hoverCard { SessionPeekView(card: sessionPeek(row, now: Date())) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(content))
        // the buttons are drawn on hover only: VoiceOver reaches the same two here
        .accessibilityAction(named: pinned ? Copy.sessionUnpin() : Copy.sessionPin()) { if hoverActions { togglePin() } }
        .accessibilityAction(named: Copy.sessionArchive()) { if hoverActions && archiveBlock(row) == nil { archive() } }
    }

    /// `why` is what keeps the button off: it is the tooltip then, and what VoiceOver reads after the name.
    private func hoverButton(_ symbol: AppIcon, _ title: String, why: String? = nil, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Glyph(symbol, size: 11).foregroundStyle(.secondary).frame(width: 22, height: 20).contentShape(Rectangle())
        }
        .buttonStyle(HoverFillButtonStyle(radius: 5)).disabled(why != nil).help(why ?? title).accessibilityLabel(title).accessibilityHint(why ?? "")
    }

    /// What the row says aloud: the title, the state in words (the icon draws it), where it works, the providers and "5 minutes ago",
    /// the parts the person switched off left out.
    private func label(_ content: SessionRowContent) -> String {
        let state: String? = switch row.state {
        case .working: Copy.sessionStatusWorking()
        case .waiting: Copy.sessionNeedsAttention()
        case .idle, .done: row.background.isEmpty == false ? Copy.sessionWaitingBackground() : row.status == .unread ? Copy.sessionDone() : nil
        }
        let place: String? = switch content.place {
        case .branch(let name)?: name
        case .baseFolder?: Copy.sessionBaseFolder()
        case nil: nil
        }
        let age = content.age == nil ? nil : spokenAge(row.updatedAt, now: Date())
        let work: [String?] = roomy ? [content.pullRequest?.spoken(), content.diff.map { Copy.sessionDiffSpoken(added: $0.added, removed: String($0.removed)) }] : []
        return ([row.title, state, row.workspace, place] + work + content.providers + [age]).compactMap { $0 }.joined(separator: ", ")
    }
}

/// What a session's row says at the top right, in the place of its time: "Needs you" while it waits for a permission or an answer, "Done" and
/// beside it how long ago, once its turn ended and it was not opened since, how long the turn has run while it works or waits for what it started (a stopwatch that ticks
/// each second, in the colour of the ring), or else the age of its last activity. `age` is nil while the time is switched off: then none of it shows.
struct SessionTimeLabel: View {
    let row: SessionRow
    let age: String?

    var body: some View {
        if row.state == .waiting && age != nil {
            Text(Copy.sessionStatusNeedsYou()).fontWeight(.medium).foregroundStyle(SessionRowView.attention)
        } else if row.status == .unread, let age {
            // the word, and beside it how long ago it ended: the time it would have shown
            HStack(spacing: Tokens.Space.s4) {
                Text(Copy.sessionDone()).fontWeight(.medium).foregroundStyle(Color.sessionDone)
                Text(age).foregroundStyle(.tertiary)
            }
        } else if age != nil, let since = row.workingSince {
            TickingTimeline(every: 1) { context in
                Text(workingElapsed(Int(context.date.timeIntervalSince(since)))).foregroundStyle(row.state == .working ? Color.thought : Color.backgroundWork)
            }
        } else {
            Text(age ?? "").foregroundStyle(.tertiary)
        }
    }
}

/// The providers a session has worked with, as their marks (three at most, then "+n"): the provider's letter where there is no mark.
struct ProviderMarks: View {
    let names: [String]
    private static let shown = 3

    var body: some View {
        HStack(spacing: Tokens.Space.s3) {
            ForEach(names.prefix(Self.shown), id: \.self) { name in
                AccountMark(account: name, size: 12).help(ProviderIdentityStore.shared.shortName(of: name))
            }
            if names.count > Self.shown { Text("+\(names.count - Self.shown)").scaledFont(10, weight: .semibold) }
        }
        .foregroundStyle(.secondary)
    }
}
