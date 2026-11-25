import Foundation
import Observation

/// The rows the events make, in order, and then the message in progress when `streaming` has text. Consecutive calls are one row
/// at the place where the first started, each completed by its end (a turn that ends first stops the calls still going); an
/// approval is one row at the place where it was asked: a card while its id is in `pending` (what the host still waits for),
/// a line once answered, and a plain line when it is neither (the turn ended without it).
/// A `reasoning` event is a thought of the run of calls it comes in (the host stores each block where the agent had it); one that comes
/// before the first call of a run waits for it, and one with no call after it is a run of its own, before the message or the end of its
/// turn: the agent's work is always above its answer. A subagent is a row of the run that launched it, built from the `task` events that share its
/// launching call's id and the events made inside it (`parentCallId`); the launching call is not one of the run's calls, and a subagent goes on
/// from events that come after the turn ended. What a nested subagent does is not drawn here. A subagent that started and never ended, in a
/// session that is not `working`, is shown stopped: the host that ran it is gone.
/// Anything else the host may add is not drawn.
public func chatFeed(
    _ events: [ChatEvent], streaming: String = "", pending: Set<String> = [], working: Bool = true, bundle: Bundle? = nil, locale: Locale = .current
) -> [FeedRow] {
    var rows: [FeedRow] = []
    // where each call still going is: its row and its place in it
    var going: [String: (row: Int, call: Int)] = [:]
    var asked: [String: (row: Int, event: ChatEvent)] = [:]
    var turnStart: Int?
    /// The context the last turn that said it ended with: what a `/clear` frees.
    var lastContext: Double?
    var held: [Thought] = []
    // the calls that launched a subagent of the main agent (a `task` event names its call), and where each subagent is: its row and its place in it
    let launching = Set(events.compactMap { $0.kind == "task" && $0.parentCallId == nil ? $0.callId : nil })
    var subagents: [String: (row: Int, index: Int)] = [:]
    // thoughts no call came to take: a run of their own, where the piece that ends them begins
    func release() {
        guard let first = held.first else { return }
        rows.append(.tools(id: first.id, ToolGroup(calls: [], thoughts: held, since: turnStart)))
        held = []
    }
    for event in events {
        // made inside a subagent: the main conversation does not draw it, it is what its row says it is doing
        if let parent = event.parentCallId {
            if let spot = subagents[parent], case .tools(let group, var run) = rows[spot.row] {
                run.subagents[spot.index].apply(inside: event)
                rows[spot.row] = .tools(id: group, run)
            }
            continue
        }
        let id = "e\(event.id)"
        switch event.kind {
        case "task":
            guard let call = event.callId, launching.contains(call) else { continue }
            if let spot = subagents[call], case .tools(let group, var run) = rows[spot.row] {
                run.subagents[spot.index].apply(task: event)
                rows[spot.row] = .tools(id: group, run)
            } else {
                subagents[call] = place(Subagent(task: event, bundle: bundle, locale: locale), in: &rows, id: id, held: &held)
            }
        case "tool_start" where event.callId.map(launching.contains) == true, "tool_end" where event.callId.map(launching.contains) == true:
            continue
        case "reasoning":
            // trimmed: the provider's blocks start and end with blank lines, and the card shows two lines of a thought
            guard let text = event.text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else { continue }
            if case .tools(let group, var run)? = rows.last {
                run.thoughts.append(Thought(id: id, text: text, at: event.at, before: run.calls.count))
                rows[rows.count - 1] = .tools(id: group, run)
            } else {
                held.append(Thought(id: id, text: text, at: event.at, before: 0))
            }
        case "user":
            release()
            turnStart = event.at
            rows.append(.user(id: id, text: event.text ?? ""))
        case "assistant":
            release()
            rows.append(.agent(id: id, text: event.text ?? "", inProgress: false))
        case "tool_start":
            let call = ToolCall(start: event)
            going[call.id] = place(call, in: &rows, id: id, held: &held)
        case "tool_end":
            if let call = event.callId, let spot = going.removeValue(forKey: call), case .tools(let group, var calls) = rows[spot.row] {
                calls.calls[spot.call].finish(event)
                rows[spot.row] = .tools(id: group, calls)
            } else {
                _ = place(ToolCall(orphanEnd: event), in: &rows, id: id, held: &held)
            }
        case "approval":
            if let approval = event.approvalId { asked[approval] = (rows.count, event) }
            if let approval = event.approvalId, pending.contains(approval) {
                let tool = event.tool ?? Copy.chatApprovalTheTool(bundle: bundle, locale: locale)
                let question = Copy.chatApprovalAllow(tool: tool, bundle: bundle, locale: locale)
                rows.append(.approval(id: id, ApprovalCard(approvalId: approval, question: question, tool: tool, arg: event.arg, choices: event.choices ?? [], questions: event.questions ?? [])))
            } else {
                rows.append(.line(id: id, text: Copy.chatApprovalNoLongerWaiting(what: what(event), bundle: bundle, locale: locale)))
            }
        case "approval_answered":
            guard let approval = event.approvalId, let question = asked[approval] else { continue }
            rows[question.row] = decided(question.event, choice: event.choiceId, answers: event.answers, id: rows[question.row].id, bundle: bundle, locale: locale)
        case "turn_end":
            release()
            for spot in going.values {
                guard case .tools(let group, var calls) = rows[spot.row] else { continue }
                calls.calls[spot.call].stop()
                rows[spot.row] = .tools(id: group, calls)
            }
            going = [:]
            if event.outcome == "error" { markLastRunErred(in: &rows) }
            // a `/clear` the agent answered with nothing: the empty line of its turn is the divider of the clear, and the context starts again from none
            if event.outcome != "error", event.outcome != "interrupted", case .user(_, let said)? = rows.last, isClearCommand(said) {
                rows.append(.cleared(id: id, freed: lastContext))
                lastContext = nil
            } else if case .compacted? = rows.last {
                // a `/compact` the agent answered with nothing more: the cut is what the turn said, and its own line of statistics would only be empty
            } else if let summary = TurnSummary(event, turnStart: turnStart) {
                rows.append(.turnEnd(id: id, summary))
                lastContext = summary.contextTokens ?? lastContext
            }
            if event.outcome == "interrupted" { rows.append(.stopped(id: "\(id)-stopped")) }
            turnStart = nil
        case "error":
            release()
            rows.append(.error(id: id, text: event.text ?? Copy.chatErrorGeneric(bundle: bundle, locale: locale)))
        case "compact":
            release()
            rows.append(.compacted(id: id, Compaction(event)))
            // what it left is the context now (a failed one changed nothing)
            if event.error == nil { lastContext = event.after }
        case "notice":
            // said by the host (a resume that began a new conversation): a plain line, never the banner of a failed turn; a change of agent is its own row
            release()
            if let switched = event.switched { rows.append(.switched(id: id, switched)) }
            else if let text = event.shown(event.text, bundle: bundle, locale: locale) { rows.append(.line(id: id, text: text)) }
        default:
            continue
        }
    }
    release()
    if working == false, let last = events.last?.at {
        for index in rows.indices {
            guard case .tools(let id, var run) = rows[index], run.runningSubagents > 0 else { continue }
            for slot in run.subagents.indices where run.subagents[slot].status == .running { run.subagents[slot].stop(at: last) }
            rows[index] = .tools(id: id, run)
        }
    }
    if streaming.isEmpty == false { rows.append(.agent(id: "streaming", text: streaming, inProgress: true)) }
    return rows
}

