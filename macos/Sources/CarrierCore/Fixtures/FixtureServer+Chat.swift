import CoreGraphics
import Foundation

extension FixtureServer {
    /// `cloneProject`: a repository the golden branches or the listing know starts cloning and stays at git's progress line, as a long clone would; one it does not know is refused
    /// like a repository the login cannot see; one already cloning is shared; one that is a project of the fixture home is refused as the host does.
    func cloneProject(_ id: Int, _ repo: String, parent: String?) -> Data {
        let key = repo.lowercased()
        let folder = (parent ?? currentProjectsFolderOfFixture) + "/" + repo
        if let running = locked({ chatClones.first { ($0["repo"] as? String)?.lowercased() == key && $0["state"] as? String == "cloning" } }) { return Self.answer(id, running) }
        let listed = chatGithubRepos.values.flatMap { ($0["repos"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String } }
        guard (Array(chatBranches.keys) + listed).contains(where: { $0.lowercased() == key }) else { return Self.refused(id, "github.repoNotFound", "\(repo) was not found, or your GitHub login cannot see it", ["repo": .string(repo)]) }
        let clone: [String: Any] = ["repo": repo, "folder": folder, "state": "cloning", "progress": "Receiving objects: 45%"]
        locked {
            chatClones.removeAll { ($0["repo"] as? String)?.lowercased() == key }
            chatClones.append(clone)
        }
        return Self.answer(id, clone)
    }

    /// `newProject`: the folder and the entry, as the host makes them, without git; refused as the host refuses.
    func newProject(_ id: Int, _ name: String, parent: String?) -> Data {
        if let refusal = projectNameProblem(name) { return Self.refused(id, "project.nameInvalid", refusal.text, ["name": .string(name)]) }
        let folder = (parent ?? currentProjectsFolderOfFixture) + "/local/" + name
        guard FileManager.default.fileExists(atPath: folder) == false else { return Self.refused(id, "project.nameTaken", "\(name) is already a project; choose another name", ["name": .string(name)]) }
        do {
            try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
            try fixtureEditProjects(home: home) { $0.append(["path": folder, "name": (folder as NSString).lastPathComponent, "origin": "created"]) }
        } catch {
            return Self.refused(id, "project.initFailed", "git could not start the project \(name)", ["name": .string(name)])
        }
        return Self.answer(id, ["folder": folder])
    }

    private var currentProjectsFolderOfFixture: String { CarrierPlaces(folder: home).chatProjects }

    func chatReply(to line: Data) -> Data {
        let request = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        if let cmd = request?["cmd"] as? String { locked { chatAsked[cmd, default: 0] += 1 } }
        guard let id = request?["id"] as? Int else { return Self.refused(nil, "request.invalid", "invalid request") }
        switch request?["cmd"] as? String {
        case "agents":
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: chatAgents, as: UTF8.self) + "}")
        case "list":
            let archived = request?["archived"] as? Bool ?? false
            let sessions = locked { chatSessions.filter { ($0["archived"] as? Bool) == archived } }
            guard let body = try? JSONSerialization.data(withJSONObject: ["sessions": sessions], options: .sortedKeys) else { break }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}")
        case "events":
            guard let session = request?["sessionId"] as? String, locked({ chatSessions.contains(where: { $0["id"] as? String == session }) }) else {
                return Self.refused(id, "session.unknown", "unknown session")
            }
            let after = request?["after"] as? Int ?? 0
            let limit = min(max(request?["limit"] as? Int ?? 200, 1), 200)
            lock.lock()
            let conversation = longChat.map { ($0, "") } ?? chatConversations[session] ?? ([], "")
            lock.unlock()
            let page = Array(conversation.0.filter { ($0["id"] as? Int ?? 0) > after }.prefix(limit))
            let reply: [String: Any] = [
                "events": page, "cursor": page.last?["id"] as? Int ?? after, "streaming": conversation.1,
                "approvals": Self.pending(conversation.0), "options": chatOptions[session] ?? [],
                "session": locked {
                    let listed = chatSessions.first { $0["id"] as? String == session }
                    var summary: [String: Any] = ["state": listed?["state"] as? String ?? "idle"]
                    if let preparation = listed?["preparation"] as? String { summary["preparation"] = preparation }
                    // what the real host adds to the summary of `events`, from the row its list gives
                    for key in ["agent", "archived", "live", "background"] { if let value = listed?[key] { summary[key] = value } }
                    return summary
                },
            ]
            guard let body = try? JSONSerialization.data(withJSONObject: reply, options: .sortedKeys) else { break }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}")
        case "workspace", "fetch":
            guard let folder = request?["folder"] as? String else { break }
            if request?["cmd"] as? String == "workspace" {
                return Self.answer(id, chatWorkspaces[folder] ?? ["folder": folder, "git": false, "bare": false, "linkedWorktree": false, "repo": NSNull(), "branch": NSNull(), "defaultBranch": NSNull(), "dirty": 0, "branches": [], "fetchedAt": NSNull()])
            }
            if let fetched = chatFetches[folder] { return Self.answer(id, fetched) }
            let git = chatWorkspaces[folder]?["git"] as? Bool ?? false
            return git ? Self.refused(id, "workspace.fetchFailed", "The fetch of origin failed") : Self.refused(id, "workspace.notGit", "That folder is not a git repository")
        case "githubRepos":
            guard let page = request?["page"] as? Int else { break }
            return chatGithubRepos[String(page)].map { Self.answer(id, $0) } ?? Self.refused(id, "github.noAnswer", "GitHub did not answer; check \"gh auth status\"")
        case "repoBranches":
            guard let repo = request?["repo"] as? String else { break }
            return chatBranches[repo].map { Self.answer(id, $0) } ?? Self.refused(id, "github.repoNotFound", "\(repo) was not found, or your GitHub login cannot see it", ["repo": .string(repo)])
        case "cloneProject":
            guard let repo = request?["repo"] as? String else { break }
            return cloneProject(id, repo, parent: request?["parent"] as? String)
        case "newProject":
            guard let name = request?["name"] as? String else { break }
            return newProject(id, name, parent: request?["parent"] as? String)
        case "projectClones":
            return Self.answer(id, ["clones": locked { chatClones }])
        case "projectWorktrees":
            guard let folder = request?["folder"] as? String else { break }
            var reply = chatProjectWorktrees[(folder as NSString).lastPathComponent] ?? ["main": ["branch": "main"], "worktrees": [Any]()]
            let main = reply["main"] as? [String: Any]
            reply["main"] = ["path": folder, "branch": main?["branch"] ?? NSNull(), "state": main?["state"] ?? "clean"]
            let gone = locked { removedWorktrees }
            reply["worktrees"] = (reply["worktrees"] as? [[String: Any]])?.filter { gone.contains($0["path"] as? String ?? "") == false }
            return Self.answer(id, reply)
        case "projectDisk":
            guard let folders = request?["folders"] as? [String] else { break }
            return Self.answer(id, ["projects": folders.map { folder in
                guard var figure = chatProjectDisk[(folder as NSString).lastPathComponent] else {
                    return ["folder": folder, "bytes": NSNull(), "measuredAt": NSNull(), "parts": [String: Any]()] as [String: Any]
                }
                // the golden file names the project's own folder "main", as the host's answer names it by its real path
                figure["parts"] = (figure["parts"] as? [String: Any] ?? [:]).reduce(into: [String: Any]()) { $0[$1.key == "main" ? folder : $1.key] = $1.value }
                figure["folder"] = folder
                return figure
            }, "measuring": [String]()])
        case "removeProjectWorktree":
            guard let folder = request?["folder"] as? String, let path = request?["path"] as? String else { break }
            let listed = chatProjectWorktrees[(folder as NSString).lastPathComponent]?["worktrees"] as? [[String: Any]] ?? []
            guard let found = listed.first(where: { $0["path"] as? String == path }), locked({ removedWorktrees.contains(path) }) == false else { return Self.refused(id, "worktree.unknown", "That is not a worktree of this project") }
            switch found["state"] as? String {
            case "sessionOpen": return Self.refused(id, "worktree.sessionOpen", "Its session is open")
            case "uncommitted": return Self.refused(id, "worktree.uncommitted", "It has uncommitted changes")
            default:
                locked { _ = removedWorktrees.insert(path) }
                return Self.answer(id, [String: Any]())
            }
        case "cleanProjectWorktrees":
            guard let folder = request?["folder"] as? String else { break }
            let planned = chatProjectCleanup[(folder as NSString).lastPathComponent] ?? ["removed": [Any](), "skipped": [Any]()]
            let gone = locked { removedWorktrees }
            let removed = (planned["removed"] as? [[String: Any]] ?? []).filter { gone.contains($0["path"] as? String ?? "") == false }
            if request?["run"] as? Bool == true { locked { removedWorktrees.formUnion(removed.compactMap { $0["path"] as? String }) } }
            return Self.answer(id, ["removed": removed, "skipped": planned["skipped"] ?? [Any]()])
        case "dismissClone":
            guard let repo = request?["repo"] as? String else { break }
            return Self.answer(id, ["clones": locked {
                chatClones.removeAll { ($0["repo"] as? String)?.lowercased() == repo.lowercased() && $0["state"] as? String == "failed" }
                return chatClones
            }])
        case "providers":
            return Self.answer(id, providersReply())
        case "usage":
            return Self.answer(id, chatUsage)
        case "usageOverride":
            guard let model = request?["model"] as? String, let action = request?["action"] as? String else { break }
            return Self.answer(id, ["model": model, "action": action])
        case "suggestName":
            let names = chatNames["suggestions"] as? [String] ?? []
            guard request?["folder"] is String, names.isEmpty == false else { break }
            return Self.answer(id, ["name": locked { defer { suggested += 1 }; return names[suggested % names.count] }])
        case "checkName":
            guard request?["folder"] is String, let name = request?["name"] as? String else { break }
            return Self.answer(id, nameCheck(name))
        case "open":
            if let plan = request?["plan"] as? [String: Any] { return openPlan(id, plan) }
            return open(id, request ?? [:])
        case "resume":
            // a closed session wakes: the next list says it is live
            guard let session = request?["sessionId"] as? String else { break }
            let found = locked { () -> Bool in
                guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return false }
                chatSessions[at]["live"] = true
                return true
            }
            return found ? Self.answer(id, [String: Any]()) : Self.refused(id, "session.unknown", "unknown session")
        case "switchAgent":
            guard let session = request?["sessionId"] as? String, let agent = request?["agent"] as? String else { break }
            return switchAgent(id, session, to: agent)
        case "send":
            guard let session = request?["sessionId"] as? String, let text = request?["text"] as? String else { break }
            // a session whose list entry says `fixtureRefuseSend` refuses every send with those words (a provider that is not signed in)
            if let refusal = locked({ chatSessions.first { $0["id"] as? String == session }?["fixtureRefuseSend"] as? String }) { return Self.refused(id, "agent.notLoggedIn", refusal) }
            let found = locked { () -> Bool in
                guard chatSessions.contains(where: { $0["id"] as? String == session }) else { return false }
                let events = chatConversations[session]?.events ?? []
                chatConversations[session, default: ([], "")].events = events + [["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "user", "text": text]]
                return true
            }
            return found ? Self.answer(id, [String: Any]()) : Self.refused(id, "session.unknown", "unknown session")
        case "answer":
            guard let session = request?["sessionId"] as? String, let approval = request?["approvalId"] as? String, let choice = request?["choiceId"] as? String else { break }
            lock.lock()
            defer { lock.unlock() }
            var events = chatConversations[session]?.events ?? []
            guard let asked = Self.pending(events).first(where: { $0["approvalId"] as? String == approval }) else {
                return Self.refused(id, "session.approval.notPending", "That approval is not pending: it is unknown or was already answered")
            }
            guard (asked["choices"] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == choice }) else {
                return Self.refused(id, "session.approval.choiceUnknown", "That is not one of the choices")
            }
            var answered: [String: Any] = ["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "approval_answered", "approvalId": approval, "choiceId": choice]
            if let answers = request?["answers"] as? [String: String] { answered["answers"] = answers }
            events.append(answered)
            chatConversations[session]?.events = events
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "setOption":
            guard let session = request?["sessionId"] as? String, let option = request?["option"] as? String, let value = request?["value"] as? String,
                let at = chatOptions[session]?.firstIndex(where: { $0["id"] as? String == option })
            else { return Self.refused(id, "session.option.unknown", "This agent has no such option", ["option": .string(request?["option"] as? String ?? "")]) }
            let listed = (chatOptions[session]?[at]["values"] as? [[String: Any]])?.contains { $0["id"] as? String == value } ?? false
            guard listed else { return Self.refused(id, "session.option.valueUnknown", "The agent does not offer that value for \(option)", ["option": .string(option), "value": .string(value)]) }
            chatOptions[session]?[at]["current"] = value
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "stopTask":
            guard let session = request?["sessionId"] as? String, let task = request?["taskId"] as? String else { break }
            lock.lock()
            defer { lock.unlock() }
            // a task the session waits for in the background: as the host does, it is gone from the session's row
            if let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }), var tasks = chatSessions[at]["background"] as? [[String: Any]],
                let found = tasks.firstIndex(where: { $0["id"] as? String == task }) {
                tasks.remove(at: found)
                chatSessions[at]["background"] = tasks
                return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
            }
            // else a running subagent: the host answers at once and the agent says the task stopped, here the event comes with the answer
            var events = chatConversations[session]?.events ?? []
            let own = events.filter { $0["kind"] as? String == "task" && $0["taskId"] as? String == task }
            let ended = own.contains { ["completed", "failed", "stopped"].contains($0["state"] as? String ?? "") }
            guard let started = own.first(where: { $0["state"] as? String == "started" }), ended == false else {
                return Self.refused(id, "session.task.notRunning", "That task is not running")
            }
            events.append(["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "task", "callId": started["callId"] as Any, "taskId": task, "state": "stopped"])
            chatConversations[session]?.events = events
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "interrupt":
            guard let session = request?["sessionId"] as? String else { break }
            // with no turn running it stops what the session waits for in the background
            locked { if let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) { chatSessions[at]["background"] = [] as [[String: Any]] } }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "regenerateTitle":
            guard let session = request?["sessionId"] as? String else { break }
            // a session whose list entry says `fixtureRefuseTitle` refuses with those words (no text generator chosen); any other gets a made-up title
            return locked {
                guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return Self.refused(id, "session.unknown", "There is no such session") }
                if let refusal = chatSessions[at]["fixtureRefuseTitle"] as? String { return Self.refused(id, "title.noGenerator", refusal) }
                regeneratedSessionIds.insert(session)
                chatSessions[at]["title"] = "Regenerated title"
                return Self.answer(id, ["title": "Regenerated title"])
            }
        case "regenerateTitles":
            let whole = (try? ProvidersFile(folder: home).read()).flatMap { $0 }
                .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            let chosen = whole?["textGenerator"] as? String
            let declared = (whole?["textGenerators"] as? [String: Any])?[chosen ?? ""] != nil
            guard chosen != nil, declared else {
                return Self.refused(id, "title.noGenerator", "Could not write titles: no text generator is chosen; choose one in Providers")
            }
            return locked {
                var started = 0
                for index in chatSessions.indices {
                    guard chatSessions[index]["parentSessionId"] as? String == nil,
                        chatSessions[index]["fixtureRefuseTitle"] == nil,
                        let sessionId = chatSessions[index]["id"] as? String,
                        regeneratedSessionIds.contains(sessionId) == false
                    else { continue }
                    regeneratedSessionIds.insert(sessionId)
                    chatSessions[index]["title"] = "Regenerated title"
                    started += 1
                }
                return Self.answer(id, ["started": started])
            }
        case "editChatSettings":
            guard let changes = request?["changes"] as? [String: Any] else { break }
            return editChatSettings(id, changes)
        case "setAccounts", "addAccount", "editAccount", "removeAccount", "setTextGenerator":
            switch fixtureProvidersChange(request ?? [:], home: home) {
            case .data(let data): return Self.answer(id, data)
            case .refused(let reason): return Self.refused(id, reason.code ?? "request.invalid", reason.text, reason.params)
            }
        case "addProject", "removeProject", "editProject", "moveProject", "editProjectIcon", "editProjectDefaults", "editProjectTags", "setProjectActions", "setProjectsFolder":
            guard let cmd = request?["cmd"] as? String, let request, let change = ProjectsChange(cmd: cmd, request: request) else { break }
            let (data, refusal) = applyProjectsChange(change, home: home)
            if let refusal { return Self.refused(id, refusal.code ?? "request.internal", refusal.text, refusal.params) }
            return Self.answer(id, data ?? [:])
        case "archive", "delete":
            let verb = request?["cmd"] as? String ?? ""
            guard let session = request?["sessionId"] as? String, let archived = verb == "delete" ? false : request?["archived"] as? Bool else { break }
            let refusal: String? = locked {
                guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return "unknown session" }
                // as the host does: a session that is working or waiting for an approval is not archived or deleted
                let state = chatSessions[at]["state"] as? String
                if verb == "delete" || archived, state != "idle" {
                    return "This session is \(state == "working" ? "working" : "waiting for an approval"); interrupt or close it first, then \(verb) it"
                }
                if verb == "delete" { chatSessions.remove(at: at) } else { chatSessions[at]["archived"] = archived }
                return nil
            }
            if let refusal { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"\(refusal)\"}") }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":{}}")
        case "deletePreview":
            guard let asked = request?["sessionIds"] as? [String] else { break }
            let listed = locked { Set(chatSessions.compactMap { $0["id"] as? String }) }
            // as the host does: one unknown id refuses the whole request
            guard asked.allSatisfy(listed.contains) else { return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"There is no such session\"}") }
            let sessions = asked.map { ["sessionId": $0, "worktree": chatWorktrees[$0] ?? NSNull()] as [String: Any] }
            guard let body = try? JSONSerialization.data(withJSONObject: ["sessions": sessions], options: .sortedKeys) else { break }
            return Self.line("{\"id\":\(id),\"ok\":true,\"data\":" + String(decoding: body, as: UTF8.self) + "}")
        default: break
        }
        return Self.line("{\"id\":\(id),\"ok\":false,\"error\":\"unknown request\"}")
    }
}
