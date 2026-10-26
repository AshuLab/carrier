import Foundation

// The Repos tab's picker: the repos the engine's gh login can push to (the `availableRepos` request), grouped by owner.
// The app has no GitHub token (ADR 0005); the engine does the read.

public struct AvailableRepo: Decodable, Equatable {
    public var name: String
    public var isPrivate: Bool
    /// ISO 8601; nil when GitHub gave none.
    public var pushedAt: String?

    public init(name: String, isPrivate: Bool = false, pushedAt: String? = nil) {
        self.name = name
        self.isPrivate = isPrivate
        self.pushedAt = pushedAt
    }

    enum CodingKeys: String, CodingKey {
        case name, pushedAt
        case isPrivate = "private"
    }
}

struct AvailableReposReply: Decodable {
    var repos: [AvailableRepo]
    /// absent from an engine that does not list `availableReposPaged`
    var hasMore: Bool?
}

public enum AvailableReposResult: Equatable {
    /// one page, and whether the engine has another
    case repos([AvailableRepo], hasMore: Bool)
    /// no socket to talk to, or the connection died
    case stopped
    /// an engine that does not advertise the request
    case unsupported
    /// the engine answered with an error: gh failed
    case githubError
}

/// Asks the engine at `socketPath` for one page. Blocks (gh can take seconds): call it off the main thread. Names the engine sends
/// that are not `owner/name` are dropped: they could not be written to the config.
public func loadAvailableRepos(socketPath: String, page: Int = 1) -> AvailableReposResult {
    guard let client = ControlClient.connect(path: socketPath, timeout: 20) else { return .stopped }
    defer { client.close() }
    do {
        _ = try client.hello()
        guard let reply = try client.availableRepos(page: page) else { return .unsupported }
        return .repos(reply.repos.filter { isRepoName($0.name) }, hasMore: reply.hasMore)
    } catch ControlError.remote {
        return .githubError
    } catch {
        return .stopped
    }
}

/// What the picker says in place of the list; nil when there is a list to show.
public func availableReposMessage(_ result: AvailableReposResult) -> (title: String, detail: String)? {
    switch result {
    case .repos: nil
    case .stopped: ("Carrier is stopped", "Start Carrier to see your repos.")
    case .unsupported: ("This Carrier cannot list repos", "Update Carrier to see your repos.")
    case .githubError: ("GitHub did not answer", "Check your login with gh auth status.")
    }
}

/// What the picker has loaded: the pages in order, the next one to ask for and whether there is one. A page that fails after the
/// first keeps what is loaded and is `problem`; the next ask retries the same page.
public struct AvailableReposList: Equatable {
    public private(set) var repos: [AvailableRepo] = []
    public private(set) var hasMore = false
    public private(set) var nextPage = 1
    /// why the latest read failed; nil when it worked
    public private(set) var problem: AvailableReposResult?

    public init() {}

    /// The first page failed: nothing to show but the message.
    public var blocked: Bool { nextPage == 1 && problem != nil }

    public mutating func apply(_ result: AvailableReposResult) {
        guard case .repos(let page, let more) = result else { problem = result; return }
        repos += page
        hasMore = more
        nextPage += 1
        problem = nil
    }
}

public struct RepoChoice: Equatable, Identifiable {
    public var name: String
    public var isPrivate: Bool
    /// "pushed 3 d ago", "already watched", "same folder name as X"
    public var detail: String
    public var watched: Bool
    /// not offered: watched, or its folder name is taken
    public var disabled: Bool
    public var id: String { name }
}

public struct RepoGroup: Equatable, Identifiable {
    public var owner: String
    public var choices: [RepoChoice]
    public var id: String { owner }
}

/// The list as the picker shows it: owners in the order the engine's list first reaches them, repos in its order, filtered by
/// `query`. A repo is off when it is watched (`watched`: the tab's draft) or shares a folder name with a watched or selected one.
public func repoGroups(_ available: [AvailableRepo], watched: [String], selected: Set<String>, query: String, now: Date = Date()) -> [RepoGroup] {
    let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
    var order: [String] = []
    var byOwner: [String: [RepoChoice]] = [:]
    for repo in available where needle.isEmpty || repo.name.lowercased().contains(needle) {
        let isWatched = watched.contains { $0.lowercased() == repo.name.lowercased() }
        let taken = selected.contains(repo.name) ? nil : (watched + selected).first { $0.lowercased() != repo.name.lowercased() && repoFolder($0) == repoFolder(repo.name) }
        let detail = isWatched ? "already watched" : taken.map { "same folder name as \($0)" } ?? pushedLine(repo.pushedAt, now: now)
        let owner = String(repo.name.split(separator: "/").first ?? "")
        if byOwner[owner] == nil { order.append(owner) }
        byOwner[owner, default: []].append(RepoChoice(name: repo.name, isPrivate: repo.isPrivate, detail: detail, watched: isWatched, disabled: isWatched || taken != nil))
    }
    return order.map { RepoGroup(owner: $0, choices: byOwner[$0]!) }
}

/// "pushed 3 d ago"; empty when GitHub gave no time.
public func pushedLine(_ iso: String?, now: Date) -> String {
    guard let iso, let date = ISO8601DateFormatter().date(from: iso) else { return "" }
    let seconds = max(0, Int(now.timeIntervalSince(date)))
    let days = seconds / 86_400
    switch seconds {
    case ..<3600: return "pushed just now"
    case ..<86_400: return "pushed \(seconds / 3600) h ago"
    default:
        if days == 1 { return "pushed yesterday" }
        if days < 14 { return "pushed \(days) d ago" }
        if days < 60 { return "pushed \(days / 7) w ago" }
        return "pushed \(days / 30) mo ago"
    }
}
