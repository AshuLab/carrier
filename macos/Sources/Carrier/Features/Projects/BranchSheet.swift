import CarrierCore
import SwiftUI

/// The branch a new worktree starts from, as a sheet: a search, the Remote and Local tabs (one list at a time) and Fetch now with when it
/// last did. Choosing a row sets the branch and the side of it the worktree is cut from, and closes the sheet. A repository that is not on
/// this Mac yet has no tabs: its branches are one list in two sections. `browsing` is the same sheet for a session that works in the folder
/// itself: the pick is the branch the folder is switched to when the message is sent (docs/adr/0018).
struct BranchSheet: View {
    @Environment(\.pieceTheme) private var theme
    @Bindable var model: NewSessionModel
    var browsing = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searching: Bool

    /// Remote branches older than this are likely missing newer ones, and the sheet says so.
    private let staleAfter: TimeInterval = 7 * 86_400

    var body: some View {
        let picker = model.picker(query: query)
        VStack(spacing: Tokens.Space.none) {
            VStack(alignment: .leading, spacing: Tokens.Space.s16) {
                header
                TextField(Copy.newSessionBranchSearch(), text: $query)
                    .textFieldStyle(.roundedBorder).controlSize(.large).autocorrectionDisabled().focused($searching)
            }
            .padding(.horizontal, Tokens.Space.s24).padding(.top, Tokens.Space.s24).padding(.bottom, Tokens.Space.s16)
            if tabbed { tabs(picker).padding(.bottom, Tokens.Space.s12) }
            Divider()
            list(picker)
            summary
            Divider()
            footer(picker)
        }
        .frame(width: 600, height: 600)
        .onAppear { searching = true }
    }

    /// The worktree's picker of a repository that is on this Mac has the two tabs; the folder's sheet and a repository to clone do not.
    private var tabbed: Bool { browsing == false && model.hasStartTabs }

    private func tabs(_ picker: BranchPicker?) -> some View {
        let tab = Binding(get: { model.startTab }, set: { model.choose(startTab: $0) })
        return SegmentedChoice(
            options: WorktreeStart.allCases.map { (value: $0, title: "\($0.tabTitle()) \(picker?.rows($0).count ?? 0)", icon: $0.icon) }, selection: tab
        )
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: Tokens.Space.s12) {
            Glyph(.gitBranch, size: 16).foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(.tint.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Text(browsing ? Copy.newSessionBranchesIn(folder: model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? Copy.newSessionThisFolder()) : Copy.newSessionStartFrom()).font(.title3.weight(.semibold))
                Text(browsing ? Copy.newSessionBrowseDetail() : Copy.newSessionStartDetail()).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func list(_ picker: BranchPicker?) -> some View {
        let local = picker?.local ?? []
        let remote = picker?.remote ?? []
        if tabbed {
            tabList(picker?.rows(model.startTab) ?? [], tab: model.startTab, otherHas: (picker?.rows(model.startTab == .remote ? .local : .remote) ?? []).isEmpty == false)
        } else if local.isEmpty && remote.isEmpty {
            VStack(spacing: Tokens.Space.s8) {
                Glyph(query.isEmpty ? .gitBranch : .search, size: 32).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(query.isEmpty ? Copy.newSessionNoBranches() : Copy.newSessionNoBranchMatches(query: query)).font(.headline)
                Text(query.isEmpty ? Copy.newSessionNoBranchYet() : Copy.newSessionSearchBoth())
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s24) {
                    section(WorktreeStart.local.tabTitle(), .harddrive, local, empty: Copy.newSessionNoLocal())
                    section(WorktreeStart.remote.tabTitle(), .cloud, remote, empty: Copy.newSessionNoRemote())
                }
                .padding(.horizontal, Tokens.Space.s16).padding(.vertical, Tokens.Space.s16)
            }
        }
    }

    /// The list of the tab that is open: its branches, or why there are none. A search that matches nothing here says where else to look.
    @ViewBuilder private func tabList(_ rows: [BranchRow], tab: WorktreeStart, otherHas: Bool) -> some View {
        if rows.isEmpty {
            let other = tab == .remote ? WorktreeStart.local : .remote
            VStack(spacing: Tokens.Space.s8) {
                Glyph(query.isEmpty ? tab.icon : .search, size: 32).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(tabEmptyTitle(tab)).font(.headline)
                Text(
                    query.isEmpty ? (tab == .remote ? Copy.newSessionNothingOnOrigin() : Copy.newSessionNoLocalBranch())
                        : otherHas ? Copy.newSessionOtherTabHas(tab: other.tabTitle()) : Copy.newSessionSearchTab()
                )
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s4) {
                    ForEach(rows, id: \.name) { row in branchRow(row, on: tab) }
                }
                .padding(.horizontal, Tokens.Space.s16).padding(.vertical, Tokens.Space.s16)
            }
        }
    }

