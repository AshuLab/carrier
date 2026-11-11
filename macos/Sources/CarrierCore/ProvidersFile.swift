import Foundation

// `providers.json` in the Carrier folder (docs/adr/0020): the accounts both the engine and the chat host read and the app writes. The app
// keeps the keys it does not know and writes the whole file in one step, as it does `chat.json`.

public enum ProvidersFileError: Error, Equatable {
    /// The file is there and is not a JSON object with a `providers` map (or has none): the app never overwrites a file it cannot read.
    case notAnObject
    /// An account of that name is already declared; the app never replaces one.
    case taken(String)
    /// No account of that name is declared.
    case missing(String)
    /// The account is named by a role, a repo override, a failover list or a chat agent, so it stays.
    case inUse(String, [AccountUse])
    /// The engine would refuse what was asked, said in words naming the field; nothing was written.
    case invalid(String)
}

/// `json` with the accounts added, each `{ harness, enabled: false }` (found by detection, not offered for an epic's choice, as the ADR
/// says); every other key of the file is left as it was. `json` nil is a file that is not there yet, which this makes.
public func applyingAccounts(_ accounts: [(name: String, harness: String)], to json: Data?) throws -> Data {
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
    for account in accounts {
        guard providers[account.name] == nil else { throw ProvidersFileError.taken(account.name) }
        providers[account.name] = ["harness": account.harness, "enabled": false] as [String: Any]
    }
    file["providers"] = providers
    return try JSONSerialization.data(withJSONObject: file, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
}

/// The file on disk. `save` is how the bytes reach it: the whole file at once, through a temporary file that replaces it, so a failed write
/// leaves the old one.
public struct ProvidersFile {
    public let url: URL
    private let save: (Data, URL) throws -> Void

    public init(folder: String, save: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) {
        url = URL(fileURLWithPath: folder + "/providers.json")
        self.save = save
    }

    /// The file of the folder the app works with (`CARRIER_HOME`, else `~/.carrier`), looked up each time.
    public static func current() -> ProvidersFile { ProvidersFile(folder: currentCarrierFolder()) }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// The bytes; nil when the file is not there, an error when it is there and cannot be read.
    public func read() throws -> Data? { exists ? try Data(contentsOf: url) : nil }

    /// Makes the Carrier folder when it is not there yet.
    public func write(_ data: Data) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try save(data, url)
    }
}
