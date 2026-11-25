import AppKit
import Observation
import CarrierCore
import SwiftUI

/// What `--smoke-window` reads off the open window: which page is selected and how the window is laid out on it.
extension WindowController {
    /// For `--smoke-window`: selects the first epic Carrier reports (running, queued, then finished), so its view is on screen.
    func selectFirstEpic() {
        guard case .running(let snapshot)? = model.state else { return }
        let first = snapshot.epics.first.map { ($0.repo, $0.issue) } ?? snapshot.queue.first.map { ($0.repo, $0.issue) }
            ?? snapshot.done.first.map { ($0.repo, $0.issue) }
        if let (repo, issue) = first { model.shell.selection = .epic(repo: repo, issue: issue) }
    }

    /// For `--smoke-window`: selects the first session the chat host lists, so its conversation is on screen.
    func selectFirstSession() {
        if let first = model.sessions.rows.first(where: { $0.archived == false }) { model.shell.selection = .session(id: first.id) }
    }

    /// For `--smoke-window`: selects the Archive page.
    func selectArchive() { model.shell.selection = .archive }

    /// For `--smoke-window`, with the Archive selected: what the page lists and says, then the window's layout as it is with it on screen.
    var archiveStructure: String {
        let page = archivePage(model.sessions.rows, by: SidebarStore().archiveSort)
        let line = "archive: \(page.subtitle.isEmpty ? "no count" : page.subtitle), groups \(page.groups.map(\.title)), \(page.emptyState?.title() ?? "listed"), clear \(page.canClear ? "enabled" : "disabled")"
        return line + "\n" + structure
    }

    /// For `--smoke-window`, after `selectFirstSession`: how the conversation is laid out (read from the constants the view uses) and
    /// what the model makes of the first session's events, which it asks the chat host for as the view does.
    @MainActor func chatStructure() async -> String {
        var lines = ["chat transcript: \(ConversationView.layout)"]
        if case .session(let id) = model.shell.selection {
            let conversation = ConversationModel(host: SocketChatHost(), sessionId: id)
            let start = Date()
            await conversation.poll()
            let took = Int(Date().timeIntervalSince(start) * 1000)
            let groups = conversation.rows.filter { if case .tools = $0 { true } else { false } }.count
            lines.append("chat feed: \(conversation.rows.count) rows (\(groups) of tool calls) from \(conversation.cursor) events in \(took) ms, options: \(optionsPill(conversation.options) ?? "none")\(conversation.failure.map { ", failed: \($0)" } ?? "")")
        } else {
            lines.append("chat feed: no session to select")
        }
        return lines.joined(separator: "\n")
    }

    /// For `--smoke-window`: shows the draft of a new session and says what it offers, as the view reads it from the chat host.
    @MainActor func newSessionStructure() async -> String {
        model.shell.selection = .newSession
        await model.newSession.load()
        let draft = model.newSession
        var lines = ["new session: \"\(draft.sentence)\", agents \(draft.agents.map { choice in choice.note().map { "\(choice.name) (\($0))" } ?? choice.name }), agent \(draft.agent ?? "none"), recent \(draft.recent.map(\.name))"]
        // the worktree half, for the first recent folder: what the host says it is, then the sentence in a new worktree
        if let folder = draft.recent.first?.path {
            await draft.choose(folder: folder)
            lines.append("new session folder: \"\(draft.sentence)\", warning \(draft.warning ?? "none"), worktree \(draft.offersWorktree ? "offered" : "not offered")")
            await draft.useWorktree(true)
            if draft.worktree {
                let picker = draft.picker(query: "")
                lines.append("new session worktree: \"\(draft.sentence)\", name \(draft.nameState), branches \(picker?.local.count ?? 0) local and \(picker?.remote.count ?? 0) remote, tabs \(draft.hasStartTabs ? "\(draft.startTab.tabTitle) open" : "none"), starts from \(draft.startPoint?.ref ?? "nothing"), \(picker?.fetched ?? "no picker")")
                await draft.useWorktree(false)
            }
        }
        // the sheet New session opens: what it lists (the projects that are not hidden, folders used lately, the person's repositories) and what choosing fills
        draft.openPicker()
        var github = ProjectSheetGithub(defaultParent: draft.projectsPath)
        github.watched = draft.watched
        let known = ProjectsModel.shared.rows
        func sheet(_ query: String) -> ProjectSheetState { projectSheetState(mode: .newSession, query: query, recent: draft.recent, projects: known, github: github) }
        lines.append("new session sheet: \(sheet("").sections.map { "\($0.title ?? "result") \($0.items.count)" }), projects \(known.filter { $0.hidden == false }.map(\.name)), folder \(draft.projectsPath)")
        // a repository (one the host lists, then one it does not) only fills the plan; nothing is cloned and the repository is watched unless the person said no
        for text in ["https://github.com/AshuLab/web", "AshuLab/api", "AshuLab/nope"] {
            guard let result = sheet(text).firstResult else { continue }
            await draft.choose(result)
            lines.append("new session repo \(text): \(result.destination?.line ?? "none"), \"\(draft.sentence)\", branches \(draft.picker(query: "")?.local.map(\.name) ?? []), problem \(draft.workspaceProblem ?? "none"), worktree \(draft.offersWorktree ? "offered" : "not offered"), \(draft.sendSteps.count) send steps, watching \(draft.watching)")
        }
        // New project: only the plan is filled (the draft then offers no worktree)
        draft.choose(newProject: "my-idea")
        lines.append("new session project my-idea: \"\(draft.sentence)\", worktree \(draft.offersWorktree ? "offered" : "not offered")")
        return lines.joined(separator: "\n")
    }

