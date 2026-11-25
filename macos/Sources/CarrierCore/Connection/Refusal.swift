import Foundation

// A text Node sends a person carries a code and its parameters beside its English words (docs/adr/0055). The app decodes them here and
// decides by the code; a reply without one (a Node that predates the codes) has its words only, and the words are the fallback.

/// The value of a parameter of a text code: a string or a number, never a sentence, an object or a boolean.
public enum TextParam: Codable, Equatable, Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case string(String)
    case number(Double)

    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if let text = try? single.decode(String.self) {
            self = .string(text)
        } else {
            self = .number(try single.decode(Double.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let text): try single.encode(text)
        case .number(let number): try single.encode(number)
        }
    }

    /// The parameter as it reads in a sentence.
    public var text: String {
        switch self {
        case .string(let text): text
        case .number(let number): number.rounded() == number ? String(Int(number)) : String(number)
        }
    }

    /// The parameters of a reply read with `JSONSerialization`: the strings and numbers of `value`, and nothing else (a boolean, an object or a list is not one).
    static func read(_ value: Any?) -> [String: TextParam] {
        var found: [String: TextParam] = [:]
        for (key, item) in value as? [String: Any] ?? [:] {
            if let text = item as? String {
                found[key] = .string(text)
            } else if let number = item as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
                found[key] = .number(number.doubleValue)
            }
        }
        return found
    }
}

/// A refusal of the engine or the chat host, or one the app makes itself: the words to show and, when the reply had them, the code and parameters to decide by.
public struct Refusal: Equatable, Sendable {
    /// nil for a reply that carries none: a Node that predates the codes, or an error of a place that has no code.
    public let code: String?
    public let params: [String: TextParam]
    /// The English words; shown as they are, and what is decided by only when `code` is nil.
    public let text: String

    public init(code: String?, params: [String: TextParam] = [:], text: String) {
        (self.code, self.params, self.text) = (code, params, text)
    }

    /// A refusal of words only: what a reply with no code is.
    public static func words(_ text: String) -> Refusal { Refusal(code: nil, text: text) }

    /// The refusal the error reply `reply` says: its `error` words, and its `code` and `params` when it has them.
    static func read(_ reply: [String: Any]) -> Refusal {
        Refusal(code: reply["code"] as? String, params: TextParam.read(reply["params"]), text: reply["error"] as? String ?? "unknown error")
    }

    /// Whether this is the refusal `code` stands for; a refusal with no code is none.
    public func has(_ code: String) -> Bool { self.code == code }
}

/// The text codes of the refusals the app makes itself, each with the words it always had. A refusal the app copies from Node (`WorkspaceSources`)
/// has Node's code; one only the app makes has its own, which starts with `app.` so that it never meets one of Node's.
extension Refusal {
    static func hostLacks(_ command: String) -> Refusal {
        Refusal(code: "app.chatHost.commandUnsupported", params: ["command": .string(command)], text: "the chat host does not support \(command)")
    }

    /// Whether `self` is `hostLacks(command)`.
    func isHostLacking(_ command: String) -> Bool { code == "app.chatHost.commandUnsupported" && params["command"] == .string(command) }

    /// Node's own refusal of a repository that is not `owner/name`, with its code.
    static func repoInvalid(_ repo: String) -> Refusal {
        Refusal(code: "project.repoInvalid", params: ["repo": .string(repo)], text: "\"\(repo)\" is not a repository; write it as owner/name")
    }

    static let projectsNeedNewerHost = Refusal(code: "app.chatHost.projectsNeedNewer", text: CarrierCore.projectsNeedNewerHost)
    public static let usageNeedsNewerHost = Refusal(code: "app.chatHost.usageNeedsNewer", text: CarrierCore.usageNeedsNewerHost)
    static let folderGone = Refusal(code: "app.session.folderGone", text: "Its folder was deleted, so it cannot go on")
    static let hostNotRunning = Refusal(code: "app.chatHost.notRunning", text: CarrierCore.hostNotRunning)
    static let hostNotAnswering = Refusal(code: "app.chatHost.notAnswering", text: "The chat host is not answering")
    static let hostTookTooLong = Refusal(code: "app.chatHost.tookTooLong", text: "The chat host took too long to answer")
    static let hostNotUnderstood = Refusal(code: "app.chatHost.notUnderstood", text: "The chat host sent something that was not understood")
    static let folderUnusable = Refusal(code: "app.folder.unusable", text: "That folder cannot be used")
    static let sessionIdInvalid = Refusal(code: "app.request.sessionIdInvalid", text: "not a valid session id")
    static let rangeInvalid = Refusal(code: "app.request.rangeInvalid", text: "not a valid range")
    static let fileInvalid = Refusal(code: "app.request.fileInvalid", text: "not a valid file")
    static let epicInvalid = Refusal(code: "app.request.epicInvalid", text: "not a valid epic")
    static let executionInvalid = Refusal(code: "app.request.executionInvalid", text: "not a valid execution id")
    static let projectNameEmpty = Refusal(code: "app.projectName.empty", text: "Write a name")
    static let projectNameTooLong = Refusal(code: "app.projectName.tooLong", text: "A name has at most 100 characters")
    static let projectNameBadStart = Refusal(code: "app.projectName.badStart", text: "A name starts with a letter, a digit or _")
    static let projectNameBadCharacters = Refusal(code: "app.projectName.badCharacters", text: "Use only letters, digits, _, . and -")
    static let carrierOlder = Refusal(code: "app.protocol.carrierOlder", text: "carrier is older than this app. Run brew upgrade carrier in Terminal, then restart Carrier.")
    static let appOlder = Refusal(
        code: "app.protocol.appOlder", text: "This app is older than carrier. It updates itself; if it has not, run brew upgrade --cask carrier in Terminal, then open the app again.")
}
