import Foundation

// The requests that exist only when the engine advertises them in its hello. Each returns nil, sending nothing, when the
// capability is missing. An error reply or a reply that does not decode marks the capability unavailable until the next hello
// (a newer engine answering something this app cannot read is treated as having none of it); a dead connection does not.
extension ControlClient {
    public func sessions(repo: String, issue: Int) throws -> SessionsReply? {
        try ask(.sessions, "sessions", try epicFields(repo, issue))
    }

    public func events(executionId: String, after: Int = 0, limit: Int = 200) throws -> EventsReply? {
        guard (1...200).contains(limit), after >= 0 else { throw ControlError.remote("not a valid range") }
        return try ask(.events, "events", ",\"executionId\":\"\(try uuid(executionId))\",\"after\":\(after),\"limit\":\(limit)")
    }

    public func epic(repo: String, issue: Int) throws -> EpicReply? {
        try ask(.epic, "epic", try epicFields(repo, issue))
    }

    public func files(repo: String, issue: Int, executionId: String? = nil) throws -> FilesReply? {
        let session = try executionId.map { ",\"executionId\":\"\(try uuid($0))\"" } ?? ""
        return try ask(.files, "files", try epicFields(repo, issue) + session)
    }

    /// The edited fragments of one file of a card (`section` is the card's id in the `files` reply). nil when this engine cannot be asked.
    /// A refusal (`unknown file`, a git that did not answer) is about that one file and leaves the capability alone.
    public func fileDiff(repo: String, issue: Int, section: String, path: String) throws -> FileDiffReply? {
        guard (1...100).contains(section.utf16.count), (1...500).contains(path.utf16.count) else { throw ControlError.remote("not a valid file") }
        let quoted = { (value: String) in String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
        return try ask(.fileDiff, "fileDiff", keepOnRefusal: true, try epicFields(repo, issue) + ",\"section\":\(try quoted(section)),\"path\":\(try quoted(path))")
    }

    /// One page of the repos the engine's gh login can push to, for the Repos tab's picker. nil when this engine cannot list them.
    /// An engine without `availableReposPaged` refuses `page`: it is asked for none, answers its one list, and has no more.
    public func availableRepos(page: Int = 1) throws -> (repos: [AvailableRepo], hasMore: Bool)? {
        let paged = capabilities.contains(.availableReposPaged)
        guard paged || page == 1 else { return nil }
        guard let reply = try ask(.availableRepos, "availableRepos", paged ? ",\"page\":\(page)" : "") as AvailableReposReply? else { return nil }
        return (reply.repos, paged && reply.hasMore == true)
    }

    /// Asks the engine to put a stopped epic back in the queue; it answers when the epic has started again. false, with nothing sent,
    /// when this engine cannot be asked. A refusal throws `.remote(reason)` and leaves the capability alone: it says nothing about the engine.
    public func resumeEpic(repo: String, issue: Int) throws -> Bool {
        try request("resumeEpic", requires: .resumeEpic, fields: try epicFields(repo, issue)) != nil
    }

    private func ask<T: Decodable>(_ capability: Capability, _ command: String, keepOnRefusal: Bool = false, _ fields: String) throws -> T? {
        guard capabilities.contains(capability) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: request(command, fields: fields))
        } catch let error as ControlError {
            if case .remote = error, keepOnRefusal == false { capabilities.remove(capability) }
            throw error
        } catch {
            capabilities.remove(capability)
            throw ControlError.badLine
        }
    }

    /// Only checked values go on the wire, the same rules as the engine's schema.
    private func epicFields(_ repo: String, _ issue: Int) throws -> String {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = repo.utf8.count <= 200 && repo.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-/".contains($0)) }
        guard allowed, parts.count == 2, parts.allSatisfy({ $0.isEmpty == false && $0 != "." && $0 != ".." }), issue > 0 else {
            throw ControlError.remote("not a valid epic")
        }
        return ",\"repo\":\"\(repo)\",\"issue\":\(issue)"
    }

    private func uuid(_ value: String) throws -> String {
        guard let id = UUID(uuidString: value)?.uuidString.lowercased() else { throw ControlError.remote("not a valid execution id") }
        return id
    }
}