    /// For `--smoke-window`: what the open window looks like, one line each: the minimum content size, the width of each
    /// column of the split view, the scroll pockets (the system's blur under a bar over a scroll view: the epic's pipeline
    /// makes one in the centre column), the toolbar's items, how the transcript is laid out and the time to merge 5,000 events.
    var structure: String {
        guard let window else { return "no window" }
        var lines = ["min content size: \(Int(Self.minContent.width)) x \(Int(Self.minContent.height))"]
        lines.append("app: \(NSApp.activationPolicy() == .regular ? "in the Dock" : "no Dock icon"), menus \(NSApp.mainMenu?.items.map(\.title) ?? [])")
        func walk(_ view: NSView) {
            if let split = view as? NSSplitView {
                // the sidebar and the detail, then the detail and the inspector: the inspector is a split of its own inside the detail
                for column in split.arrangedSubviews where column.frame.width > 0 {
                    lines.append("column: x \(Int(column.frame.minX.rounded())) width \(Int(column.frame.width.rounded()))")
                }
            }
            if String(describing: type(of: view)) == "NSScrollPocket" {
                let frame = view.convert(view.bounds, to: nil)
                lines.append("scroll pocket: x \(Int(frame.minX.rounded())) width \(Int(frame.width.rounded())) height \(Int(frame.height.rounded()))")
            }
            view.subviews.forEach(walk)
        }
        if let content = window.contentView { walk(content) }
        for item in window.toolbar?.items ?? [] {
            // where each one sits in the window, left edge and width: an item that is not where it belongs shows here
            let frame = item.view.map { $0.convert($0.bounds, to: nil) }
            lines.append("toolbar item: \(item.label.isEmpty ? item.itemIdentifier.rawValue : item.label)\(frame.map { " at x \(Int($0.minX)) width \(Int($0.width))" } ?? "")")
        }
        lines.append("sessions: \(model.sessions.rows.count) rows, \(archivedCount(model.sessions.rows)) archived, groups \(sessionGroups(model.sessions.rows).map(\.title))")
        let home = sessionsPage(model.sessions.rows, by: SidebarStore().sessionSort)
        lines.append("sessions home: \(home.subtitle.isEmpty ? "no count" : home.subtitle), \(home.emptyState?.title() ?? "listed")")
        lines.append("transcript: \(SessionSectionsView.layout)")
        let events = longTranscriptEvents(rounds: 556)
        var transcript = Transcript()
        let start = Date()
        transcript.apply(EventsReply(events: events, next: events.count, running: true, structured: true))
        lines.append("transcript merge: \(events.count) events in \(Int(Date().timeIntervalSince(start) * 1000)) ms, \(transcript.work) processed")
        return lines.joined(separator: "\n")
    }

    /// For `--smoke-window`: the window at its smallest, one line per page with how tall the split view lays out. A page that asks for
    /// more than the window has (its title bar's 26 points apart) shows the sidebar and the bottom of the page pushed out of the window.
    @MainActor func minimumSizeReport() async -> String {
        guard let window else { return "no window" }
        window.setContentSize(Self.minContent)
        var lines = ["at the smallest size (\(Int(Self.minContent.width)) x \(Int(Self.minContent.height))), split view height per page:"]
        func splitHeight() -> Int {
            var found = 0
            func walk(_ view: NSView) {
                if found == 0, let split = view as? NSSplitView, let first = split.arrangedSubviews.first { found = Int(first.frame.height) }
                view.subviews.forEach(walk)
            }
            if let content = window.contentView { walk(content) }
            return found
        }
        let pages: [(String, () -> Void)] = [
            ("home", { self.model.shell.selection = .home }), ("sessions", { self.model.shell.selection = .sessions }),
            ("new session", { self.model.shell.selection = .newSession }), ("archive", { self.model.shell.selection = .archive }),
            ("carrier", { self.model.shell.selection = .carrier }), ("terminals", { self.model.shell.selection = .terminals }),
            ("usage", { self.model.shell.selection = .usage }),
            ("first session", { self.selectFirstSession() }),
        ]
        for (name, select) in pages {
            select()
            try? await Task.sleep(for: .milliseconds(700))
            let height = splitHeight()
            lines.append("  \(name): \(height)\(height > Int(Self.minContent.height) + 40 ? "  <- taller than the window" : "")")
        }
        // the last page is a session: where its toolbar's items sit, left edge and width (the header on the left, the Open menu on the right)
        let items = (window.toolbar?.items ?? []).compactMap { item in
            item.view.map { "\(item.label.isEmpty ? String(item.itemIdentifier.rawValue.prefix(8)) : item.label) x \(Int($0.convert($0.bounds, to: nil).minX)) w \(Int($0.bounds.width))" }
        }
        lines.append("  toolbar with a session open: \(items.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }
}
