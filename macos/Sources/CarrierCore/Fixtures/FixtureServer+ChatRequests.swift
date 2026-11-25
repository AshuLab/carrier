import CoreGraphics
import Foundation

extension FixtureServer {
    /// `editChatSettings` as the host answers it: the scratch `chat.json` read again, each key set (null removes it), the four keys checked as the host's schema does, and written only when
    /// all hold; the reply is the keys as the file now has them. A file that is not a JSON object is refused and left as it was.
    func editChatSettings(_ id: Int, _ changes: [String: Any]) -> Data {
        let url = URL(fileURLWithPath: CarrierPlaces(folder: home).chatConfig)
        var file: [String: Any] = [:]
        if let data = try? Data(contentsOf: url) {
            guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return Self.refused(id, "config.problem", "chat.json is not a JSON object, so it was not changed", ["path": "(file)", "problem": "notAnObject"])
            }
            file = object
        }
        for (key, value) in changes { file[key] = value is NSNull ? nil : value }
        func refusal(_ path: String, _ problem: String, _ words: String) -> Data {
            Self.refused(id, "config.problem", "\(path): \(words)", ["path": .string(path), "problem": .string(problem)])
        }
        /// the days of an age: nil for "never" or a key that is not there, and whether the value is one the schema takes
        func age(_ key: String) -> (days: Int?, valid: Bool) {
            guard let value = file[key], value as? String != "never" else { return (nil, true) }
            guard let days = value as? Int, days > 0 else { return (nil, false) }
            return (days, true)
        }
        let (archive, delete) = (age("archiveAfterDays"), age("deleteAfterDays"))
        guard archive.valid else { return refusal("archiveAfterDays", "too_small", "Too small: expected number to be >0") }
        guard delete.valid else { return refusal("deleteAfterDays", "too_small", "Too small: expected number to be >0") }
        if let start = file["worktreeStart"], ["remote", "local"].contains(start as? String ?? "") == false { return refusal("worktreeStart", "invalid_value", "Invalid option: expected one of \"remote\"|\"local\"") }
        if let idle = file["idleCloseMinutes"], [10, 30, 60].contains(idle as? Int ?? 0) == false { return refusal("idleCloseMinutes", "invalid_union", "must be 10, 30 or 60 (minutes)") }
        if let archive = archive.days, let delete = delete.days, delete <= archive { return refusal("deleteAfterDays", "custom", "must be greater than archiveAfterDays") }
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), (try? data.write(to: url, options: .atomic)) != nil else {
            return Self.refused(id, "request.internal", "internal error")
        }
        return Self.answer(id, ["saved": changes.keys.reduce(into: [String: Any]()) { $0[$1] = file[$1] }])
    }

    /// The golden check of a worktree name: free unless `chat-names.json` says why not.
    func nameCheck(_ name: String) -> [String: Any] {
        (chatNames["checks"] as? [String: [String: Any]])?[name] ?? chatNames["free"] as? [String: Any] ?? ["valid": true, "free": true]
    }

    /// `open`: a session in memory, in a worktree of the folder when asked; refused as the host does. A plan opens the same session with its
    /// text already sent and every step done at once.
    func openPlan(_ id: Int, _ plan: [String: Any]) -> Data {
        let place = plan["workspace"] as? [String: Any]
        // a repository is cloned by the host under its projects folder, which the fixture only names
        let folder = place?["folder"] as? String ?? (place?["repo"] as? String).map { "/Users/dev/projects/\($0)" }
        guard let folder, let text = plan["text"] as? String else { return Self.refused(id, "request.invalid", "invalid request") }
        var request: [String: Any] = ["agent": plan["agent"] as Any, "folder": folder]
        if var from = plan["branch"] as? String {
            // as the host does: a remote start of a branch the repository lists as `origin/<name>` is cut from that ref
            let listed = (chatWorkspaces[folder]?["branches"] as? [[String: Any]])?.compactMap { $0["name"] as? String } ?? []
            if (plan["worktree"] as? [String: Any])?["startFrom"] as? String == "remote", from.hasPrefix("origin/") == false, listed.contains("origin/\(from)") { from = "origin/\(from)" }
            request["worktree"] = ["from": from, "name": (plan["worktree"] as? [String: Any])?["name"] as Any].compactMapValues { $0 is NSNull ? nil : $0 }
        }
        let opened = open(id, request)
        guard let reply = (try? JSONSerialization.jsonObject(with: opened.dropLast())) as? [String: Any], reply["ok"] as? Bool == true,
            let session = (reply["data"] as? [String: Any])?["session"] as? [String: Any], let sessionId = session["id"] as? String else { return opened }
        let now = Int(Date().timeIntervalSince1970 * 1000)
        locked {
            chatConversations[sessionId, default: ([], "")].events = ["agent", "message"].enumerated().map { at, step in
                ["id": at + 1, "at": now, "kind": "step", "step": step, "status": "done"]
            } + [["id": 3, "at": now, "kind": "user", "text": text]]
        }
        return opened
    }

    /// As the host does: an idle session takes another listed agent and gets the notice of the switch; a working or waiting one, the agent it has and one that is not listed are refused.
    func switchAgent(_ id: Int, _ session: String, to agent: String) -> Data {
        guard let chosen = ((try? JSONSerialization.jsonObject(with: chatAgents)) as? [[String: Any]])?.first(where: { $0["name"] as? String == agent }) else {
            return Self.refused(id, "agent.unknown", "There is no chat agent named \"\(agent)\"", ["agent": .string(agent)])
        }
        return locked {
            guard let at = chatSessions.firstIndex(where: { $0["id"] as? String == session }) else { return Self.refused(id, "session.unknown", "There is no such session") }
            let from = chatSessions[at]["agent"] as? String ?? ""
            let state = chatSessions[at]["state"] as? String
            if state != "idle" { return Self.refused(id, "session.switchAgent.busy", "This session is \(state == "working" ? "working" : "waiting for an approval"); interrupt it or wait, then switch its agent", ["state": .string(state ?? "")]) }
            if from == agent { return Self.refused(id, "session.switchAgent.same", "This session already has the agent \"\(agent)\"", ["agent": .string(agent)]) }
            if chosen["found"] as? Bool == false { return Self.refused(id, "agent.notFound", "The agent \"\(agent)\" is not found on this machine", ["agent": .string(agent)]) }
            chatSessions[at]["agent"] = agent
            chatSessions[at]["harness"] = chosen["harness"] as? String ?? agent
            chatSessions[at]["live"] = true
            let events = chatConversations[session]?.events ?? []
            let notice: [String: Any] = ["id": (events.last?["id"] as? Int ?? 0) + 1, "at": Int(Date().timeIntervalSince1970 * 1000), "kind": "notice", "text": "The agent changed from \(from) to \(agent).", "switched": ["from": from, "to": agent]]
            chatConversations[session, default: ([], "")].events = events + [notice]
            var summary = chatSessions[at]
            for key in ["live", "kept", "deleteAt", "lastMessage", "turns", "model"] { summary[key] = nil }
            return Self.answer(id, ["session": summary, "options": [Any]()])
        }
    }

    func open(_ id: Int, _ request: [String: Any]) -> Data {
        guard let agent = request["agent"] as? String, let folder = request["folder"] as? String else { return Self.refused(id, "request.invalid", "invalid request") }
        guard let chosen = ((try? JSONSerialization.jsonObject(with: chatAgents)) as? [[String: Any]])?.first(where: { $0["name"] as? String == agent }) else {
            return Self.refused(id, "agent.unknown", "There is no chat agent named \"\(agent)\"", ["agent": .string(agent)])
        }
        var session: [String: Any] = [
            "id": UUID().uuidString.lowercased(), "agent": agent, "harness": chosen["harness"] as? String ?? agent, "folder": folder, "workspace": ["kind": "folder"],
            "state": "idle", "createdAt": Int(Date().timeIntervalSince1970 * 1000), "lastActiveAt": Int(Date().timeIntervalSince1970 * 1000), "archived": false, "live": true,
        ]
        if let worktree = request["worktree"] as? [String: Any] {
            guard let info = chatWorkspaces[folder], info["git"] as? Bool == true, info["bare"] as? Bool != true else { return Self.refused(id, "worktree.notGit", "Worktrees need a git repository") }
            let from = worktree["from"] as? String ?? ""
            guard (info["branches"] as? [[String: Any]])?.contains(where: { $0["name"] as? String == from }) == true else {
                return Self.refused(id, "worktree.startNotListed", "The branch to start from is not one this repository lists")
            }
            let names = chatNames["suggestions"] as? [String] ?? []
            let name = worktree["name"] as? String ?? names.first ?? "worktree"
            let check = nameCheck(name)
            guard check["valid"] as? Bool == true, check["free"] as? Bool == true else { return Self.refused(id, check["code"] as? String ?? "request.invalid", check["reason"] as? String ?? "That name cannot be used") }
            let path = "/Users/dev/.carrier/chat/worktrees/local/\(URL(fileURLWithPath: folder).lastPathComponent)/\(name)"
            session["folder"] = path
            session["workspace"] = ["kind": "worktree", "branch": "carrier/\(name)", "from": from, "base": folder, "path": path]
        }
        locked { chatSessions.insert(session, at: 0) }
        return Self.answer(id, ["session": session, "options": [Any]()])
    }

    /// The golden `providers` reply as `<home>/providers.json` leaves it, so an Add, an edit or a Remove made in the app shows in the page as it
    /// would against a real host: an account of the file is listed (what the golden reply knows of its name, else what this Mac has of its
    /// harness) with the file's display name, binary, folder; a harness the file gives no account is "found, not added".
    func providersReply() -> [String: Any] {
        var reply = chatProviders
        let whole = (try? ProvidersFile(folder: home).read()).flatMap { $0 }
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let file = whole?["providers"] as? [String: [String: Any]] ?? [:]
        // the generator in use, as the host reads it: the entry `textGenerator` names
        reply["textGenerator"] = (whole?["textGenerator"] as? String).flatMap { name in
            (whole?["textGenerators"] as? [String: [String: Any]])?[name].map { ["name": name].merging($0) { $1 } }
        }
        let golden = reply["accounts"] as? [[String: Any]] ?? []
        let unadded = reply["unadded"] as? [[String: Any]] ?? []
        // what this Mac has of each harness
        var seen: [String: [String: Any]] = [:]
        for entry in golden + unadded {
            guard let harness = entry["harness"] as? String, seen[harness] == nil else { continue }
            seen[harness] = ["path": entry["path"] ?? "", "version": entry["version"] as Any]
        }
        // the golden reply's accounts keep their order, those the app added follow by name
        let goldenNames = golden.compactMap { $0["name"] as? String }
        let order = goldenNames.filter { file[$0] != nil } + file.keys.filter { goldenNames.contains($0) == false }.sorted()
        reply["accounts"] = order.compactMap { name -> [String: Any]? in
            guard let account = file[name], let harness = account["harness"] as? String else { return nil }
            var entry = golden.first { $0["name"] as? String == name }
                ?? ["name": name, "harness": harness, "found": seen[harness] != nil, "path": seen[harness]?["path"] ?? "", "state": "unknown"]
            if entry["version"] == nil, let version = seen[harness]?["version"] as? String { entry["version"] = version }
            for key in ["displayName", "command", "configDir"] { entry[key] = account[key] }
            return entry
        }
        let taken = Set(file.values.compactMap { $0["harness"] as? String })
        reply["unadded"] = seen.keys.sorted().filter { taken.contains($0) == false }.map { harness in
            var entry: [String: Any] = ["harness": harness, "path": seen[harness]?["path"] ?? ""]
            if let version = seen[harness]?["version"] as? String { entry["version"] = version }
            return entry
        }
        return reply
    }
}
