import Foundation

// `providers.json` in the Carrier folder (docs/adr/0020): the accounts both the engine and the chat host read. The app only reads it; a change is a request to the chat
// host or to `carrier config` (ADR 0053, `ProvidersRequest`).

/// The file on disk.
public struct ProvidersFile {
    public let url: URL

    public init(folder: String) {
        url = URL(fileURLWithPath: CarrierPlaces(folder: folder).providers)
    }

    /// The file of the folder the app works with (`CARRIER_HOME`, else `~/.carrier`), looked up each time.
    public static func current() -> ProvidersFile { ProvidersFile(folder: currentCarrierFolder()) }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    /// The bytes; nil when the file is not there, an error when it is there and cannot be read.
    public func read() throws -> Data? { exists ? try Data(contentsOf: url) : nil }
}