/// The ids of the subagents the events show running, in the order they started: a start with no end, as the host counts them.
func runningTasks(in events: [ChatEvent]) -> [String] {
    var running: [String] = []
    for event in events where event.kind == "task" {
        guard let task = event.taskId else { continue }
        switch event.state {
        case "started": if running.contains(task) == false { running.append(task) }
        case "completed", "failed", "stopped": running.removeAll { $0 == task }
        default: break
        }
    }
    return running
}

/// The run a turn that failed ended in: the last one of the turn, when the agent had not written an answer after it.
private func markLastRunErred(in rows: inout [FeedRow]) {
    for index in rows.indices.reversed() {
        switch rows[index] {
        case .tools(let id, var group):
            group.erred = true
            rows[index] = .tools(id: id, group)
            return
        case .user, .agent: return
        default: continue
        }
    }
}

/// Puts a call at the end of the run the last row is, or opens a row for it that starts with the thoughts that were waiting.
private func place(_ call: ToolCall, in rows: inout [FeedRow], id: String, held: inout [Thought]) -> (row: Int, call: Int) {
    if case .tools(let group, var run)? = rows.last {
        run.calls.append(call)
        rows[rows.count - 1] = .tools(id: group, run)
        return (rows.count - 1, run.calls.count - 1)
    }
    rows.append(.tools(id: held.first?.id ?? id, ToolGroup(calls: [call], thoughts: held)))
    held = []
    return (rows.count - 1, 0)
}

/// Puts a subagent at the end of the run the last row is, or opens a row for it, as `place` does for a call.
private func place(_ subagent: Subagent, in rows: inout [FeedRow], id: String, held: inout [Thought]) -> (row: Int, index: Int) {
    if case .tools(let group, var run)? = rows.last {
        run.subagents.append(subagent)
        rows[rows.count - 1] = .tools(id: group, run)
        return (rows.count - 1, run.subagents.count - 1)
    }
    rows.append(.tools(id: held.first?.id ?? id, ToolGroup(calls: [], thoughts: held, subagents: [subagent])))
    held = []
    return (rows.count - 1, 0)
}

private func what(_ approval: ChatEvent) -> String { [approval.tool, approval.arg].compactMap { $0 }.joined(separator: " ") }

/// "Allowed pnpm test · Allow once · by you": the verb is from whether the chosen choice allows, the label is the provider's own.
private func decided(_ approval: ChatEvent, choice: String?, answers: [String: String]?, id: String, bundle: Bundle?, locale: Locale) -> FeedRow {
    if let questions = approval.questions, questions.isEmpty == false {
        guard let answers, let chosen = approval.choices?.first(where: { $0.id == choice })?.allow, chosen else {
            return .decided(id: id, text: Copy.chatDecidedSkipped(bundle: bundle, locale: locale), allow: false)
        }
        let parts = questions.compactMap { question in answers[question.question].map { "\(question.header): \($0)" } }
        return .decided(id: id, text: ([Copy.chatDecidedAnswered(bundle: bundle, locale: locale)] + parts).joined(separator: "\n"), allow: true)
    }
    guard let chosen = approval.choices?.first(where: { $0.id == choice }) else {
        return .decided(id: id, text: Copy.chatDecidedAnsweredWhat(what: what(approval), bundle: bundle, locale: locale), allow: false)
    }
    let text = Copy.chatDecidedChoice(verdict: chosen.allow ? .allowed : .declined, what: what(approval), choice: chosen.label, bundle: bundle, locale: locale)
    return .decided(id: id, text: text, allow: chosen.allow)
}
