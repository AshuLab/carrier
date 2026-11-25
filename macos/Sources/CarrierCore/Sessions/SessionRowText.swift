import Foundation

// MARK: the session's row
// The centered row that opens a session: who acted, what it did, how it ran, and one line of numbers under it.

/// What `engine.json` says of its profiles and of the two roles a session runs as. The engine sends the key of `profiles` a session acted
/// as, a name the person chose; this says whose GitHub account it is, and names who a session acted as when the engine sends no key.
/// ponytail: the global roles only; a repo's own `agents` override is not read.
public struct RoleIdentities: Equatable {
    private struct Role: Equatable {
        var profile: String?
        var model: String?
        var effort: String?
    }

    private var roles: [String: Role] = [:]
    /// The Agent Forge bot of each `forge` profile, by the profile's key.
    private var bots: [String: String] = [:]
    /// The keys of the `gh` profiles.
    private var logins: Set<String> = []

    public static let none = RoleIdentities()

    private init() {}

    /// Only a bot of Agent Forge is a name: a `gh` profile is the person's login, which the config does not hold. No file, or one that is
    /// not a JSON object, names nobody.
    public init(config: Data?) {
        guard let config, let file = (try? JSONSerialization.jsonObject(with: config)) as? [String: Any] else { return }
        let profiles = file["profiles"] as? [String: Any] ?? [:]
        let agents = file["agents"] as? [String: Any] ?? [:]
        for (key, value) in profiles {
            guard let profile = value as? [String: Any] else { continue }
            if profile["kind"] as? String == "forge", let bot = profile["agent"] as? String { bots[key] = bot }
            if profile["kind"] as? String == "gh" { logins.insert(key) }
        }
        for name in ["author", "reviewer"] {
            guard let role = agents[name] as? [String: Any] else { continue }
            let profile = (role["profile"] as? String).flatMap { profiles[$0] as? [String: Any] }
            roles[name] = Role(
                profile: profile?["kind"] as? String == "forge" ? profile?["agent"] as? String : nil,
                model: role["model"] as? String, effort: role["effort"] as? String
            )
        }
    }

    /// `section` with the bot its profile's key stands for (a `gh` profile is the person's login, which the config does not hold, so it
    /// names no one; a key the config does not know stays as the engine sent it), or, when the engine sent no key, the bot of its role; and
    /// the role's effort when it ran on the role's model (a failover to another model did not run with that effort).
    public func resolved(_ section: SessionSection) -> SessionSection {
        var named = section
        if let key = section.profile, key.isEmpty == false {
            if let bot = bots[key] { named.profile = bot } else if logins.contains(key) { named.profile = nil }
        }
        guard let role = roles[section.engineRole] else { return named }
        if section.profile == nil { named.profile = role.profile }
        if named.effort == nil, let model = section.model, model == role.model { named.effort = role.effort }
        return named
    }
}

/// The words of a session's row, as the view draws them.
public struct SessionRowText: Equatable {
    /// The GitHub profile, or the tool's name when the session has none.
    public var name: String
    /// "Builder · Ship".
    public var role: String
    /// The tool's name on the second line; nil when it already is the name.
    public var tool: String?
    /// "account pro", the model, the effort: what is known, in this order.
    public var details: [String]
    /// The avatar's letter: the profile's, else the tool's.
    public var letter: String
    public var identified: Bool

    /// The second line as one text.
    public var how: String { ([tool].compactMap { $0 } + details).joined(separator: " · ") }
}

public func sessionRowText(_ section: SessionSection, bundle: Bundle? = nil, locale: Locale = .current) -> SessionRowText {
    let profile = section.profile.flatMap { $0.isEmpty ? nil : $0 }
    return SessionRowText(
        name: profile ?? section.agent,
        role: "\(section.role) · \(section.place)",
        tool: profile == nil ? nil : section.agent,
        details: [section.account.map { Copy.sessionAccount(name: $0, bundle: bundle, locale: locale) }, section.model, section.effort].compactMap { $0 }.filter { $0.isEmpty == false },
        letter: profile.map { String($0.prefix(1)).uppercased() } ?? section.initial,
        identified: profile != nil
    )
}

