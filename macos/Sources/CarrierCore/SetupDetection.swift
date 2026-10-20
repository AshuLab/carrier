import Foundation

// The setup the app starts Carrier with, found once by asking the user's own shell (`zsh -ilc`). An app started from the
// Dock sees only /usr/bin:/bin:/usr/sbin:/sbin, and `zsh -lc` does not read .zshrc, so it finds a different Node than nvm's.

/// What `zsh -ilc` printed between the markers; nil is a tool the shell did not find.
public struct Detection: Equatable {
    public var carrier: String?
    public var node: String?
    public var path: String?

    public init(carrier: String? = nil, node: String? = nil, path: String? = nil) {
        self.carrier = carrier
        self.node = node
        self.path = path
    }
}

public let detectionBegin = "CARRIER_DETECT_BEGIN"
public let detectionEnd = "CARRIER_DETECT_END"

/// The command `zsh -ilc` runs. A `.zshrc` may print anything, so the answer sits between two marker lines.
public let detectionScript = """
    printf '\\n%s\\n' \(detectionBegin)
    printf 'carrier=%s\\n' "$(command -v carrier)"
    printf 'node=%s\\n' "$(command -v node)"
    printf 'path=%s\\n' "$PATH"
    printf '%s\\n' \(detectionEnd)
    """

/// The answer between the markers, ignoring anything before and after them. nil when there is no complete answer: empty
/// output, or a shell that was stopped at its time limit before the end marker. A tool is nil when its line is empty or is
/// not an absolute path (`command -v` prints the text of an alias or a function, which cannot be run).
public func parseDetection(_ output: String) -> Detection? {
    let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
    guard let begin = lines.firstIndex(of: detectionBegin),
          let end = lines[begin...].firstIndex(of: detectionEnd) else { return nil }
    var detection = Detection()
    for line in lines[(begin + 1)..<end] {
        guard let equals = line.firstIndex(of: "=") else { continue }
        let value = String(line[line.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
        switch line[..<equals] {
        case "carrier": detection.carrier = value.hasPrefix("/") ? value : nil
        case "node": detection.node = value.hasPrefix("/") ? value : nil
        case "path": detection.path = value.isEmpty ? nil : value
        default: break
        }
    }
    return detection
}

/// The PATH the engine runs with, and so the agent CLIs it starts: the detected one with the directory of `node` first.
public func enginePath(detected: String, node: String) -> String {
    var entries = detected.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    if node.hasPrefix("/") {
        let folder = (node as NSString).deletingLastPathComponent
        entries.removeAll { $0 == folder }
        entries.insert(folder, at: 0)
    }
    return entries.joined(separator: ":")
}

/// The five values of the settings pane; an empty one is a value not found.
public struct SetupSettings: Equatable {
    public var carrier = ""
    public var node = ""
    public var path = ""
    public var configPath = ""
    public var root = ""

    public init(carrier: String = "", node: String = "", path: String = "", configPath: String = "", root: String = "") {
        self.carrier = carrier
        self.node = node
        self.path = path
        self.configPath = configPath
        self.root = root
    }

    /// The shell's answer (nil: it gave none) with the config path and root from where Carrier keeps them, not from the shell.
    public init(detection: Detection?, environment: [String: String], home: String, configJSON: Data?) {
        self.init(
            carrier: detection?.carrier ?? "", node: detection?.node ?? "", path: detection?.path ?? "",
            configPath: configFilePath(environment: environment, home: home),
            root: sharedRoot(configJSON: configJSON, home: home)
        )
    }

    /// The values the person has to look at: the ones that were not found.
    public var missing: [String] {
        [("carrier", carrier), ("node", node), ("PATH", path), ("config path", configPath), ("root", root)]
            .filter { $0.1.isEmpty }.map(\.0)
    }
}

/// Saved settings in user defaults. nil means nothing was saved yet: the only time the shell is asked.
public struct SetupStore {
    private let defaults: UserDefaults
    private let key = "setup"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> SetupSettings? {
        guard let saved = defaults.dictionary(forKey: key) as? [String: String] else { return nil }
        return SetupSettings(
            carrier: saved["carrier"] ?? "", node: saved["node"] ?? "", path: saved["path"] ?? "",
            configPath: saved["configPath"] ?? "", root: saved["root"] ?? ""
        )
    }

    public func save(_ settings: SetupSettings) {
        defaults.set([
            "carrier": settings.carrier, "node": settings.node, "path": settings.path,
            "configPath": settings.configPath, "root": settings.root,
        ], forKey: key)
    }
}
