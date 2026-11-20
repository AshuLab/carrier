import CarrierCore
import SwiftUI

/// The branch a new worktree starts from, as a sheet: a search, the Remote and Local tabs (one list at a time) and Fetch now with when it
/// last did. Choosing a row sets the branch and the side of it the worktree is cut from, and closes the sheet. A repository that is not on
/// this Mac yet has no tabs: its branches are one list in two sections. `browsing` is the same sheet for a session that works in the folder
/// itself: the pick is the branch the folder is switched to when the message is sent (docs/adr/0018).
struct BranchSheet: View {
    @Bindable var model: NewSessionModel
    var browsing = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searching: Bool

    /// Remote branches older than this are likely missing newer ones, and the sheet says so.
    private let staleAfter: TimeInterval = 7 * 86_400

    var body: some View {
        let picker = model.picker(query: query)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                header
                TextField("Search branches", text: $query)
                    .textFieldStyle(.roundedBorder).controlSize(.large).autocorrectionDisabled().focused($searching)
            }
            .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 16)
            if tabbed { tabs(picker).padding(.bottom, 12) }
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
            options: WorktreeStart.allCases.map { (value: $0, title: "\($0.tabTitle) \(picker?.rows($0).count ?? 0)", icon: $0.icon) }, selection: tab
        )
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Glyph(.gitBranch, size: 16).foregroundStyle(Color.themeAccent)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.themeAccent.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(browsing ? "Branches in \(model.folder.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "this folder")" : "Start from a branch").font(.title3.weight(.semibold))
                Text(browsing ? "The folder is switched to the branch you pick when the message is sent." : "The new worktree is cut from the branch you pick.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func list(_ picker: BranchPicker?) -> some View {
        let local = picker?.local ?? []
        let remote = picker?.remote ?? []
        if tabbed {
            tabList(picker?.rows(model.startTab) ?? [], tab: model.startTab, otherHas: (picker?.rows(model.startTab == .remote ? .local : .remote) ?? []).isEmpty == false)
        } else if local.isEmpty && remote.isEmpty {
            VStack(spacing: 8) {
                Glyph(query.isEmpty ? .gitBranch : .search, size: 32).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(query.isEmpty ? "No branches" : "No branch matches “\(query)”").font(.headline)
                Text(query.isEmpty ? "This repository has no branch to start from yet." : "Search looks at the local and the remote branches. Fetch to see new ones.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    section("Local", .harddrive, local, empty: "No local branches.")
                    section("Remote", .cloud, remote, empty: "No remote branches yet. Fetch to look for them.")
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
        }
    }

    /// The list of the tab that is open: its branches, or why there are none. A search that matches nothing here says where else to look.
    @ViewBuilder private func tabList(_ rows: [BranchRow], tab: WorktreeStart, otherHas: Bool) -> some View {
        if rows.isEmpty {
            let other = tab == .remote ? WorktreeStart.local : .remote
            VStack(spacing: 8) {
                Glyph(query.isEmpty ? tab.icon : .search, size: 32).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(query.isEmpty ? "No \(tab.tabTitle.lowercased()) branches" : "No \(tab.tabTitle.lowercased()) branch matches “\(query)”").font(.headline)
                Text(
                    query.isEmpty ? (tab == .remote ? "Nothing on origin yet. Fetch to look for it." : "This repository has no local branch.")
                        : otherHas ? "The \(other.tabTitle) tab has matches." : "Search looks at the branches of this tab. Fetch to see new ones."
                )
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(rows, id: \.name) { row in branchRow(row, on: tab) }
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
        }
    }

    /// A section: its name and how many branches it holds, then the rows. With a search the section that matches nothing is left out; without
    /// one it says it is empty.
    @ViewBuilder private func section(_ title: String, _ icon: AppIcon, _ rows: [BranchRow], empty: String) -> some View {
        if rows.isEmpty == false || query.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label(title, icon: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(rows.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.15)))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.bottom, 4)
                if rows.isEmpty {
                    Text(empty).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 8)
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
            fill: chosen ? Color.themeAccent.opacity(0.18) : nil
        ) { hovering in
            rowContent(row, chosen: chosen, hovering: hovering, notOnOrigin: tab == .local && row.localOnly)
        }
    }

    private func rowContent(_ row: BranchRow, chosen: Bool, hovering: Bool, notOnOrigin: Bool = false) -> some View {
        let cut = row.name.lastIndex(of: "/").map { row.name.index(after: $0) } ?? row.name.startIndex
        return HStack(spacing: 10) {
            Glyph(.gitBranch).foregroundStyle(chosen ? Color.themeAccent : .secondary).frame(width: 18).accessibilityHidden(true)
            Text("\(Text(row.name[..<cut]).foregroundStyle(.secondary))\(Text(row.name[cut...]).fontWeight(chosen ? .semibold : .medium))")
                .lineLimit(1).truncationMode(.middle)
            if row.isDefault { Badge(text: "default", icon: .starFilled, tint: .themeAccent) }
            if row.checkedOut { Badge(text: browsing ? "current" : "checked out", icon: .checkCircle, tint: browsing ? .themeAccent : .secondary) }
            if notOnOrigin { Badge(text: "not on origin", icon: .cloud, tint: .secondary) }
            Spacer(minLength: 8)
            if chosen { Glyph(.check, label: "Chosen").foregroundStyle(Color.themeAccent) }
            else { RowHint(text: "Select", shown: hovering) }
        }
        .frame(minHeight: 20).padding(.horizontal, 10).padding(.vertical, 8)
    }

    /// What the choice does: the new branch and the one it is cut from, or the branch the folder will be switched to.
    @ViewBuilder private var summary: some View {
        if browsing {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Glyph(.info).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Picking another branch switches this folder to it when the message is sent, unless it has uncommitted changes. To keep the folder as it is, start a new worktree from it.")
                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            .padding(.horizontal, 16).padding(.bottom, 16)
        } else {
            newBranch
        }
    }

    private var newBranch: some View {
        HStack(spacing: 8) {
            Glyph(.circlePlus).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("New branch").font(.subheadline).foregroundStyle(.secondary)
            Text(model.worktreeName.isEmpty ? "\(worktreeBranchPrefix)<generated when sent>" : "\(worktreeBranchPrefix)\(model.worktreeName)").font(.subheadline.monospaced()).lineLimit(1).truncationMode(.middle)
            Glyph(.arrowLeft, size: 11, label: "from").foregroundStyle(.secondary)
            Text(model.startPoint?.ref ?? "…").font(.subheadline.monospaced().weight(.semibold)).foregroundStyle(model.startPoint?.side?.tint ?? .primary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    @ViewBuilder private func footer(_ picker: BranchPicker?) -> some View {
        if model.toClone {
            HStack(spacing: 10) {
                Glyph(.cloud).foregroundStyle(.secondary).accessibilityHidden(true)
                Text("Branches as GitHub lists them now. The repository is cloned when the message is sent.").font(.subheadline)
                Spacer(minLength: 16)
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        } else {
            fetchFooter(picker)
        }
    }

    private func fetchFooter(_ picker: BranchPicker?) -> some View {
        let at = model.workspace?.fetchedAt
        let stale = at.map { Date().timeIntervalSince1970 - Double($0) / 1000 > staleAfter } ?? true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Glyph(stale ? .warningFilled : .history)
                    .foregroundStyle(stale ? Color.orange : .secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(picker?.fetched ?? "").font(.subheadline)
                    if stale { Text("The remote branches may be out of date.").font(.subheadline).foregroundStyle(.orange) }
                }
                Button { Task { await model.fetchNow() } } label: {
                    Label { Text(model.fetching ? "Fetching…" : "Fetch now") } icon: {
                        // turns for as long as the fetch takes
                        Glyph(.refresh).glyphSpinning(model.fetching)
                    }
                }
                    .controlSize(.small).disabled(model.fetching).help("Ask the remote for its latest branches")
                Spacer(minLength: 16)
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryCapsuleButtonStyle()).keyboardShortcut(.cancelAction)
            }
            if let problem = model.fetchProblem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Glyph(.warningFilled).foregroundStyle(.red).accessibilityHidden(true)
                    Text(problem).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .font(.subheadline).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

extension WorktreeStart {
    /// The side's mark in the picker's tabs, the "from" chip and the summary.
    var icon: AppIcon { self == .remote ? .cloud : .harddrive }
    /// The colour of the side wherever a start is named: the chip, the summary and the send steps' ref.
    var tint: Color { self == .remote ? .teal : .indigo }
}
