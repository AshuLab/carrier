import Foundation

// The list of steps at the top of a conversation while the host prepares a session from its plan (docs/adr/0018): each step the host
// recorded as a `step` event, with where it stands and a line in words. The list ends when the agent answers.

/// A row of the list: one step, as the last of its events left it.
public struct StepRow: Equatable, Identifiable {
    public enum Status: String { case running, done, failed }

    public let step: String
    public let status: Status
    /// What the step is doing or did, in words.
    public let line: String
    /// Why a failed step failed, in the host's words.
    public let reason: String?
    /// While a clone runs: the last line of git's own progress; while an action runs, the last line it wrote.
    public let progress: String?
    /// The name of the project's action this row is (the step is `action`), and the moment it runs at: each action is a row of its own.
    public var action: String?
    public var when: String?
    /// The row's own icon, beside its line: an action is a command.
    public var icon: AppIcon? { step == "action" ? .terminal : nil }

    public var id: String { [step, when, action].compactMap { $0 }.joined(separator: ":") }
}

/// The rows the session's `step` events make, in the order the steps first appeared. Nothing once the session is not being prepared
/// (`preparation` is nil: the agent answered, or the host does not prepare sessions), so the list ends with the answer; a failed
/// preparation keeps its list, with the reason on the step that failed. `progress` goes on the step that is running.
/// `restoring`: the session exists and its worktree folder is coming back, whose steps are the `worktree` one that opens a restore and the project's actions; the log also
/// holds the steps of the original preparation and of the agent's start, so only the `worktree` and `action` steps that end it are the restore's, from the latest `worktree`
/// one: restores one after another each begin with their own, and a restore that goes on after it stopped keeps the first try's, so its finished actions still show.
public func preparationSteps(
    _ events: [ChatEvent], preparation: ChatSession.Preparation?, progress: String? = nil, restoring: Bool = false, bundle: Bundle? = nil, locale: Locale = .current
) -> [StepRow] {
    guard preparation != nil else { return [] }
    var events = events
    if restoring {
        let steps = events.filter { $0.kind == "step" }
        let run = steps.reversed().prefix { $0.step == "action" || $0.step == "worktree" }
        let first = run.first { $0.step == "worktree" }?.id ?? run.last?.id ?? Int.max
        events = events.filter { $0.id >= first }
    }
    var order: [StepRow] = []
    var latest: [String: (status: StepRow.Status, detail: String?)] = [:]
    for event in events where event.kind == "step" {
        guard let step = event.step, let status = event.status.flatMap(StepRow.Status.init(rawValue:)) else { continue }
        let key = StepRow(step: step, status: status, line: "", reason: nil, progress: nil, action: event.action, when: event.when)
        if latest[key.id] == nil { order.append(key) }
        latest[key.id] = (status, event.shown(event.detail))
    }
    return order.compactMap { key in
        guard let now = latest[key.id] else { return nil }
        return StepRow(
            step: key.step, status: now.status, line: stepLine(key.step, now.status, action: key.action, bundle: bundle, locale: locale), reason: now.status == .failed ? now.detail : nil,
            progress: now.status == .running ? progress : nil, action: key.action, when: key.when
        )
    }
}

