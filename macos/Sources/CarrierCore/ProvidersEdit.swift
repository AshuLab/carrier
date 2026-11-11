import Foundation

// Add, edit and remove an account of `providers.json` (docs/specs/providers-in-settings.md, docs/adr/0020). The app checks what it cheaply can
// with the rules of `src/config/providers.ts` (the name's pattern, the range of Auto-compact, absolute paths, the flags Carrier sets itself)
// and never writes a file those rules refuse; the rest is the chat host's, which answers `problem` on the next `providers`. Every function takes
// the file's bytes and returns the whole new file, keeping the keys the app does not know, so the caller has only to write it.

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
    public static let fields = ["displayName", "command", "configDir", "autoCompact", "launchArgs", "idleCompaction"]
}

/// "~" or "~/..." or "/...", with no control character: what the schema accepts once `~` is expanded.
private func isAbsolute(_ path: String) -> Bool {
    (path.hasPrefix("/") || path == "~" || path.hasPrefix("~/")) && path.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value != 0x7F }
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
    if draft.command.isEmpty == false, isAbsolute(draft.command) == false {
        problems["command"] = "Binary path must be an absolute path, or start with ~/."
    }
    if draft.configDir.isEmpty == false {
        if harness == "agy" {
            problems["configDir"] = "Antigravity has no config folder setting."
        } else if isAbsolute(draft.configDir) == false {
            problems["configDir"] = "Config folder must be an absolute path, or start with ~/."
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

/// The first of `problems` in the order of the fields, as the error that refuses the write.
private func refusal(_ problems: [String: String]) -> ProvidersFileError {
    .invalid(AccountDraft.fields.compactMap { problems[$0] }.first ?? "The account is not valid.")
}

/// The file's object and its `providers` map; a file that is not there is an empty one. Throws `notAnObject` for a file it must not overwrite.
private func parsed(_ json: Data?) throws -> (file: [String: Any], providers: [String: Any]) {
    var file: [String: Any] = [:]
    if let json {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { throw ProvidersFileError.notAnObject }
        file = object
    }
    var providers: [String: Any] = [:]
    if let existing = file["providers"] {
        guard let map = existing as? [String: Any] else { throw ProvidersFileError.notAnObject }
        providers = map
    }
    return (file, providers)
}

private func serialized(_ file: [String: Any], _ providers: [String: Any]) throws -> Data {
    var file = file
    file["providers"] = providers
    return try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// `json` with a new account of `harness`: its name and, when given, its config folder. Refused for a name that is invalid or taken, a folder
/// that is not absolute, and Antigravity, which has one account.
public func applyingNewAccount(name: String, harness: String, configDir: String, to json: Data?) throws -> Data {
    if let problem = nameProblem(name) { throw ProvidersFileError.invalid(problem) }
    guard harness == "claude" || harness == "codex" else { throw ProvidersFileError.invalid("Only Claude Code and Codex take more accounts.") }
    var draft = AccountDraft()
    draft.configDir = configDir
    let problems = draftProblems(draft, harness: harness)
    guard problems.isEmpty else { throw refusal(problems) }
    var (file, providers) = try parsed(json)
    guard providers[name] == nil else { throw ProvidersFileError.taken(name) }
    var account: [String: Any] = ["harness": harness]
    if configDir.isEmpty == false { account["configDir"] = configDir }
    providers[name] = account
    return try serialized(file, providers)
}

/// `json` with the editor's fields written to the account `name`: a filled field writes its key, an emptied one removes it, and every other key
/// of the account (`provider`, `model`, `enabled`, the ones the app does not know) stays as it was.
public func applyingEdit(name: String, draft: AccountDraft, to json: Data?) throws -> Data {
    var (file, providers) = try parsed(json)
    guard var account = providers[name] as? [String: Any], let harness = account["harness"] as? String else { throw ProvidersFileError.missing(name) }
    let problems = draftProblems(draft, harness: harness)
    guard problems.isEmpty else { throw refusal(problems) }
    func set(_ key: String, _ value: Any?) { account[key] = value }
    let display = draft.displayName.trimmingCharacters(in: .whitespaces)
    set("displayName", display.isEmpty ? nil : display)
    set("command", draft.command.isEmpty ? nil : draft.command)
    set("configDir", draft.configDir.isEmpty ? nil : draft.configDir)
    set("autoCompact", draft.autoCompact.isEmpty ? nil : (Int(draft.autoCompact) as Any? ?? draft.autoCompact))
    set("launchArgs", draft.arguments.isEmpty ? nil : draft.arguments)
    switch draft.idle {
    case .useDefault: set("idleCompaction", nil)
    case .never: set("idleCompaction", false)
    case .always: set("idleCompaction", true)
    }
    providers[name] = account
    return try serialized(file, providers)
}

/// `json` without the account `name`. `uses` is who names it (`accountUses`): while anyone does, the account stays.
public func applyingRemoval(name: String, uses: [AccountUse], to json: Data?) throws -> Data {
    var (file, providers) = try parsed(json)
    guard providers[name] != nil else { throw ProvidersFileError.missing(name) }
    guard uses.isEmpty else { throw ProvidersFileError.inUse(name, uses) }
    providers[name] = nil
    return try serialized(file, providers)
}

/// The editor's fields for the account `name`, as the file has them; nil when the file has no such account.
public func accountDraft(named name: String, in json: Data?) -> AccountDraft? {
    guard let json, let file = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any],
          let account = (file["providers"] as? [String: Any])?[name] as? [String: Any] else { return nil }
    return AccountDraft(account: account)
}

/// Said under the accounts, as the Behavior tab says it of `config.json`: the engine reads the file when it starts.
public let providersFooter = "The engine reads providers.json when it starts, so a running engine needs a restart to read a change. The chat host reads it at its next session."
