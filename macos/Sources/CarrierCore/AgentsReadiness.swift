import Foundation

// What the top of the Agents page says (docs/macos/settings-carrier.md): whether the roles of an epic are set up, and what is in the way; and what
// each role runs, stage by stage. Decided here from what the page reads, so it can be tested; the views only draw it.

/// One thing in the way of a role: said with the role's name in front.
public struct RoleProblem: Equatable, Identifiable {
    public let role: AgentRole
    public let text: String
    /// A role can have several, so the line is the id, not the role.
    public var id: String { line }
    public var line: String { "\(role.title): \(text)" }
}

public struct AgentsReadiness: Equatable {
    public enum Tone: Equatable { case ready, attention }

    public let tone: Tone
    public let title: String
    /// What the card says under its title: what is wrong, one line each, or what is fine and what is off.
    public let notes: [String]
    public let problems: [RoleProblem]
    /// The role to open to fix the first problem.
    public var fix: AgentRole? { problems.first?.role }
}

/// Whether Author, Reviewer and (when it is on) the Lead reviewer each have an identity, an account of `providers.json` and a model. It says nothing
/// of whether an account is signed in: that is the Providers page's answer.
public func agentsReadiness(_ page: AgentsPage) -> AgentsReadiness {
    let active = page.rows.filter { $0.off == false }
    var problems: [RoleProblem] = []
    for row in active {
        switch row.identity {
        case .forge, .gh: break
        case .missing: problems.append(RoleProblem(role: row.role, text: "the identity “\(row.fields.profile ?? "")” is not in Agent Forge or in profiles. Choose another."))
        case .unset: problems.append(RoleProblem(role: row.role, text: "it has no identity yet."))
        }
        if let provider = row.fields.provider, provider.isEmpty == false {
            if row.providerMissing { problems.append(RoleProblem(role: row.role, text: "the account “\(provider)” is not in providers.json.")) }
        } else {
            problems.append(RoleProblem(role: row.role, text: "it has no account yet."))
        }
        if row.fields.model?.isEmpty ?? true { problems.append(RoleProblem(role: row.role, text: "it has no model yet.")) }
    }
    let lead = page.rows.first { $0.role == .leadReviewer }
    var notes: [String]
    let title: String
    let tone: AgentsReadiness.Tone
    if problems.isEmpty {
        tone = .ready
        title = lead?.off == true ? "Author and Reviewer are set up" : "All three roles are set up"
        notes = [lead?.off == true ? "The Lead reviewer is off." : "Each has an identity, an account and a model."]
    } else {
        tone = .attention
        let roles = Set(problems.map(\.role)).count
        title = roles == 1 ? "One role needs attention" : "\(roles) roles need attention"
        notes = problems.map(\.line)
    }
    if let shared = page.sharedNote { notes.append(shared) }
    return AgentsReadiness(tone: tone, title: title, notes: notes, problems: problems)
}

/// One step of an epic that runs a skill of Solve (`AshuLab/skills`) for a role.
public struct RoleStage: Equatable, Identifiable {
    public let title: String
    public let detail: String
    /// The skill the engine invokes in this stage, as `src/prompts` spells it (`AgentsReadinessTests` reads those files and fails when this drifts).
    public let skill: String
    public var id: String { skill }
}

extension AgentRole {
    /// What the engine runs for the role, in the order an epic goes through it. The Lead reviewer has no stage: the engine does not run it yet
    /// (`agents.leadReviewer` is read and kept, and nothing uses it).
    public var stages: [RoleStage] {
        switch self {
        case .author: [
            RoleStage(title: "First pass", detail: "Drains the epic into its own worktree and leaves the final pull request open", skill: "ship"),
            RoleStage(title: "Answering a review", detail: "Answers every finding of the last review and fixes what applies", skill: "code-resolve"),
        ]
        case .reviewer: [
            RoleStage(title: "Review", detail: "Checks the epic against its spec and tickets", skill: "code-review"),
            RoleStage(title: "Post findings", detail: "Publishes the findings on the pull request", skill: "code-post"),
        ]
        case .leadReviewer: []
        }
    }
}

/// How the harness of an account is told to run a skill (`src/prompts/invoke.ts`): Codex spells it `$skill`, Claude Code and Antigravity `/skill`.
/// `icon` is the account's harness as `accountIcons` gives it; with none, the slash.
public func skillInvocation(_ skill: String, icon: String?) -> String { (icon == "codex" ? "$" : "/") + skill }

/// The letters a bot with no picture wears: the first of up to two words of its name (`artanis-agent` is AA, `zeratul` is Z); `?` for no name.
public func roleInitials(_ name: String) -> String {
    let words = name.split { $0.isLetter == false && $0.isNumber == false }.prefix(2)
    let letters = words.compactMap(\.first).map { String($0).uppercased() }.joined()
    return letters.isEmpty ? "?" : letters
}
