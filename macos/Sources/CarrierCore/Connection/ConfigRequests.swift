import Foundation

// The `config` capability of the chat host (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 6; ADR 0053): a change to a file of the Carrier
// folder is a request, and Node's code writes the file. The host answers it when its hello lists `config`; otherwise `carrier config` takes the same request,
// without its `id`, on standard input and prints the reply the socket would give, without its `id`, as one line of JSON.

/// What `editChatSettings` changes in `chat.json`: the keys of the two ages, `worktreeStart` and `idleCloseMinutes`; a value equal to its default is removed from the file.
public struct ChatSettingChanges: Equatable {
    public enum Value: Equatable {
        case days(Int), text(String), remove
    }

    /// The change by key, as the file names it.
    public var values: [String: Value]

    public init(_ values: [String: Value]) { self.values = values }

    public static func ages(_ ages: SessionAges) -> ChatSettingChanges {
        func value(_ age: SessionAge, default fallback: Int) -> Value {
            switch age {
            case .never: .text("never")
            case .days(let days): days == fallback ? .remove : .days(days)
            }
        }
        return ChatSettingChanges([
            "archiveAfterDays": value(ages.archive, default: defaultArchiveAfterDays),
            "deleteAfterDays": value(ages.delete, default: defaultDeleteAfterDays),
        ])
    }

    public static func worktreeStart(_ start: WorktreeStart) -> ChatSettingChanges {
        ChatSettingChanges(["worktreeStart": start == defaultWorktreeStart ? .remove : .text(start.rawValue)])
    }

    public static func idleClose(_ close: IdleClose) -> ChatSettingChanges {
        ChatSettingChanges(["idleCloseMinutes": close == defaultIdleClose ? .remove : .days(close.rawValue)])
    }

    /// The `changes` object as JSON, keys in order; a removal is `null`.
    var json: String {
        let pairs = values.sorted { $0.key < $1.key }.map { key, value in
            let written: String
            switch value {
            case .days(let days): written = String(days)
            case .text(let text): written = jsonString(text)
            case .remove: written = "null"
            }
            return "\(jsonString(key)):\(written)"
        }
        return "{" + pairs.joined(separator: ",") + "}"
    }

    /// The request as `carrier config` reads it: the socket's request without its `id`.
    var request: Data { Data("{\"cmd\":\"editChatSettings\",\"changes\":\(json)}\n".utf8) }
}

/// The reply of `editChatSettings`: the keys that were asked for, as the file now has them (a removed key is not there).
public struct ChatSettingsSaved: Decodable, Equatable {
    public let saved: [String: TextParam]
}

/// How the app runs `carrier config` when the chat host does not list `config`: the program that runs it, and what it needs.
public struct CarrierConfigLauncher {
    public let runner: any ProcessRunner
    /// nil when there is no `carrier` to run.
    public let command: () -> ProcessCommand?

    public init(runner: any ProcessRunner, command: @escaping () -> ProcessCommand?) {
        (self.runner, self.command) = (runner, command)
    }

    /// Runs `carrier config` with `request` on its standard input and reads the reply it printed: exit 0 saved, 1 refused (it prints the refusal), 2 not a request.
    func run<Reply: Decodable>(_ request: Data, as type: Reply.Type) async throws -> Reply {
        guard var command = command() else { throw ControlError.remote(.carrierNotFound) }
        command.input = request
        let result: ProcessResult
        do { result = try await runner.run(command) } catch { throw ControlError.remote(.configNotRun) }
        guard let line = result.output.split(whereSeparator: \.isNewline).last,
            let reply = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any], let ok = reply["ok"] as? Bool
        else { throw ControlError.remote(.configNotRun) }
        guard ok, result.status == 0 else { throw ControlError.remote(Refusal.read(reply)) }
        guard let data = reply["data"], let body = try? JSONSerialization.data(withJSONObject: data, options: .fragmentsAllowed),
            let decoded = try? JSONDecoder().decode(Reply.self, from: body)
        else { throw ControlError.badLine }
        return decoded
    }
}

/// What to run for `carrier config`: `carrier config` (`node <carrier> config` for a script), with the same `PATH` and `CARRIER_HOME` the chat host starts with.
/// nil when `startMissing` is not empty.
public func carrierConfigCommand(settings: SetupSettings, carrier: String?, environment: [String: String], home: String = NSHomeDirectory()) -> ProcessCommand? {
    guard let carrier, startMissing(settings, carrier: carrier).isEmpty else { return nil }
    var environment = environment
    environment["PATH"] = enginePath(detected: settings.path, node: settings.node)
    environment["CARRIER_HOME"] = carrierFolder(environment: environment, home: home)
    let run = carrierProgram(carrier: carrier, node: settings.node, arguments: ["config"])
    // node starts a TypeScript file slower than a request on a socket
    return ProcessCommand(program: run.program, arguments: run.arguments, environment: environment, limit: 30)
}

extension Refusal {
    static let carrierNotFound = Refusal(code: "app.config.carrierNotFound", text: "The app did not find carrier, so it cannot save this setting")
    static let configNotRun = Refusal(code: "app.config.notRun", text: "carrier could not save this setting")
}
