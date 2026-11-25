import Foundation
import Observation

extension ConversationModel {
    /// What a host whose `events` do not say whether the session runs says of it in its lists: the active one first, the archive when it is not there.
    func readSessionFromLists() async throws {
        if let session = try await host.list(archived: false).first(where: { $0.id == sessionId }) {
            agent = session.agent
            live = session.live
            archived = false
            known = true
            preparingSession = session.state == .preparing
            background = session.background
            baseFolder = session.workspace?.base ?? session.folder
        } else if let session = try await host.list(archived: true).first(where: { $0.id == sessionId }) {
            agent = session.agent
            live = false
            archived = true
            known = true
            preparingSession = false
            background = []
        } else {
            live = false
            archived = false
            known = false
            preparingSession = false
            background = []
        }
    }

    func settleAsleep(first: Bool) {
        if live || archived || known == false || preparingSession || waking {
            closedSince = nil
        } else if closedSince == nil {
            closedSince = first ? .distantPast : .now
        }
        let next = closedSince.map { Date.now.timeIntervalSince($0) >= Self.settle } ?? false
        if asleep != next { asleep = next }
    }

    /// Sends the text, resuming the session first when the host's list says it is not live. A refusal is shown and the text goes back
    /// to the box when it came from there or from the queue (`refill`); on success the box is emptied unless the person has typed something else.
    func deliver(_ text: String, refill: Bool = true) async {
        // the project's folder was deleted: nothing is asked of the host, and what was typed stays in the box
        if folderGone {
            refusal = .folderGone
            return
        }
        sends += 1
        waking = true
        asleep = false
        defer { waking = false }
        // the box empties on Enter and not when the host has answered; a refusal puts the text back
        if refill, draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        do {
            try await switchToPendingAgent()
            if try await host.list(archived: false).first(where: { $0.id == sessionId })?.live != true {
                try await host.resume(sessionId)
                await applyWakeOptions()
            }
            // a message that starts with the name of a command the session lists invokes it; the host composes what the provider is told
            if let invoked = invokedCommand(in: text, among: shownCommands) {
                try await host.send(sessionId, invoked.arguments, command: invoked.command.id)
            } else {
                try await host.send(sessionId, text)
            }
        } catch {
            refusal = report(error, "send the message")
            refusedText = text
            if refill, draft.isEmpty { draft = text }
            return
        }
        clearRefusal()
        if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
        sends += 1
        busy = true
        // the loop may be in a long wait of an idle session: the turn that just began is read at the turn's pace from now
        nap.wake()
        await poll()
    }

    /// The choices made while the session was closed, now that its agent runs: the model first, as the reasoning levels depend on it. One
    /// the host refuses is said in words and the rest still go.
    private func applyWakeOptions() async {
        let waiting = wakeOptions.sorted { ($0.key == "model" ? 0 : 1, $0.key) < ($1.key == "model" ? 0 : 1, $1.key) }
        wakeOptions = [:]
        for (option, value) in waiting {
            do {
                try await host.setOption(sessionId, option: option, value: value)
            } catch {
                optionRefusal = report(error, "change the option").text
            }
        }
    }

    func clearRefusal() {
        refusal = nil
        refusedText = nil
    }

    func report(_ error: Error, _ doing: String) -> Refusal {
        let refusal = Self.refusal(error)
        // a refusal is the host answering as it should; anything else is a failure to talk to it
        if case ControlError.remote = error { return refusal }
        log("session \(sessionId): could not \(doing): \(refusal.text)")
        return refusal
    }

    nonisolated static func words(_ error: Error) -> String { refusal(error).text }

    nonisolated static func refusal(_ error: Error) -> Refusal {
        switch error {
        case ControlError.closed: .hostNotAnswering
        case ControlError.remote(let refusal): refusal
        case ControlError.timeout: .hostTookTooLong
        default: .hostNotUnderstood
        }
    }
}