    private func tabEmptyTitle(_ tab: WorktreeStart) -> String {
        switch (tab, query.isEmpty) {
        case (.remote, true): Copy.newSessionNoRemoteBranches()
        case (.local, true): Copy.newSessionNoLocalBranches()
        case (.remote, false): Copy.newSessionNoRemoteMatch(query: query)
        case (.local, false): Copy.newSessionNoLocalMatch(query: query)
        }
    }

    /// A section: its name and how many branches it holds, then the rows. With a search the section that matches nothing is left out; without
    /// one it says it is empty.
    @ViewBuilder private func section(_ title: String, _ icon: AppIcon, _ rows: [BranchRow], empty: String) -> some View {
        if rows.isEmpty == false || query.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                HStack(spacing: Tokens.Space.s8) {
                    Label(title, icon: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(rows.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, Tokens.Space.s6).padding(.vertical, Tokens.Space.s1).background(Capsule().fill(Color.secondary.opacity(0.15)))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, Tokens.Space.s10).padding(.bottom, Tokens.Space.s4)
                if rows.isEmpty {
                    Text(empty).font(.callout).foregroundStyle(.secondary).padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s8)
                }
                ForEach(rows, id: \.name) { row in branchRow(row, on: nil) }
            }
        }
    }

    /// The folder part of a name (`carrier/`, `origin/`, `feature/x/`) is quiet and the last part is the branch; a row is a button that picks it.
    /// `tab` is the tab the row is in, nil in a list with no tabs.
    @ViewBuilder private func branchRow(_ row: BranchRow, on tab: WorktreeStart?) -> some View {
        let chosen = tab.map { model.startPoint?.chooses(row, on: $0) ?? false } ?? (model.startBranch == row.name)
        HoverRow(
            action: {
                if let tab { model.choose(startBranch: row.name, on: tab) } else { model.choose(startBranch: row.name) }
                dismiss()
            },
            fill: chosen ? theme.accent.opacity(0.18) : nil
        ) { hovering in
            rowContent(row, chosen: chosen, hovering: hovering, notOnOrigin: tab == .local && row.localOnly, counted: tab == .local)
        }
    }

    /// `counted` is the Local tab: only there is a branch compared with its copy on `origin`.
    private func rowContent(_ row: BranchRow, chosen: Bool, hovering: Bool, notOnOrigin: Bool = false, counted: Bool = false) -> some View {
        let cut = row.name.lastIndex(of: "/").map { row.name.index(after: $0) } ?? row.name.startIndex
        return HStack(spacing: Tokens.Space.s10) {
            Glyph(.gitBranch).foregroundStyle(chosen ? theme.accent : .secondary).frame(width: 18).accessibilityHidden(true)
            Text("\(Text(row.name[..<cut]).foregroundStyle(.secondary))\(Text(row.name[cut...]).fontWeight(chosen ? .semibold : .medium))")
                .lineLimit(1).truncationMode(.middle)
            if row.isDefault { Badge(text: Copy.newSessionBadgeDefault(), icon: .starFilled, tint: theme.accent) }
            if row.checkedOut { Badge(text: browsing ? Copy.newSessionBadgeCurrent() : Copy.newSessionBadgeCheckedOut(), icon: .checkCircle, tint: browsing ? theme.accent : .secondary) }
            if notOnOrigin { Badge(text: Copy.newSessionBadgeNotOnOrigin(), icon: .cloud, tint: .secondary) }
            if counted, let behind = row.behindText() { Badge(text: behind, icon: .arrowDown, tint: .orange) }
            if counted, let notPushed = row.notPushedText() { Badge(text: notPushed, icon: .arrowUp, tint: .orange) }
            Spacer(minLength: 8)
            if chosen { Glyph(.check, label: Copy.newSessionChosen()).foregroundStyle(.tint) }
            else { RowHint(text: Copy.newSessionSelect(), shown: hovering) }
        }
        .frame(minHeight: 20).padding(.horizontal, Tokens.Space.s10).padding(.vertical, Tokens.Space.s8)
    }

    /// What the choice does: the new branch and the one it is cut from, or the branch the folder will be switched to.
    @ViewBuilder private var summary: some View {
        if browsing {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                Glyph(.info).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(Copy.newSessionBrowseSummary())
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Tokens.Space.s12).background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(Color.secondary.opacity(0.08)))
            .padding(.horizontal, Tokens.Space.s16).padding(.bottom, Tokens.Space.s16)
        } else {
            newBranch
        }
    }

    private var newBranch: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            newBranchLine
            if let warning = model.startWarning { ProblemLine(text: warning, size: 11) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Space.s12).background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(Color.secondary.opacity(0.08)))
        .padding(.horizontal, Tokens.Space.s16).padding(.bottom, Tokens.Space.s16)
    }

    private var newBranchLine: some View {
        HStack(spacing: Tokens.Space.s8) {
            Glyph(.circlePlus).foregroundStyle(.secondary).accessibilityHidden(true)
            Text(Copy.newSessionNewBranch()).font(.subheadline).foregroundStyle(.secondary)
            Text(model.worktreeName.isEmpty ? Copy.newSessionBranchGenerated(prefix: worktreeBranchPrefix) : "\(worktreeBranchPrefix)\(model.worktreeName)").font(.subheadline.monospaced()).lineLimit(1).truncationMode(.middle)
            Glyph(.arrowLeft, size: 11, label: Copy.newSessionFrom()).foregroundStyle(.secondary)
            Text(model.startPoint?.ref ?? "…").font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(model.startPoint?.side?.tint ?? .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private func footer(_ picker: BranchPicker?) -> some View {
        if model.toClone {
            HStack(spacing: Tokens.Space.s10) {
                Glyph(.cloud).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(Copy.newSessionBranchesFromGitHub()).font(.subheadline)
                Spacer(minLength: 16)
                Button(Copy.projectsCancel()) { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, Tokens.Space.s20).padding(.vertical, Tokens.Space.s12)
        } else {
            fetchFooter(picker)
        }
    }

    private func fetchFooter(_ picker: BranchPicker?) -> some View {
        let at = model.workspace?.fetchedAt
        let stale = at.map { Date().timeIntervalSince1970 - Double($0) / 1000 > staleAfter } ?? true
        return VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            HStack(spacing: Tokens.Space.s10) {
                Glyph(stale || picker?.unreachable != nil ? .warningFilled : .history)
                    .foregroundStyle(stale || picker?.unreachable != nil ? Color.orange : .secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                    Text(picker?.fetched ?? "").font(.subheadline)
                    // the fetch that choosing the project started could not reach origin: said here and nowhere else
                    if let unreachable = picker?.unreachable {
                        Text(unreachable).font(.subheadline).foregroundStyle(.orange)
                            .onAppear { AccessibilityNotification.Announcement(unreachable).post() }
                    } else if stale { Text(Copy.newSessionStale()).font(.subheadline).foregroundStyle(.orange) }
                }
                Button { Task { await model.fetchNow() } } label: {
                    Label { Text(model.fetching ? Copy.newSessionFetching() : Copy.newSessionFetchNow()) } icon: {
                        // turns for as long as the fetch takes
                        Glyph(.refresh).glyphSpinning(model.fetching)
                    }
                }
                    .controlSize(.small).disabled(model.fetching).help(Copy.newSessionFetchHelp())
                Spacer(minLength: 16)
                Button(Copy.projectsCancel()) { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if let problem = model.fetchProblem {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s8) {
                    Glyph(.warningFilled).foregroundStyle(.red).accessibilityHidden(true)
                    Text(problem).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .font(.subheadline).padding(Tokens.Space.s10).background(RoundedRectangle(cornerRadius: Tokens.Radius.control).fill(Color.red.opacity(0.12)))
            }
        }
        .padding(.horizontal, Tokens.Space.s20).padding(.vertical, Tokens.Space.s12)
    }
}

extension WorktreeStart {
    /// The side's mark in the picker's tabs, the "from" chip and the summary.
    var icon: AppIcon { self == .remote ? .cloud : .harddrive }
    /// The colour of the side wherever a start is named: the chip, the summary and the send steps' ref.
    var tint: Color { self == .remote ? .teal : .indigo }
}
