import Foundation

/// The reply of `open`: only the new session's id is read.
struct OpenedReply: Decodable {
    struct Session: Decodable { let id: String }
    let session: Session
}

/// The reply of `cancelPreparation`: the plan as the host stored it, or null when the session stays (a restore of a worktree).
struct CancelledReply: Decodable {
    struct Stored: Decodable {
        struct Workspace: Decodable {
            let kind: String
            let folder: String?
            let repo: String?
            let name: String?
        }
        struct Worktree: Decodable { let name: String?; let startFrom: String? }
        let workspace: Workspace
        let agent: String
        let text: String
        let options: [String: String]?
        let branch: String?
        let worktree: Worktree?

        /// A worktree is cut from the branch, so the one field serves both, as the plan's wire has it.
        var plan: SessionPlan {
            get throws {
                let place: PlanWorkspace
                switch (workspace.kind, workspace.folder, workspace.repo, workspace.name) {
                case ("folder", let folder?, _, _): place = .folder(folder)
                case ("repo", _, let repo?, _): place = .repo(repo)
                case ("project", _, _, let name?): place = .newProject(name)
                default: throw ControlError.badLine
                }
                let cut = worktree.flatMap { wanted in branch.map { WorktreeRequest(from: $0, name: wanted.name, startFrom: wanted.startFrom.flatMap(WorktreeStart.init(rawValue:))) } }
                return SessionPlan(agent: agent, workspace: place, branch: worktree == nil ? branch : nil, worktree: cut, options: options ?? [:], text: text)
            }
        }
    }
    let plan: Stored?
}

struct SuggestedName: Decodable { let name: String }

/// A reply whose content the app does not read: any JSON will do.
struct AnyReply: Decodable { init(from decoder: Decoder) throws {} }

struct DeletePreviewReply: Decodable { let sessions: [SessionDeletePreview] }

struct ChatSessionsReply: Decodable { let sessions: [ChatSession] }

/// The options and the commands of each session as the host last sent them, with its name for that version (`listsRev`): the one thing of a
/// reply that is most of its bytes and almost never changes. A reference, so every copy of the host that holds it shares what was kept.
final class ListsMemory: @unchecked Sendable {
    struct Kept { let rev: String; let options: [ChatOption]; let commands: [ChatCommand] }

    private let lock = NSLock()
    private var kept: [String: Kept] = [:]

    func kept(_ session: String) -> Kept? { lock.withLock { kept[session] } }

    /// The reply with its lists: the ones that came, kept for the next ask, or the ones kept when the host said they had not changed.
    /// A name that is not plain hex is not kept (it goes into the next request as it is), and a host that gives none is asked in full.
    func filled(_ reply: ChatEvents, for session: String, kept before: Kept?) -> ChatEvents {
        if reply.listsUnchanged {
            // nothing was kept to send back, so the host had no reason to say it: what it left out is not an empty list to keep
            guard let before else { return reply }
            return reply.with(options: before.options, commands: before.commands)
        }
        lock.withLock {
            if let rev = reply.listsRev, rev.isEmpty == false, rev.count <= 64, rev.allSatisfy(\.isHexDigit) {
                kept[session] = Kept(rev: rev, options: reply.options, commands: reply.commands)
            } else {
                kept[session] = nil
            }
        }
        return reply
    }
}
