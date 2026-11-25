import AppKit
import CarrierCore
import SwiftUI

// The Worktrees and disk group of a project's screen, and what its buttons do: remove a worktree, clean up, delete the project from disk.

extension ProjectDetailView {
    /// The Worktrees and disk group: the total and a bar, then the main clone and each worktree Carrier made with its size. The worktrees are asked of the host when
    /// the page opens, and so is a fresh measure; the last known figure stays on show meanwhile.
    @ViewBuilder var worktreesGroup: some View {
        let figure = model.disk[(row.path as NSString).expandingTildeInPath]
        let measuring = model.measuring.contains((row.path as NSString).expandingTildeInPath)
        SettingsGroup(title: "Worktrees and disk", footer: "The worktrees Carrier made for sessions of this project, and what each folder takes on disk.") {
            if let worktrees {
                let items = worktreeRows(worktrees, sizes: figure?.parts ?? [:], now: Date())
                let shares = diskShares(items)
                SettingsTabRow(title: "Total", detail: diskTotalWords(figure, measuring: measuring, now: Date()), first: true) {
                    HStack(spacing: 8) {
                        if measuring { ProgressView().controlSize(.small) }
                        Text(figure?.bytes.map(formatDiskSize) ?? "—").fontWeight(.medium).monospacedDigit()
                    }
                }
                if shares.isEmpty == false {
                    DiskBar(shares: shares, color: { diskColor($0, in: items) })
                        .padding(.vertical, 10).frame(maxWidth: .infinity)
                        .overlay(alignment: .top) { SettingsDivider() }
                }
                ForEach(items) { item in
                    SettingsTabRow(title: item.branch, detail: item.detail, mono: true, problem: removeProblems[item.id]) {
                        HStack(spacing: 10) {
                            if let state = item.state, let kind = item.kind { StatusChip(text: state, tint: worktreeTint(kind)) }
                            if item.hasRemove {
                                Button { Task { await removeWorktree(item.id) } } label: { Label("Remove", icon: .trash) }
                                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                                    .disabled(item.removeBlockedBy != nil || removing.contains(item.id))
                                    .help(item.removeBlockedBy ?? "Removes this worktree's folder; its branch and its session stay")
                                    .accessibilityLabel("Remove the worktree \(item.branch)")
                            }
                            HStack(spacing: 6) {
                                Circle().fill(diskColor(item.id, in: items)).frame(width: 7, height: 7).accessibilityHidden(true)
                                Text(item.size).font(.scaled(12)).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .frame(width: 76, alignment: .trailing)
                        }
                    }
                }
                if let cleanup, let words = cleanUpWords(cleanup) {
                    SettingsTabRow(title: "Clean up", detail: "Merged worktrees nothing blocks: \(words)") {
                        Button { confirmingCleanup = true } label: { Label("Clean up", icon: .trash) }
                            .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
                            .disabled(removing.isEmpty == false)
                    }
                }
                if let cleanUpNote {
                    SettingsTabRow(title: "Last clean up", detail: cleanUpNote, wrapsDetail: true) { EmptyView() }
                }
            } else if let worktreesProblem {
                SettingsTabRow(title: "Worktrees", detail: "", first: true, problem: worktreesProblem) { EmptyView() }
            } else {
                SettingsTabRow(title: "Worktrees", detail: "", first: true) { ProgressView().controlSize(.small) }
            }
        }
    }

    /// The colour of a folder in the bar and before its size: the main clone the theme's accent, then one for each worktree, round again after six.
    private func diskColor(_ id: String, in items: [WorktreeRow]) -> Color {
        let palette: [Color] = [.themeAccent, .teal, .indigo, .purple, .pink, .mint]
        return palette[(items.firstIndex { $0.id == id } ?? 0) % palette.count]
    }

    /// What the alert of Clean up says it takes and leaves.
    var cleanUpQuestionWords: String { "Their folders go, with what git ignores in them. Their branches and their sessions stay, and a session's next message brings its folder back." }

    private func worktreeTint(_ state: ProjectWorktree.State) -> Color {
        switch state {
        case .sessionOpen: .accentColor
        case .merged: .green
        case .uncommitted, .notPushed: .orange
        case .clean: .secondary
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
                deletionAsk = DeletionAsk(title: "\(row.name) cannot be deleted yet", message: "\(check.refusals.joined(separator: "\n"))\n\nClose the sessions of the project first. Nothing was deleted.")
            } else if check.needsConfirmation && confirmed == false {
                deletionAsk = DeletionAsk(title: "\(row.name) has work that is not saved", message: "\(check.unsaved.joined(separator: "\n"))\n\nMoving it to the Trash keeps it there until the Trash is emptied.", canConfirm: true)
            } else {
                try await model.deleteFromDisk(path: row.path, worktrees: folders)
                close()
            }
        } catch ControlError.remote(let refusal) {
            deletionAsk = DeletionAsk(title: "\(row.name) was not deleted", message: refusal.text)
        } catch let error as ProjectTrashError {
            deletionAsk = DeletionAsk(title: "\(row.name) was not deleted", message: error.words)
        } catch {
            deletionAsk = DeletionAsk(title: "\(row.name) was not deleted", message: "The chat host did not answer. Nothing was deleted.")
        }
    }

    func loadWorktrees() async {
        guard row.status == .ready else { return }
        do {
            let listed = try await model.worktrees(of: row.path)
            worktrees = listed
            worktreesProblem = nil
            // measuring what Clean up takes walks the folders, so only a project with a merged worktree asks
            cleanup = listed.worktrees.contains { $0.state == .merged } ? try? await model.cleanUpWorktrees(of: row.path, run: false) : nil
        } catch ControlError.remote(let refusal) {
            worktreesProblem = refusal.text
        } catch {
            worktreesProblem = "The chat host did not answer."
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
            removeProblems[path] = refusal.text
        } catch {
            removeProblems[path] = "The chat host did not answer."
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
            cleanUpNote = refusal.text
        } catch {
            cleanUpNote = "The chat host did not answer."
        }
        // what is left of the project is measured again, so the total and the bar follow the folders that went
        await model.refreshDisk(.now, of: [row.path])
        await loadWorktrees()
    }
}