/// A piece of the row's summary line and how it is drawn.
public struct SummarySpan: Equatable {
    public enum Style: Equatable { case plain, strong, faint, red, green, working }
    public var text: String
    public var style: Style
}

public enum SessionSummary: Equatable {
    /// The orange badge and why, when the engine says.
    case stopped(reason: String?)
    case line([SummarySpan])

    /// What it says, as one sentence for VoiceOver.
    public func text(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .stopped(let reason): reason.map { Copy.sessionStoppedReason(reason: $0, bundle: bundle, locale: locale) } ?? Copy.sessionStopped(bundle: bundle, locale: locale)
        case .line(let spans): spans.map(\.text).joined(separator: " ").replacingOccurrences(of: " · ", with: ", ")
        }
    }
}

/// The line under a session's row. Running: `Working · since 16:09 · 62 calls`. Stopped: the badge and its reason. Open: the counts and the
/// time (`229 calls · 23 edits +10 −2 · 27 test runs · 9 errors · 31m`). Folded: how it ended in bold, the CI verdict and the time
/// (`Completed · CI passed · 31m`), or the counts when it has no result.
public func sessionSummary(_ section: SessionSection, open: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> SessionSummary {
    func plural(_ n: Int, _ noun: String) -> [SummarySpan] { [.init(text: "\(n)", style: .strong), .init(text: noun, style: .plain)] }
    func join(_ parts: [[SummarySpan]]) -> [SummarySpan] {
        parts.enumerated().flatMap { index, part in index == 0 ? part : [SummarySpan(text: "·", style: .faint)] + part }
    }
    func word(_ text: String, _ style: SummarySpan.Style = .plain) -> [SummarySpan] { [.init(text: text, style: style)] }
    let time = section.timeLabel.map { word($0) }
    switch section.state {
    case .stopped:
        return .stopped(reason: section.failure)
    case .running:
        let calls = section.counts.map { plural($0.calls, Copy.sessionNounCall(count: $0.calls, bundle: bundle, locale: locale)) }
        return .line(join([word(Copy.sessionStatusWorking(bundle: bundle, locale: locale), .working), section.timeLabel.map { word($0) }, calls].compactMap { $0 }))
    case .done:
        if open == false, let result = section.result {
            return .line(join([word(result.outcome, .strong), result.ci.map { word(ciVerdictText($0.verdict, bundle: bundle, locale: locale)) }, time].compactMap { $0 }))
        }
        var parts: [[SummarySpan]] = []
        if let counts = section.counts {
            parts.append(plural(counts.calls, Copy.sessionNounCall(count: counts.calls, bundle: bundle, locale: locale)))
            if counts.edits > 0 {
                parts.append(
                    plural(counts.edits, Copy.sessionNounEdit(count: counts.edits, bundle: bundle, locale: locale)) + word("+\(counts.added)", .green) + word("−\(counts.removed)", .red))
            }
            if counts.tests > 0 { parts.append(plural(counts.tests, Copy.sessionNounTestRun(count: counts.tests, bundle: bundle, locale: locale))) }
            if counts.errors > 0 {
                parts.append(plural(counts.errors, Copy.sessionNounError(count: counts.errors, bundle: bundle, locale: locale)).map { SummarySpan(text: $0.text, style: .red) })
            }
        }
        return .line(join(parts + [time].compactMap { $0 }))
    }
}

/// Whom, what and whether it is open, for the one button that is the whole row.
public func sessionRowLabel(_ section: SessionSection, open: Bool, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    let text = sessionRowText(section, bundle: bundle, locale: locale)
    let summary = sessionSummary(section, open: open, bundle: bundle, locale: locale).text(bundle: bundle, locale: locale)
    let state = open ? Copy.sessionRowOpen(bundle: bundle, locale: locale) : Copy.sessionRowFolded(bundle: bundle, locale: locale)
    return [text.name, text.role, text.how, summary, state].filter { $0.isEmpty == false }.joined(separator: ". ")
}
