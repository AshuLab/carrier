import Foundation
import Observation

extension ConversationModel {
    /// Enter or the send button: sends what is typed, or holds it as the queued message when the agent is answering (replacing
    /// the one that was held). With `.interrupt` the turn is stopped as well: the host answers the stop once the turn has ended, and the
    /// poll that sees the session idle delivers the held message.
    public func submit(whileWorking: WhileWorking = .queue) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return }
        if busy {
            queued = text
            draft = ""
            clearRefusal()
            if whileWorking == .interrupt {
                await stop()
                await poll()
            }
        } else {
            await deliver(text)
        }
    }

    /// A button of an approval card: passes the choice to the host and polls, so the card becomes the line once the host recorded the
    /// answer. A refusal (not pending any more, not one of the choices) is shown in words; the next poll draws what the host says.
    public func answer(_ approvalId: String, choice: String, answers: [String: String]? = nil) async {
        do {
            try await host.answer(sessionId, approval: approvalId, choice: choice, answers: answers)
        } catch {
            refusedText = nil
            refusal = report(error, "answer the approval")
            return
        }
        clearRefusal()
        await poll()
    }

    /// Chooses a value in the options panel: asks the host and reads the session again, so the pill shows what the host says. A
    /// refusal is kept in words for the panel and nothing changes here.
    public func setOption(_ option: String, _ value: String) async {
        // a closed session cannot change anything: the choice waits for the message that wakes it
        if options.isEmpty, loaded, remembered.contains(where: { $0.id == option && $0.values.contains { $0.id == value } }) {
            wakeOptions[option] = value
            optionRefusal = nil
            return
        }
        do {
            try await host.setOption(sessionId, option: option, value: value)
        } catch {
            optionRefusal = report(error, "change the option").text
            return
        }
        optionRefusal = nil
        await poll()
    }

    /// Whether the panel offers the other agents: the host can, nothing is answering or being switched, and the session is not archived. The host
    /// says the rest in words (waiting for an approval, preparing, a child).
    public var canSwitchNow: Bool { canSwitchAgent && busy == false && switching == false && archived == false }

    /// Picks the agent the session changes to with the next message, or the session's own again: nothing is asked of the host here (what was chosen for the
    /// old agent is let go). The host keeps the transcript and folder, and the new agent goes on from a selection of the messages and can read the rest.
    public func chooseAgent(_ name: String) {
        guard canSwitchNow else { return }
        pendingAgent = name == agent ? nil : name
        wakeOptions = [:]
        optionRefusal = nil
    }

    /// The switch a picked agent asks for, before its message: a refusal stops the message and says why in words, and the agent stays picked.
    func switchToPendingAgent() async throws {
        guard let target = pendingAgent else { return }
        switching = true
        defer { switching = false }
        _ = try await host.switchAgent(sessionId, to: target)
        pendingAgent = nil
        wakeOptions = [:]
    }

    /// Continue on the mark of a stopped turn.
    public func continueTurn() async { await deliver("Continue", refill: false) }

    /// Try again on a failed preparation: the host repeats the steps that did not finish and the list fills in again.
    public func retryPreparation() async {
        do {
            try await host.retryPreparation(sessionId)
        } catch {
            preparationRefusal = report(error, "try the preparation again").text
            return
        }
        preparationRefusal = nil
        await poll()
    }

    /// Cancel while preparing: the host stops the running step and deletes the session, and answers the plan for the draft to take back; nil
    /// when it refused, which is said in words (`preparationRefusal`) and leaves the session as it was, or when the session stays (a worktree
    /// coming back: only its running action stops, and there is no draft to refill), which says nothing.
    public func cancelPreparation() async -> SessionPlan? {
        do {
            let plan = try await host.cancelPreparation(sessionId)
            preparationRefusal = nil
            if plan == nil { await poll() }
            return plan
        } catch {
            preparationRefusal = report(error, "cancel the preparation").text
            return nil
        }
    }

    /// Try again on a banner: the refused message again, or the person's last message when the turn failed.
    public func retry() async {
        if let text = refusedText ?? lastUserText { await deliver(text, refill: false) }
    }

    /// The first message the draft sent with the plan of this session: it shows as the person's message until the host records it.
    public func show(firstMessage text: String) {
        firstMessage = text
        rows = feed()
    }

    func feed() -> [FeedRow] {
        let signpost = Signposts.feed.beginInterval("chat feed")
        defer { Signposts.feed.endInterval("chat feed", signpost, "\(self.events.count) events") }
        feedWork += events.count
        let rows = chatFeed(events, streaming: streaming, pending: pending, working: busy)
        guard let firstMessage, events.contains(where: { $0.kind == "user" }) == false else { return rows }
        return [.user(id: "first-message", text: firstMessage)] + rows
    }

    /// The subagent view the person opened (the call that launched it), nil for the conversation itself.
    public func show(subagent call: String?) {
        openCall = call
        openSubagent = call.flatMap(work)
    }

    /// The subagent's view from the events, its header saying whether the host can stop it.
    func work(_ call: String) -> SubagentWork? {
        var work = subagentWork(in: events, call: call, working: busy)
        work?.header.hostStops = hostStops == true
        return work
    }

    /// Stop in the subagent's header: asks the host to stop the open subagent and nothing else. The view shows it stopped when the host's
    /// `stopped` event arrives, not before; a refusal (it ended meanwhile) needs no word, the next poll says how it stands.
    public func stopOpenSubagent() async {
        guard let header = openSubagent?.header, header.canStop, let task = header.taskId else { return }
        do {
            try await host.stopTask(sessionId, task: task)
        } catch {
            _ = report(error, "stop the subagent")
        }
    }

    /// Drops the queued message.
    public func cancelQueued() { queued = nil }

    /// Takes the queued message back into the box to be edited; what is already typed there stays under it.
    public func editQueued() {
        guard let held = queued else { return }
        queued = nil
        draft = draft.isEmpty ? held : held + "\n" + draft
    }

    /// Send now on the queued message: stops the turn, and the poll that sees the agent idle delivers it.
    public func sendQueuedNow() async {
        guard queued != nil else { return }
        await stop()
        await poll()
    }

    /// Stops one of the tasks the agent waits for in the background; the host refuses one that has already ended.
    public func stopTask(_ taskId: String) async {
        do {
            try await host.stopTask(sessionId, task: taskId)
            clearRefusal()
        } catch {
            refusedText = nil
            refusal = report(error, "stop the task")
        }
    }

    /// The Stop of the processes card's line: each process through `stopTask`, one at a time, and never `interrupt`, which with no turn running would stop
    /// the agent work as well. A refusal is said by `stopTask`, and the first one stays up when a later process stops cleanly; the rest are still asked.
    public func stopProcesses() async {
        var first: Refusal?
        for process in processesCard?.processes ?? [] {
            await stopTask(process.id)
            first = first ?? refusal
        }
        if let first {
            refusedText = nil
            refusal = first
        }
    }

    /// The Stop button: ends the turn (with none running, the host stops what the agent waits for in the background), then stops each subagent
    /// still running (only a host that lists `stopTask` can; a refusal means it ended meanwhile); the queued message, if any, goes when the poll
    /// sees the agent idle.
    public func stop() async {
        do {
            try await host.interrupt(sessionId)
            clearRefusal()
        } catch {
            refusedText = nil
            refusal = report(error, "stop the turn")
        }
        guard hostStops == true else { return }
        for task in runningTasks(in: events) {
            do {
                try await host.stopTask(sessionId, task: task)
            } catch {
                _ = report(error, "stop the subagent")
            }
        }
    }
}
