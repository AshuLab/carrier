import Foundation

// The editor of an account of `providers.json` (docs/specs/providers-in-settings.md, docs/adr/0020). The app checks what it cheaply can while the person types
// with the rules of `src/config/providers.ts` (the name's pattern, the range of Auto-compact, absolute paths for the binary, the flags Carrier sets itself);
// the write is a request to the chat host (ADR 0053), which refuses what the rules refuse, and the rest is the host's, which answers `problem` on the next `providers`.

public enum IdleCompaction: Equatable, CaseIterable {
    case useDefault, never, always

    public var title: String {
        switch self {
        case .useDefault: "Use default"
        case .never: "Never"
        case .always: "Always"
        }
    }
}

/// The editor's fields as the person typed them. An empty text is a key that is not there.
public struct AccountDraft: Equatable {
    public var displayName = ""
    public var label = ""
    /// nil is the tool's own mark.
    public var icon: AccountIcon?
    public var color: AccountColor?
    public var command = ""
    public var configDir = ""
    public var autoCompact = ""
    /// One argument per line.
    public var launchArgs = ""
    public var idle = IdleCompaction.useDefault

    public init() {}

    /// The draft of an account as the file has it.
    public init(account: [String: Any]) {
        displayName = account["displayName"] as? String ?? ""
        let identity = ProviderIdentity(account: account)
        label = identity.label ?? ""
        icon = identity.icon
        color = identity.color
        command = account["command"] as? String ?? ""
        configDir = account["configDir"] as? String ?? ""
        if let text = account["autoCompact"] as? String { autoCompact = text } else if let number = account["autoCompact"] as? Int { autoCompact = String(number) }
        launchArgs = (account["launchArgs"] as? [String] ?? []).joined(separator: "\n")
        if let idleCompaction = account["idleCompaction"] as? Bool { idle = idleCompaction ? .always : .never }
    }

    /// The arguments: the non-empty lines, each trimmed.
    var arguments: [String] {
        launchArgs.split(separator: "\n", omittingEmptySubsequences: true).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.isEmpty == false }
    }

    /// The fields in the order they are shown, with the key of each, which is what a problem is keyed by.
    public static let fields = ["displayName", "label", "icon", "color", "command", "configDir", "autoCompact", "launchArgs", "idleCompaction"]
}

/// "~" or "~/..." or "/...", with no control character: what the schema accepts once `~` is expanded.
private func isAbsolute(_ path: String) -> Bool {
    (path.hasPrefix("/") || path == "~" || path.hasPrefix("~/")) && path.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
}

/// The config folder as the file keeps it. The engine takes an absolute path or one that starts with `~/`, and a person can type anything: a
/// path that is neither is taken from the home folder (`work` is `~/work`, `./work` too), so the file is always one the engine reads.
public func normalizedConfigDir(_ text: String) -> String {
    let path = text.trimmingCharacters(in: .whitespaces)
    if path.isEmpty || isAbsolute(path) { return path }
    return "~/" + (path.hasPrefix("./") ? String(path.dropFirst(2)) : path)
}

