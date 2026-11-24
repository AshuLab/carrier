import Foundation

// The five requests of the `config` capability that write `providers.json` (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6; ADR 0053).
// Node's code writes the file and asks the engine to read it; the reply says what the engine did. They go over the socket when the chat host's hello lists `config`
// and to `carrier config` otherwise, as `editChatSettings` does (ConfigRequests.swift).

/// An account found by detection that the file does not have yet.
public struct DetectedAccount: Equatable {
    public let name: String
    public let harness: String

    public init(name: String, harness: String) { (self.name, self.harness) = (name, harness) }
}

/// A model of a local server chosen as the text generator.
public struct TextGeneratorChoice: Equatable {
    public let server: String
    public let model: String

    public init(server: String, model: String) { (self.server, self.model) = (server, model) }
}

/// A change to `providers.json`: one request, with what the Swift function it replaced took.
public enum ProvidersRequest: Equatable {
    /// Adds each account `{ harness }`; creates the file when it is not there (`applyingAccounts`).
    case setAccounts([DetectedAccount])
    /// A new account of a harness, with its config folder when given (`applyingNewAccount`).
    case addAccount(name: String, harness: String, configDir: String)
    /// The editor's fields written to the account, an emptied one removing its key (`ProvidersEdit.applyingEdit`).
    case editAccount(name: String, draft: AccountDraft)
    case removeAccount(name: String)
    /// nil clears the choice (`applyingTextGenerator`).
    case setTextGenerator(TextGeneratorChoice?)

    /// The request as the socket takes it, without its `id`.
    var body: [String: Any] {
        switch self {
        case .setAccounts(let accounts):
            return ["cmd": "setAccounts", "accounts": accounts.map { ["name": $0.name, "harness": $0.harness] }]
        case .addAccount(let name, let harness, let configDir):
            var account = ["name": name, "harness": harness]
            if configDir.isEmpty == false { account["configDir"] = configDir }
            return ["cmd": "addAccount", "account": account]
        case .editAccount(let name, let draft):
            return ["cmd": "editAccount", "name": name, "changes": draft.changes]
        case .removeAccount(let name):
            return ["cmd": "removeAccount", "name": name]
        case .setTextGenerator(let choice):
            return ["cmd": "setTextGenerator", "choice": choice.map { ["server": $0.server, "model": $0.model] as Any } ?? NSNull()]
        }
    }

    var command: String { body["cmd"] as? String ?? "" }

    /// The request as JSON, keys in order.
    var line: Data { (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data() }

    /// The fields after `cmd`, as the socket's request carries them.
    var fields: String {
        var rest = body
        rest["cmd"] = nil
        let json = (try? JSONSerialization.data(withJSONObject: rest, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return "," + String(json.dropFirst().dropLast())
    }

    /// The request as `carrier config` reads it: the socket's request without its `id`, one line.
    var request: Data { line + Data("\n".utf8) }
}

extension AccountDraft {
    /// Every field the editor shows as the key it writes: a filled one its value, an emptied one `null`, which removes the key.
    fileprivate var changes: [String: Any] {
        func text(_ value: String) -> Any { value.isEmpty ? NSNull() : value }
        var result: [String: Any] = [
            "displayName": text(displayName.trimmingCharacters(in: .whitespaces)),
            "label": text(label.trimmingCharacters(in: .whitespaces)),
            "icon": icon?.rawValue ?? NSNull(),
            "color": color?.rawValue ?? NSNull(),
            "command": text(command),
            "configDir": text(normalizedConfigDir(configDir)),
            "autoCompact": autoCompact.isEmpty ? NSNull() : (Int(autoCompact) as Any? ?? autoCompact),
            "launchArgs": arguments.isEmpty ? NSNull() : arguments,
        ]
        switch idle {
        case .useDefault: result["idleCompaction"] = NSNull()
        case .never: result["idleCompaction"] = false
        case .always: result["idleCompaction"] = true
        }
        return result
    }
}

/// The reply of a `providers.json` request: what the running engine did with the file (the part of the file that was saved is not read by the app).
public struct ProvidersSaved: Decodable, Equatable {
    /// `applied`, `refused` or `notRunning`.
    public let engine: String
    public let engineReason: Reason?

    public struct Reason: Decodable, Equatable {
        public let error: String
        public let code: String?
        public let params: [String: TextParam]?
    }

    /// What the page says about it, as `reloadWords` says it of the engine's own answer.
    public var outcome: ReloadOutcome {
        switch engine {
        case "applied": return .applied
        case "notRunning": return .nobody
        case "refused":
            guard let reason = engineReason else { return .noAnswer }
            // the engine was there and did not answer
            if reason.code == "providers.engineNoAnswer" { return .noAnswer }
            return .refused(Refusal(code: reason.code, params: reason.params ?? [:], text: reason.error))
        default: return .unsupported
        }
    }
}