private func stepLine(_ step: String, _ status: StepRow.Status, action: String?, bundle: Bundle?, locale: Locale) -> String {
    let b = bundle, l = locale
    let words: (running: String, done: String, failed: String) = switch step {
    case "clone": (Copy.epicsStepCloneRunning(bundle: b, locale: l), Copy.epicsStepCloneDone(bundle: b, locale: l), Copy.epicsStepCloneFailed(bundle: b, locale: l))
    case "fetch": (Copy.epicsStepFetchRunning(bundle: b, locale: l), Copy.epicsStepFetchDone(bundle: b, locale: l), Copy.epicsStepFetchFailed(bundle: b, locale: l))
    case "project": (Copy.epicsStepProjectRunning(bundle: b, locale: l), Copy.epicsStepProjectDone(bundle: b, locale: l), Copy.epicsStepProjectFailed(bundle: b, locale: l))
    case "worktree": (Copy.epicsStepWorktreeRunning(bundle: b, locale: l), Copy.epicsStepWorktreeDone(bundle: b, locale: l), Copy.epicsStepWorktreeFailed(bundle: b, locale: l))
    case "checkout": (Copy.epicsStepCheckoutRunning(bundle: b, locale: l), Copy.epicsStepCheckoutDone(bundle: b, locale: l), Copy.epicsStepCheckoutFailed(bundle: b, locale: l))
    case "action":
        if let action {
            (Copy.epicsStepActionRunning(name: action, bundle: b, locale: l), Copy.epicsStepActionDone(name: action, bundle: b, locale: l), Copy.epicsStepActionFailed(name: action, bundle: b, locale: l))
        } else {
            (Copy.epicsStepAnActionRunning(bundle: b, locale: l), Copy.epicsStepAnActionDone(bundle: b, locale: l), Copy.epicsStepAnActionFailed(bundle: b, locale: l))
        }
    case "agent": (Copy.epicsStepAgentRunning(bundle: b, locale: l), Copy.epicsStepAgentDone(bundle: b, locale: l), Copy.epicsStepAgentFailed(bundle: b, locale: l))
    case "message": (Copy.epicsStepMessageRunning(bundle: b, locale: l), Copy.epicsStepMessageDone(bundle: b, locale: l), Copy.epicsStepMessageFailed(bundle: b, locale: l))
    default: (Copy.epicsStepOtherRunning(step: step, bundle: b, locale: l), Copy.epicsStepOtherDone(step: step, bundle: b, locale: l), Copy.epicsStepOtherFailed(step: step, bundle: b, locale: l))
    }
    return switch status {
    case .running: words.running
    case .done: words.done
    case .failed: words.failed
    }
}

/// A line of the card's list: a step the host recorded, or one that comes after them and has not started (`status` nil).
public struct OutlineItem: Equatable, Identifiable {
    public let step: String
    public let status: StepRow.Status?
    public let line: String
    public let reason: String?
    public let progress: String?
    public var icon: AppIcon?
    /// A row's own id, which tells the actions of one preparation apart; the step's name for a step that comes once.
    public var id: String

    public init(step: String, status: StepRow.Status?, line: String, reason: String?, progress: String?, icon: AppIcon? = nil, id: String? = nil) {
        (self.step, self.status, self.line, self.reason, self.progress, self.icon, self.id) = (step, status, line, reason, progress, icon, id ?? step)
    }
}

/// The steps the host recorded and, after them, the two every preparation ends with (the agent starts, the message is sent) while they
/// have not started, so the list shows where it is going and not only where it is. ponytail: a worktree that has not started is not
/// known to be coming, so it joins the list when it does.
public func preparationOutline(_ rows: [StepRow], bundle: Bundle? = nil, locale: Locale = .current) -> [OutlineItem] {
    var items = rows.map { OutlineItem(step: $0.step, status: $0.status, line: $0.line, reason: $0.reason, progress: $0.progress, icon: $0.icon, id: $0.id) }
    let sent = rows.contains { $0.step == "message" }
    for (step, line) in [("agent", Copy.epicsStepAgentNext(bundle: bundle, locale: locale)), ("message", Copy.epicsStepMessageNext(bundle: bundle, locale: locale))] where rows.contains(where: { $0.step == step }) == false {
        if step == "agent" && sent { continue }
        items.append(OutlineItem(step: step, status: nil, line: line, reason: nil, progress: nil))
    }
    return items
}

/// How far a clone is, from git's progress line ("Receiving objects:  63% (1234/1960)"); nil when the line has no percentage.
public func progressFraction(_ line: String?) -> Double? {
    guard let line, let range = line.range(of: #"\d{1,3}(?=%)"#, options: .regularExpression), let percent = Double(line[range]), percent <= 100 else { return nil }
    return percent / 100
}