/// The account of `harness` whose config folder is `configDir` (`~` expanded, trailing slash ignored), so with the same login: its display name,
/// else its key. An account with no folder has the tool's own (`~/.claude`, `~/.codex`). Nil when none is or the folder is empty. `except` is the
/// account being edited. Not a problem: two accounts may share a login for another model or other arguments.
public func accountSharingFolder(configDir: String, harness: String, except name: String? = nil, in json: Data?) -> String? {
    func resolved(_ path: String) -> String { URL(fileURLWithPath: (normalizedConfigDir(path) as NSString).expandingTildeInPath).standardizedFileURL.path }
    guard configDir.trimmingCharacters(in: .whitespaces).isEmpty == false, let json,
          let providers = ((try? JSONSerialization.jsonObject(with: json)) as? [String: Any])?["providers"] as? [String: Any] else { return nil }
    let wanted = resolved(configDir)
    let toolFolder = ["claude": "~/.claude", "codex": "~/.codex"][harness]
    let key = providers.keys.sorted().first { other in
        guard other != name, let account = providers[other] as? [String: Any], account["harness"] as? String == harness else { return false }
        let own = (account["configDir"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard let folder = own ?? toolFolder else { return false }
        return resolved(folder) == wanted
    }
    guard let key else { return nil }
    return (providers[key] as? [String: Any])?["displayName"] as? String ?? key
}

/// A name the engine accepts: `optionNamePattern`, `^[a-z][a-z0-9-]{0,39}$`.
public func nameProblem(_ name: String) -> String? {
    let scalars = Array(name.unicodeScalars)
    let valid = (1...40).contains(scalars.count)
        && ("a"..."z").contains(scalars[0])
        && scalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
    return valid ? nil : "Name must be a lowercase word: letters, digits and hyphens, starting with a letter, up to 40 characters."
}

private let refusedFlags = [
    "claude": ["-p", "--model", "--permission-mode", "--output-format", "--resume", "--name", "--add-dir", "--settings", "--autocompact"],
    "codex": ["--model", "--json", "--dangerously-bypass-approvals-and-sandbox", "--sandbox"],
]
private let refusedCodexKeys = ["model_provider", "carrier_marker", "model_auto_compact_token_limit"]

/// What an argument repeats of what Carrier sets (`src/config/launch-args.ts`): the flag, or the Codex config key; nil when none does.
private func refusedLaunchArg(harness: String, _ args: [String]) -> String? {
    for (index, token) in args.enumerated() {
        if token.hasPrefix("-") {
            let flag = String(token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[0])
            if refusedFlags[harness]?.contains(flag) == true { return flag }
        }
        guard harness == "codex" else { continue }
        var pair: String?
        if token == "-c" || token == "--config" {
            pair = index + 1 < args.count ? args[index + 1] : nil
        } else if token.hasPrefix("--config=") {
            pair = String(token.dropFirst("--config=".count))
        } else if token.hasPrefix("-c"), token.count > 2, token.dropFirst(2).first != "-" {
            pair = String(token.dropFirst(2))
        }
        if let key = pair?.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map({ $0.trimmingCharacters(in: .whitespaces) }), refusedCodexKeys.contains(key) {
            return "the config key \(key)"
        }
    }
    return nil
}

/// What is wrong with the draft for an account of `harness`, by the key of the field, in words that name it. Empty when the engine would take it.
public func draftProblems(_ draft: AccountDraft, harness: String) -> [String: String] {
    var problems: [String: String] = [:]
    let name = draft.displayName.trimmingCharacters(in: .whitespaces)
    if name.count > 60 || name.contains(where: \.isNewline) {
        problems["displayName"] = "Display name is a single line of at most 60 characters."
    }
    let label = draft.label.trimmingCharacters(in: .whitespaces)
    if label.count > ProviderIdentity.labelLimit || label.contains(where: \.isNewline) {
        problems["label"] = "Label is a single line of at most \(ProviderIdentity.labelLimit) characters."
    }
    if draft.command.isEmpty == false, isAbsolute(draft.command) == false {
        problems["command"] = "Binary path must be an absolute path, or start with ~/."
    }
    if draft.configDir.isEmpty == false {
        if harness == "agy" {
            problems["configDir"] = "Antigravity has no config folder setting."
        } else if draft.configDir.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) {
            problems["configDir"] = "Config folder has a character that a path cannot have."
        }
    }
    if draft.autoCompact.isEmpty == false {
        switch harness {
        case "claude":
            if draft.autoCompact != "auto", (Int(draft.autoCompact).map { (100_000...1_000_000).contains($0) } ?? false) == false {
                problems["autoCompact"] = "Auto-compact after for Claude is \"auto\" or a token count from 100000 to 1000000."
            }
        case "codex":
            if (Int(draft.autoCompact).map { $0 > 0 } ?? false) == false {
                problems["autoCompact"] = "Auto-compact after for Codex is a token count above zero."
            }
        default:
            problems["autoCompact"] = "Antigravity has no auto-compact setting."
        }
    }
    if let refused = refusedLaunchArg(harness: harness, draft.arguments) {
        problems["launchArgs"] = "Launch arguments cannot repeat \(refused), Carrier sets it."
    }
    if draft.idle != .useDefault, harness != "claude" {
        problems["idleCompaction"] = "Compact idle threads is for Claude only."
    }
    return problems
}

/// The editor's fields for the account `name`, as the file has them; nil when the file has no such account.
public func accountDraft(named name: String, in json: Data?) -> AccountDraft? {
    guard let json, let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
          let account = (file["providers"] as? [String: Any])?[name] as? [String: Any] else { return nil }
    return AccountDraft(account: account)
}
