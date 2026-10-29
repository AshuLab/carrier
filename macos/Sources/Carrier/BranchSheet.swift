import CarrierCore
import SwiftUI

/// The branch a new worktree starts from, as a sheet: a search, the local and the remote branches in two sections, and Fetch now with
/// when it last did. Choosing a row sets `startBranch` and closes the sheet.
struct BranchSheet: View {
    @Bindable var model: NewSessionModel
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
            Divider()
            list(picker)
            summary
            Divider()
            footer(picker)
        }
        .frame(width: 600, height: 600)
        .onAppear { searching = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Start from a branch").font(.title3.weight(.semibold))
                Text("The new worktree is cut from the branch you pick.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func list(_ picker: BranchPicker?) -> some View {
        let local = picker?.local ?? []
        let remote = picker?.remote ?? []
        if local.isEmpty && remote.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: query.isEmpty ? "arrow.triangle.branch" : "magnifyingglass")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(query.isEmpty ? "No branches" : "No branch matches “\(query)”").font(.headline)
                Text(query.isEmpty ? "This repository has no branch to start from yet." : "Search looks at the local and the remote branches. Fetch to see new ones.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    section("Local", "internaldrive", local, empty: "No local branches.")
                    section("Remote", "cloud", remote, empty: "No remote branches yet. Fetch to look for them.")
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
        }
    }

    /// A section: its name and how many branches it holds, then the rows. With a search the section that matches nothing is left out; without
    /// one it says it is empty.
    @ViewBuilder private func section(_ title: String, _ icon: String, _ rows: [BranchRow], empty: String) -> some View {
        if rows.isEmpty == false || query.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text("\(rows.count)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.secondary.opacity(0.15)))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10).padding(.bottom, 4)
                if rows.isEmpty {
                    Text(empty).font(.callout).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.vertical, 8)
                }
                ForEach(rows, id: \.name) { row in branchRow(row) }
            }
        }
    }

    /// The folder part of a name (`carrier/`, `origin/`, `feature/x/`) is quiet and the last part is the branch.
    private func branchRow(_ row: BranchRow) -> some View {
        let chosen = model.startBranch == row.name
        let cut = row.name.lastIndex(of: "/").map { row.name.index(after: $0) } ?? row.name.startIndex
        return HoverRow(action: { model.choose(startBranch: row.name); dismiss() }, fill: chosen ? Color.accentColor.opacity(0.18) : nil) { hovering in
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(chosen ? Color.accentColor : .secondary).frame(width: 18).accessibilityHidden(true)
                Text("\(Text(row.name[..<cut]).foregroundStyle(.secondary))\(Text(row.name[cut...]).fontWeight(chosen ? .semibold : .medium))")
                    .lineLimit(1).truncationMode(.middle)
                if row.isDefault { Badge(text: "default", icon: "star.fill", tint: .accentColor) }
                if row.checkedOut { Badge(text: "checked out", icon: "checkmark.circle", tint: .secondary) }
                Spacer(minLength: 8)
                if chosen { Image(systemName: "checkmark").foregroundStyle(Color.accentColor).accessibilityLabel("Chosen") }
                else { RowHint(text: "Select", shown: hovering) }
            }
            .frame(minHeight: 20).padding(.horizontal, 10).padding(.vertical, 8)
        }
    }

    /// What the choice does: the new branch and the one it is cut from.
    private var summary: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.circle").foregroundStyle(.secondary).accessibilityHidden(true)
            Text("New branch").font(.subheadline).foregroundStyle(.secondary)
            Text("\(worktreeBranchPrefix)\(model.worktreeName)").font(.subheadline.monospaced()).lineLimit(1).truncationMode(.middle)
            Image(systemName: "arrow.left").font(.caption).foregroundStyle(.secondary).accessibilityLabel("from")
            Text(model.startBranch ?? "…").font(.subheadline.monospaced().weight(.semibold)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(12).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
        .padding(.horizontal, 16).padding(.bottom, 16)
    }

    private func footer(_ picker: BranchPicker?) -> some View {
        let at = model.workspace?.fetchedAt
        let stale = at.map { Date().timeIntervalSince1970 - Double($0) / 1000 > staleAfter } ?? true
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: stale ? "exclamationmark.triangle.fill" : "clock.arrow.circlepath")
                    .foregroundStyle(stale ? Color.orange : .secondary).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(picker?.fetched ?? "").font(.subheadline)
                    if stale { Text("The remote branches may be out of date.").font(.subheadline).foregroundStyle(.orange) }
                }
                Button { Task { await model.fetchNow() } } label: {
                    Label { Text(model.fetching ? "Fetching…" : "Fetch now") } icon: {
                        // turns for as long as the fetch takes
                        Image(systemName: "arrow.clockwise").symbolEffect(.rotate, options: .repeating, isActive: model.fetching)
                    }
                }
                    .controlSize(.small).disabled(model.fetching).help("Ask the remote for its latest branches")
                Spacer(minLength: 16)
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if let problem = model.fetchProblem {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red).accessibilityHidden(true)
                    Text(problem).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
                .font(.subheadline).padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.12)))
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}
