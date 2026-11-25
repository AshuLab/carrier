import AppKit
import CarrierCore
import SwiftUI

// The results of the shared sheet: the sections of folders, projects and repositories, and what a hovered or chosen row shows.

extension AddProjectSheet {
    @ViewBuilder func resultsList(_ current: ProjectSheetState) -> some View {
        if current.items.isEmpty {
            let emptyQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            EmptyStateView(
                icon: emptyQuery ? .folder : .search,
                title: emptyQuery ? "No recent folders" : "Nothing matches",
                line: emptyQuery
                    ? "Paste a GitHub address, type a path starting with ~ or /, drop folders here, or choose Open a folder… below."
                    : "Nothing in your recent folders or repositories matches. Paste a GitHub address, or type a path starting with ~ or / to add any folder."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Tokens.Space.s14) {
                    ForEach(current.sections) { section in
                        VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                            if let title = section.title {
                                Text(title)
                                    .sectionLabel()
                                    .padding(.horizontal, Tokens.Space.s10)
                                    .padding(.bottom, Tokens.Space.s2)
                            }
                            ForEach(section.items) { item in
                                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                                    resultRow(item, highlighted: highlightedId == item.id)
                                    if item.destination != nil, highlightedId == item.id || section.id == "path" { destinationLine(item) }
                                }
                                .id(item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, Tokens.Space.s16)
                .padding(.vertical, Tokens.Space.s14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func resultRow(_ item: ProjectSheetResult, highlighted: Bool) -> some View {
        HoverRow(
            action: { activate(item) },
            fill: highlighted ? theme.accent.opacity(0.16) : nil
        ) { hovering in
            HStack(spacing: Tokens.Space.s12) {
                ProjectIcon(tile: item.tile)
                VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                    HStack(spacing: Tokens.Space.s6) {
                        Text(item.title)
                            .scaledFont(13, weight: .medium)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let chip = item.chip { StatusChip(text: chip, tint: .secondary) }
                    }
                    Text(item.detail)
                        .scaledFont(11, design: item.kind.isRepository ? .default : .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(item.kind.isRepository ? .tail : .middle)
                }
                Spacer(minLength: 8)
                if item.pushed.isEmpty == false {
                    Text(item.pushed).scaledFont(11).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
                }
                actionBadge(item.actionTitle, active: (hovering || highlighted) && item.isEnabled)
            }
            .padding(.horizontal, Tokens.Space.s10)
            .padding(.vertical, Tokens.Space.s8)
        }
        .disabled(item.isEnabled == false)
        .accessibilityLabel(item.problem.map { "\(item.title), \($0)" } ?? "\(item.title), \(item.detail)")
        .accessibilityAddTraits(highlighted ? .isSelected : [])
    }

    /// Where a clone goes, with Choose… to change it for this clone only; a repository the login cannot see says so in orange instead.
    @ViewBuilder private func destinationLine(_ item: ProjectSheetResult) -> some View {
        if let problem = item.problem {
            ProblemLine(text: problem).padding(.horizontal, Tokens.Space.s10).padding(.bottom, Tokens.Space.s4)
        } else if let destination = item.destination, case .cloneRepo(let repo, _) = item.kind {
            VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                HStack(spacing: Tokens.Space.s8) {
                    Text(destination.line)
                        .scaledFont(11, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(destination.parent + "/" + repo)
                    if destination.canChoose {
                        Button("Choose…") { chooseParent(for: repo, current: destination.parent) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .accessibilityLabel("Choose where \(repo) is cloned")
                    }
                    Spacer(minLength: 0)
                }
                if let watch = item.watch, let newSession { watchChoice(watch, newSession) }
            }
            .padding(.horizontal, Tokens.Space.s10).padding(.bottom, Tokens.Space.s4)
        }
    }

    /// "Let Carrier watch this repo": on by default, a choice of the plan acted on once the first message was prepared; off, with the reason, when it cannot be on.
    private func watchChoice(_ watch: ProjectSheetWatch, _ newSession: NewSessionModel) -> some View {
        let on = watch.problem == nil && newSession.watch
        return HStack(spacing: Tokens.Space.s8) {
            Toggle("Let Carrier watch this repo", isOn: Binding(get: { on }, set: { newSession.watch = $0 }))
                .toggleStyle(.switch).controlSize(.small).scaledFont(11)
                .disabled(watch.problem != nil)
            if let reason = watch.problem { ProblemLine(text: reason, size: 11, announces: false) }
            Spacer(minLength: 0)
        }
    }

    private func actionBadge(_ title: String, active: Bool) -> some View {
        Text(title)
            .scaledFont(11, weight: .semibold)
            .foregroundStyle(active ? .white : .secondary)
            .padding(.horizontal, Tokens.Space.s10)
            .padding(.vertical, Tokens.Space.s3)
            .background(Capsule().fill(active ? theme.accentGlass : Color.primary.opacity(0.08)))
    }

    // MARK: Drop Veil

    var dropVeil: some View {
        VStack(spacing: Tokens.Space.s4) {
            Glyph(.folderPlus, size: 22).foregroundStyle(.tint)
            Text(mode.actsAtOnce ? "Drop folders to add" : "Drop a folder to work in").scaledFont(14, weight: .semibold)
            Text(mode.actsAtOnce ? "Folders are added to your projects; files are refused" : "The folder fills the plan; nothing is written").scaledFont(12).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(.tint.opacity(0.14)))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.card).strokeBorder(.tint, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])))
        .padding(Tokens.Space.s8)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
