import Foundation
import Observation

extension ConversationModel {
    func round() async {
        // a round can be asked for from an action while another ends, so each interval has its own id
        let signpost = Signposts.poll.beginInterval("conversation poll", id: Signposts.poll.makeSignpostID())
        let eventsBefore = events.count
        var changed = loaded == false
        defer { Signposts.poll.endInterval("conversation poll", signpost, "\(self.events.count - eventsBefore) new events, changed \(changed)") }
        let sendsBefore = sends
        do {
            var reply: ChatEvents
            var fresh: [ChatEvent]
            repeat {
                reply = try await host.events(sessionId, after: cursor, limit: Self.page)
                // ids only grow (the host reads after the cursor, in order): one already here is never added twice
                fresh = reply.events.filter { $0.id > (events.last?.id ?? 0) }
                // kept as each page comes, so a later page that fails does not lose the cursor's progress
                events += fresh
                if let last = fresh.last(where: { $0.kind == "user" }) { lastUserText = last.text }
                cursor = max(cursor, reply.cursor)
                changed = changed || fresh.isEmpty == false
            // a full page that brought nothing new does not move the cursor: asking again would only get the same page
            } while reply.events.count >= Self.page && fresh.isEmpty == false
            let first = loaded == false
            if hostStops == nil, let listed = try? await host.capabilities() {
                hostStops = listed.contains(.stopTask)
                canStopTask = hostStops == true
                if listed.contains(.switchAgent) {
                    canSwitchAgent = true
                    if let agents = try? await host.agents() { switchTargets = agentChoices(agents) }
                }
                changed = true
            }
            if let facts = reply.facts {
                // the summary of the reply says it, and the session answered: no list is asked
                if let named = facts.agent { agent = named }
                // as the lists said it: a session in the archive is not live and waits for nothing, though the host's `events` say what it has
                // (a session closed, archived and resumed is archived and live)
                live = facts.live && !facts.archived
                archived = facts.archived
                // `events` also answers for a child session, which the list leaves out and so never read as unknown; the app opens no child
                // (every id it has comes from that list), so `known` is always true here
                known = true
                preparingSession = reply.state == .preparing
                background = facts.archived ? [] : facts.background
                baseFolder = facts.baseFolder
            } else {
                try await readSessionFromLists()
            }
            // only an idle session that is not being prepared (a plan that clones has no folder yet) can have lost its folder
            let gone = baseFolder.map { reply.state == .idle && reply.preparation == nil && archived == false && folderExists($0) == false } ?? false
            if folderGone != gone { folderGone = gone }
            settleAsleep(first: first)
            changed = changed || reply.streaming != streaming
            streaming = reply.streaming
            changed = changed || reply.pending != pending
            pending = reply.pending
            if preparation != reply.preparation { preparation = reply.preparation }
            restoring = reply.preparation == .running && reply.state != .preparing
            progress = reply.progress
            loaded = true
            failure = nil
            failures = 0
            options = reply.options
            commands = reply.commands
            if agent.isEmpty == false, agent != savedAgent {
                memory.saveAgent(sessionId, agent)
                savedAgent = agent
            }
            if reply.commands.isEmpty == false, reply.commands != rememberedCommands {
                rememberedCommands = reply.commands
                memory.saveCommands(sessionId, reply.commands)
            }
            if reply.options.isEmpty == false, reply.options != remembered {
                remembered = reply.options
                memory.save(sessionId, reply.options)
            }
            if sends == sendsBefore, let state = reply.state {
                // the feed shows a subagent that never ended as stopped only while the session is not working
                changed = changed || busy != (state != .idle)
                busy = state != .idle
            }
        } catch {
            let message = Self.words(error)
            if failure != message { log("session \(sessionId): \(message)") }
            failure = message
            failures += 1
        }
        let preparing = preparationSteps(events, preparation: preparation, progress: progress, restoring: restoring)
        if preparing != steps { steps = preparing }
        if changed {
            let next = feed()
            if quotaErrorAppeared(from: rows, to: next) { onQuotaError?() }
            rows = next
            openSubagent = openCall.flatMap(work)
            times = Dictionary(events.filter { $0.kind == "user" || $0.kind == "assistant" }.map { ("e\($0.id)", $0.at) }) { $1 }
            if followsOutput && atEnd { scrolls += 1 }
        }
        if busy == false, let next = queued {
            queued = nil
            await deliver(next)
        }
    }
}
