import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

// The Worktrees and disk group of a project's screen, and what its buttons do: remove a worktree, clean up, delete the project from disk.

extension ProjectDetailView {
    /// The Worktrees and disk group: the total and a bar, then the main clone and each worktree Carrier made with its size. The worktrees are asked of the host when
    /// the page opens, and so is a fresh measure; the last known figure stays on show meanwhile.
    @ViewBuilder var worktreesGroup: some View {
        let figure = model.disk[(row.path as NSString).expandingTildeInPath]
        let measuring = model.measuring.contains((row.path as NSString).expandingTildeInPath)
        SettingsGroup(title: Copy.projectsWorktreesTitle(), footer: Copy.projectsWorktreesFooter()) {
            if let worktrees {
                let items = worktreeRows(worktrees, sizes: figure?.parts ?? [:], now: Date())
                let shares = diskShares(items)
                SettingsTabRow(title: Copy.projectsTotal(), detail: diskTotalWords(figure, measuring: measuring, now: Date()), first: true) {
                    HStack(spacing: Tokens.Space.s8) {
                        if measuring { ProgressView().controlSize(.small) }
                        Text(figure?.bytes.map(formatDiskSize) ?? "—").fontWeight(.medium).monospacedDigit()
                    }
                }
                if shares.isEmpty == false {
                    DiskBar(shares: shares, color: { diskColor($0, in: items) })
                        .padding(.vertical, Tokens.Space.s10).frame(maxWidth: .infinity)
                        .overlay(alignment: .top) { SettingsDivider() }
                }
                ForEach(items) { item in
                    SettingsTabRow(title: item.branch, detail: item.detail(), mono: true, problem: removeProblems[item.id]) {
                        HStack(spacing: Tokens.Space.s10) {
                            // the activity above the integration: both chips and the link keep their width, so the row's words are what gives way at the narrowest window
                            VStack(alignment: .trailing, spacing: Tokens.Space.s4) {
                                if let activity = item.activity, let kind = item.activityKind { StatusChip(text: activity, tint: activityTint(kind)).fixedSize() }
                                HStack(spacing: Tokens.Space.s6) {
                                    if let integration = item.integration, let kind = item.integrationKind { StatusChip(text: integration, tint: integrationTint(kind)).fixedSize() }
                                    if let pullRequest = item.pullRequest { PullRequestChip(number: pullRequest.number, dot: nil, url: pullRequest.url) }
                                }
                            }
                            if item.hasRemove {
                                // the trash alone: the tooltip and the label say what the icon does, so no word sits in the row
                                Button { Task { await removeWorktree(item.id) } } label: { Glyph(.trash, size: 14).frame(width: 24, height: 24).contentShape(Rectangle()) }
                                    .buttonStyle(HoverFillButtonStyle()).foregroundStyle(.secondary)
                                    .disabled(item.removeBlockedBy() != nil || removing.contains(item.id))
                                    .help(item.removeBlockedBy() ?? Copy.projectsRemoveWorktreeHelp())
                                    .accessibilityLabel(Copy.projectsRemoveWorktreeLabel(branch: item.branch))
                            }
                            HStack(spacing: Tokens.Space.s6) {
                                Circle().fill(diskColor(item.id, in: items)).frame(width: 7, height: 7).accessibilityHidden(true)
                                Text(item.size).scaledFont(12).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
                if let cleanup, let words = cleanUpWords(cleanup) {
                    SettingsTabRow(title: Copy.projectsCleanUpTitle(), detail: Copy.projectsCleanUpDetail(words: words)) {
                        Button { confirmingCleanup = true } label: { Label(Copy.projectsCleanUp(), icon: .trash) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .disabled(removing.isEmpty == false)
                    }
                }
                if let cleanUpNote {
                    SettingsTabRow(title: Copy.projectsLastCleanUp(), detail: cleanUpNote, wrapsDetail: true) { EmptyView() }
                }
            } else if let worktreesProblem {
                SettingsTabRow(title: Copy.projectsWorktrees(), detail: "", first: true, problem: worktreesProblem) { EmptyView() }
            } else {
                SettingsTabRow(title: Copy.projectsWorktrees(), detail: "", first: true) { ProgressView().controlSize(.small) }
            }
        }
    }

    /// The colour of a folder in the bar and before its size: the main clone the theme's accent, then one for each worktree, round again after six.
    private func diskColor(_ id: String, in items: [WorktreeRow]) -> Color {
        let palette: [Color] = [theme.accent, .teal, .indigo, .purple, .pink, .mint]
        return palette[(items.firstIndex { $0.id == id } ?? 0) % palette.count]
    }

    /// What the alert of Clean up says it takes and leaves.
    var cleanUpQuestionWords: String { Copy.projectsCleanUpQuestionWords() }

    private func activityTint(_ activity: ProjectWorktree.Activity) -> Color {
        switch activity {
        case .sessionOpen: theme.accent
        case .uncommitted: .orange
        }
    }

    /// Purple for a merged pull request as everywhere, green for what main already holds, orange for work held nowhere else, blue for a pull request still open, grey for the rest.
    private func integrationTint(_ integration: ProjectWorktree.Integration) -> Color {
        switch integration {
        case .merged: Color(Tokens.PullRequest.merged)
        case .inMain: .green
        case .notPushed: .orange
        case .prOpen: .blue
        case .prClosed, .pushed: .secondary
        }
    }

    /// The question or refusal that stops deleting a project from disk: `canConfirm` when it is unsaved work the person may accept, and not when it is a session that is open or a failure.
    struct DeletionAsk {
        let title: String
        let message: String
        var canConfirm = false
    }

    /// Asks the host again just now (`deletionCheck`) and goes on only when nothing refuses and the unsaved work, if any, was confirmed; a failed move leaves everything where it was.
    func deleteFromDisk(confirmed: Bool) async {
        deleting = true
        defer { deleting = false }
        do {
            let (check, folders) = try await model.deletionCheck(of: row.path)
            if check.canGoOn == false {
                deletionAsk = DeletionAsk(title: Copy.projectsCannotDeleteYet(name: row.name), message: Copy.projectsCannotDeleteMessage(refusals: check.refusals.joined(separator: "\n")))
            } else if check.needsConfirmation && confirmed == false {
                deletionAsk = DeletionAsk(title: Copy.projectsUnsavedTitle(name: row.name), message: Copy.projectsUnsavedMessage(unsaved: check.unsaved.joined(separator: "\n")), canConfirm: true)
            } else {
                try await model.deleteFromDisk(path: row.path, worktrees: folders)
                close()
            }
        } catch ControlError.remote(let refusal) {
            deletionAsk = DeletionAsk(title: Copy.projectsNotDeleted(name: row.name), message: refusal.shown())
        } catch let error as ProjectTrashError {
            deletionAsk = DeletionAsk(title: Copy.projectsNotDeleted(name: row.name), message: error.words)
        } catch {
            deletionAsk = DeletionAsk(title: Copy.projectsNotDeleted(name: row.name), message: Copy.projectsHostNoAnswerNothingDeleted())
        }
    }

    func loadWorktrees() async {
        guard row.status == .ready else { return }
        do {
            let listed = try await model.worktrees(of: row.path)
            worktrees = listed
            worktreesProblem = nil
            // measuring what Clean up takes walks the folders, so only a project with a finished worktree asks
            cleanup = listed.worktrees.hasFinished ? try? await model.cleanUpWorktrees(of: row.path, run: false) : nil
        } catch ControlError.remote(let refusal) {
            worktreesProblem = refusal.shown()
        } catch {
            worktreesProblem = Copy.projectsHostNoAnswer()
        }
    }

    /// Removes one worktree's folder; the host's reason for refusing it stays in that row until the next try.
    private func removeWorktree(_ path: String) async {
        removing.insert(path)
        defer { removing.remove(path) }
        do {
            try await model.removeWorktree(path, of: row.path)
            removeProblems[path] = nil
            cleanUpNote = nil
        } catch ControlError.remote(let refusal) {
            removeProblems[path] = refusal.shown()
        } catch {
            removeProblems[path] = Copy.projectsHostNoAnswer()
        }
        // what is left of the project is measured again, so the total and the bar follow the folders that went
        await model.refreshDisk(.now, of: [row.path])
        await loadWorktrees()
    }

    func runCleanup() async {
        guard let cleanup else { return }
        removing = Set(cleanup.removed.map(\.path))
        defer { removing = [] }
        do {
            cleanUpNote = cleanUpReport(try await model.cleanUpWorktrees(of: row.path, run: true))
            removeProblems = [:]
        } catch ControlError.remote(let refusal) {
            cleanUpNote = refusal.shown()
        } catch {
            cleanUpNote = Copy.projectsHostNoAnswer()
        }
        // what is left of the project is measured again, so the total and the bar follow the folders that went
        await model.refreshDisk(.now, of: [row.path])
        await loadWorktrees()
    }
}
