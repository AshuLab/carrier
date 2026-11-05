import Foundation

// The setup the app starts Carrier with: `node` and the `PATH`, found once by asking the user's own shell (`zsh -ilc`), and where
// `carrier` is. An app started from the Dock sees only /usr/bin:/bin:/usr/sbin:/sbin, and `zsh -lc` does not read .zshrc, so it finds
// a different Node than nvm's.

/// What `zsh -ilc` printed between the markers; nil is a tool the shell did not find.
public struct Detection: Equatable {
    public var node: String?
    public var path: String?

    public init(node: String? = nil, path: String? = nil) {
        self.node = node
        self.path = path
    }
}

public let detectionBegin = "CARRIER_DETECT_BEGIN"
public let detectionEnd = "CARRIER_DETECT_END"

/// The command `zsh -ilc` runs. A `.zshrc` may print anything, so the answer sits between two marker lines.
public let detectionScript = """
    printf '\\n%s\\n' \(detectionBegin)
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
        case "node": detection.node = value.hasPrefix("/") ? value : nil
        case "path": detection.path = value.isEmpty ? nil : value
        default: break
        }
    }
    return detection
}

let systemPath = "/usr/bin:/bin:/usr/sbin:/sbin"

/// Where Homebrew puts `carrier` and the `gh` its formula depends on.
public let homebrewBin = "/opt/homebrew/bin"
public let homebrewCarrier = homebrewBin + "/carrier"

/// Where `carrier` is: the "use this carrier" value as the person typed it (trimmed; blank is not set), else the Homebrew one when
/// it is executable, else nil. A saved value that does not run is not second-guessed here: the Health tab says so.
public func carrierPath(override: String, isExecutable: (String) -> Bool) -> String? {
    let saved = override.trimmingCharacters(in: .whitespacesAndNewlines)
    if saved.isEmpty == false { return (saved as NSString).expandingTildeInPath }
    return isExecutable(homebrewCarrier) ? homebrewCarrier : nil
}

/// Whether `carrier` has to be run by `node`: it is JavaScript or TypeScript source, like the repo's `main.ts`.
public func carrierNeedsNode(_ carrier: String) -> Bool { carrier.hasSuffix(".ts") || carrier.hasSuffix(".js") }

/// What to spawn to run `carrier` with `arguments`: `node <carrier> ...` for a script, the file itself for anything else.
public func carrierProgram(carrier: String, node: String, arguments: [String]) -> (program: String, arguments: [String]) {
    carrierNeedsNode(carrier) ? (node, [carrier] + arguments) : (carrier, arguments)
}

/// The PATH the engine and the chat host run with, and so the tools they start: the detected one with the directory of `node` first,
/// and `/opt/homebrew/bin` at the end when it is not in it, so the `gh` Homebrew installed is found from a shell that never loaded Homebrew.
/// With no detected PATH (the shell gave no answer) it starts from the system's, so `git` is still found.
public func enginePath(detected: String, node: String) -> String {
    var entries = (detected.isEmpty ? systemPath : detected).split(separator: ":", omittingEmptySubsequences: true).map(String.init)
    if node.hasPrefix("/") {
        let folder = (node as NSString).deletingLastPathComponent
        entries.removeAll { $0 == folder }
        entries.insert(folder, at: 0)
    }
    if entries.contains(homebrewBin) == false { entries.append(homebrewBin) }
    return entries.joined(separator: ":")
}

/// What the shell found; an empty one is a value not found.
public struct SetupSettings: Equatable {
    public var node = ""
    public var path = ""

    public init(node: String = "", path: String = "") {
        self.node = node
        self.path = path
    }

    /// The values the person has to look at: the ones that were not found.
    public var missing: [String] {
        [("node", node), ("PATH", path)]
            .filter { $0.1.isEmpty }.map(\.0)
    }
}

/// Saved in user defaults: what the shell found, and the "use this carrier" value. nil means no shell answer was saved yet: the only
/// time the shell is asked. The key is not the one the three-field setup used, so what that one saved is ignored, with no migration.
public struct SetupStore {
    private let defaults: UserDefaults
    private let key = "shellSetup"
    private let carrierKey = "engine.carrier"

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> SetupSettings? {
        guard let saved = defaults.dictionary(forKey: key) as? [String: String] else { return nil }
        return SetupSettings(node: saved["node"] ?? "", path: saved["path"] ?? "")
    }

    public func save(_ settings: SetupSettings) {
        defaults.set(["node": settings.node, "path": settings.path], forKey: key)
    }

    /// The advanced "use this carrier" value; empty when unset.
    public var carrierOverride: String {
        get { defaults.string(forKey: carrierKey) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: carrierKey) }
    }
}
