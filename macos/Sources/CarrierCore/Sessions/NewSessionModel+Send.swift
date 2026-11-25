import Foundation
import Observation

extension NewSessionModel {
    public var canSend: Bool { canSendWithText && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }

    /// Whether everything but the text is ready: a long text pasted into the box is the message when there is none typed.
    public var canSendWithText: Bool {
        guard folder != nil, hostOlder == false, agents.contains(where: { $0.name == agent && $0.available }), sending == false else { return false }
        guard worktree else { return true }
        if case .problem = nameState { return false }
        return startPoint != nil && (worktreeName.isEmpty == false || toClone)
    }

    /// What `send` asks `open` for: nil in the base folder.
    var worktreeRequest: WorktreeRequest? {
        guard worktree, let point = startPoint else { return nil }
        let name = worktreeName.isEmpty ? nil : worktreeName
        // an older host takes no `startFrom`: a remote start is the ref `origin/<name>`, as the app always named it
        guard hostStarts, let side = point.side else { return WorktreeRequest(from: point.ref, name: name) }
        return WorktreeRequest(from: point.branch, name: name, startFrom: side)
    }

    /// Opens the session with one request that carries the plan and the first message, and returns the session's id to select, nil when
    /// `open` was refused or was not made (the draft keeps the text and says why). The host prepares the session in the background and its
    /// conversation shows the steps; the message is kept in `takeFirstMessage` for it.
    public func send() async -> String? {
        guard canSend, let folder, let agent else { return nil }
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        refusal = nil
        defer { sending = false }
        guard await ensureHost() else {
            refusal = .hostNotRunning
            return nil
        }
        // a host that was not running when the draft opened has not said yet whether it takes a plan
        if let capabilities = try? await host.capabilities() {
            hostOlder = capabilities.contains(.plan) == false
            hostStarts = capabilities.contains(.worktreeStart)
        }
        guard hostOlder == false else { return nil }
        let id: String
        do {
            id = try await host.open(plan: SessionPlan(agent: agent, workspace: newProject.map(PlanWorkspace.newProject) ?? repo.map(PlanWorkspace.repo) ?? .folder(folder), branch: branchChange?.to, worktree: worktreeRequest, options: chosenOptions, text: message))
        } catch {
            refusal = report(error, "open the session")
            return nil
        }
        firstMessages[id] = message
        // added when the `message` step is done, never before
        if let repo, watch, watchProblem(for: repo) == nil { pendingWatches[id] = repo; watchSince = Date(); keepWatching() }
        blank()
        return id
    }

    /// The first message of a session this draft opened, handed over once to the conversation that shows it.
    public func takeFirstMessage(of id: String) -> String? { firstMessages.removeValue(forKey: id) }

    func report(_ error: Error, _ doing: String) -> Refusal {
        let refusal = ConversationModel.refusal(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return refusal }
        log("new session: could not \(doing): \(refusal.text)")
        return refusal
    }
}
