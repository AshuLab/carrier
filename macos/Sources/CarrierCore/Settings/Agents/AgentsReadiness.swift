import Foundation

// What the top of the Agents page says (docs/macos/settings-carrier.md): whether the roles of an epic are set up, and what is in the way; and what
// each role runs, stage by stage. Decided here from what the page reads, so it can be tested; the views only draw it.

/// One thing in the way of a role: said with the role's name in front.
public struct RoleProblem: Equatable, Identifiable {
    public let role: AgentRole
    public let text: String
    /// The text with the role's name in front, in the language it was made in.
    public let line: String
    /// A role can have several, so the line is the id, not the role.
    public var id: String { line }

    public init(role: AgentRole, text: String, bundle: Bundle? = nil, locale: Locale = .current) {
        self.role = role
        self.text = text
        line = Copy.agentsProblemLine(role: role.title(bundle: bundle, locale: locale), text: text, bundle: bundle, locale: locale)
    }
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
public func agentsReadiness(_ page: AgentsPage, bundle: Bundle? = nil, locale: Locale = .current) -> AgentsReadiness {
    let active = page.rows.filter { $0.off == false }
    var problems: [RoleProblem] = []
    for row in active {
        switch row.identity {
        case .forge, .gh: break
        case .missing:
            problems.append(RoleProblem(role: row.role, text: Copy.agentsProblemIdentity(profile: row.fields.profile ?? "", bundle: bundle, locale: locale), bundle: bundle, locale: locale))
        case .unset: problems.append(RoleProblem(role: row.role, text: Copy.agentsProblemNoIdentity(bundle: bundle, locale: locale), bundle: bundle, locale: locale))
        }
        if let provider = row.fields.provider, provider.isEmpty == false {
            if row.providerMissing {
                problems.append(RoleProblem(role: row.role, text: Copy.agentsProblemAccount(provider: provider, bundle: bundle, locale: locale), bundle: bundle, locale: locale))
            }
        } else {
            problems.append(RoleProblem(role: row.role, text: Copy.agentsProblemNoAccount(bundle: bundle, locale: locale), bundle: bundle, locale: locale))
        }
        if row.fields.model?.isEmpty ?? true {
            problems.append(RoleProblem(role: row.role, text: Copy.agentsProblemNoModel(bundle: bundle, locale: locale), bundle: bundle, locale: locale))
        }
    }
    let lead = page.rows.first { $0.role == .leadReviewer }
    var notes: [String]
    let title: String
    let tone: AgentsReadiness.Tone
    if problems.isEmpty {
        tone = .ready
        title = lead?.off == true ? Copy.agentsTwoSet(bundle: bundle, locale: locale) : Copy.agentsAllSet(bundle: bundle, locale: locale)
        notes = [lead?.off == true ? Copy.agentsLeadOff(bundle: bundle, locale: locale) : Copy.agentsEachHas(bundle: bundle, locale: locale)]
    } else {
        tone = .attention
        let roles = Set(problems.map(\.role)).count
        title = Copy.agentsNeedAttention(count: roles, bundle: bundle, locale: locale)
        notes = problems.map(\.line)
    }
    if let shared = page.sharedNote { notes.append(shared) }
    return AgentsReadiness(tone: tone, title: title, notes: notes, problems: problems)
}

/// One step of an epic that runs a skill of Solve (`AshuLab/skills`) for a role.
public struct RoleStage: Equatable, Identifiable {
    public let title: String
    public let detail: String
    /// The skill the engine invokes in this stage, as the engine's defaults name it (`skills` in `engine.json`; `AgentsReadinessTests` reads them from the contract fixture and fails when this drifts).
    public let skill: String
    public var id: String { skill }
}

extension AgentRole {
    /// What the engine runs for the role, in the order an epic goes through it. The Lead reviewer has no stage here: the engine runs it,
    /// once after the reviewers agree, but the app does not list its skills yet.
    public func stages(bundle: Bundle? = nil, locale: Locale = .current) -> [RoleStage] {
        switch self {
        case .author: [
            RoleStage(
                title: Copy.agentsStageTitle(which: .first, bundle: bundle, locale: locale), detail: Copy.agentsStageDetail(which: .first, bundle: bundle, locale: locale), skill: "ship"),
            RoleStage(
                title: Copy.agentsStageTitle(which: .answer, bundle: bundle, locale: locale), detail: Copy.agentsStageDetail(which: .answer, bundle: bundle, locale: locale), skill: "code-resolve"),
        ]
        case .reviewer: [
            RoleStage(
                title: Copy.agentsStageTitle(which: .review, bundle: bundle, locale: locale), detail: Copy.agentsStageDetail(which: .review, bundle: bundle, locale: locale), skill: "code-review"),
            RoleStage(
                title: Copy.agentsStageTitle(which: .post, bundle: bundle, locale: locale), detail: Copy.agentsStageDetail(which: .post, bundle: bundle, locale: locale), skill: "code-post"),
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
