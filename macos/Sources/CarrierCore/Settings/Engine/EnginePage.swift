import Foundation

// The Engine page of Settings (docs/specs/engine-in-settings.md): its groups, rows, titles and descriptions as plain values. The view only
// draws this; the later groups of the page add themselves here.

/// The row a view has to draw for. The Starting rows are switches over an app preference; the Programs rows are `carrier`, `node`, the `PATH`
/// and the button that looks for the tools again; `orchestratorProfile` is a choice written to `engine.json`, the Files rows a button over a path.
/// The raw value is what the row is known by in Settings (its anchor), whatever its title says.
public enum EngineRowID: String, CaseIterable, Equatable {
    case startOnOpen, confirmStop
    case carrier, node, path, lookAgain
    case orchestratorProfile, carrierFolder, logs, startLog
}

/// A Files row's path: `shown` is in the person's words (`~`), `path` is what Reveal or Open acts on, and `exists` is false while there is nothing there yet.
public struct EngineFile: Equatable {
    public enum Action: Equatable { case reveal, open }
    public let shown: String
    public let path: String
    public let action: Action
    public let exists: Bool
    /// The button's words: its verb, or "Not created yet" (the button is disabled) while the path is missing.
    public func buttonTitle(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        Copy.engineFileButton(which: exists ? (action == .reveal ? .reveal : .open) : .missing, bundle: bundle, locale: locale)
    }
}

public struct EngineRow: Equatable {
    public let id: EngineRowID
    public let title: String
    public var detail: String
    /// The quiet monospaced line under the detail: a path, or "Not found" in its place.
    public var note: String?
    /// The `carrier` row only: the person set their own, so the row offers "Use the Homebrew one".
    public var offersHomebrew = false
    /// What is wrong with the value, shown in orange in the place of the detail
    public var problem: String?
    public var file: EngineFile?
}

/// What the Programs group says about, all of it read by the caller: the paths and versions are inputs so the model is tested without a window.
public struct EnginePrograms: Equatable {
    public var carrier: String?
    /// The person's own `carrier` is set ("Use another…" on the `carrier` row).
    public var carrierIsOwn: Bool
    public var carrierVersion: String?
    public var setup: SetupSettings
    public var nodeVersion: String?
    /// Something runs at the `carrier` path: a script exists, anything else is executable.
    public var carrierRuns: Bool
    /// The versions have been read; false while `--version` is still running.
    public var versionsRead: Bool

    public init(
        carrier: String?, carrierIsOwn: Bool, carrierVersion: String?, setup: SetupSettings, nodeVersion: String?, carrierRuns: Bool = true,
        versionsRead: Bool = true
    ) {
        self.carrier = carrier
        self.carrierIsOwn = carrierIsOwn
        self.carrierVersion = carrierVersion
        self.setup = setup
        self.nodeVersion = nodeVersion
        self.carrierRuns = carrierRuns
        self.versionsRead = versionsRead
    }
}

public struct EngineGroup: Equatable {
    public let id: String
    public let title: String
    public let rows: [EngineRow]
}

/// `configured` is whether the engine has a config file: without one, starting when the app opens does nothing and the row says so.
/// `programs` is what the Programs group shows, all of it read by the caller.
/// `identity` is what that file says about the GitHub identity, nil when there is no file or it cannot be read (the row is then disabled by the view).
/// `identityFailure` is why the last choice of identity was not saved; it is shown on that row.
/// `folder` is the Carrier folder; `exists` says whether a path is there (a folder or a file).
public func engineGroups(
    configured: Bool, programs: EnginePrograms, identity: EngineIdentity?, identityFailure: String? = nil, folder: String, home: String,
    exists: (String) -> Bool, bundle: Bundle? = nil, locale: Locale = .current
) -> [EngineGroup] {
    func file(_ id: EngineRowID, _ title: String, _ detail: String, _ path: String, _ action: EngineFile.Action) -> EngineRow {
        EngineRow(id: id, title: title, detail: detail, file: EngineFile(shown: tildePath(path, home: home), path: path, action: action, exists: exists(path)))
    }
    let places = ["CARRIER_HOME": folder]
    return [
        EngineGroup(id: "starting", title: Copy.engineGroupStarting(bundle: bundle, locale: locale), rows: [
            EngineRow(
                id: .startOnOpen, title: Copy.engineStartOnOpenTitle(bundle: bundle, locale: locale),
                detail: configured ? Copy.engineStartOnOpenDetail(bundle: bundle, locale: locale) : Copy.engineStartOnOpenNotConfigured(bundle: bundle, locale: locale)
            ),
            EngineRow(id: .confirmStop, title: Copy.engineConfirmStopTitle(bundle: bundle, locale: locale), detail: Copy.engineConfirmStopDetail(bundle: bundle, locale: locale)),
        ]),
        EngineGroup(id: "programs", title: Copy.engineGroupPrograms(bundle: bundle, locale: locale), rows: programRows(programs, bundle: bundle, locale: locale)),
        EngineGroup(id: "github-identity", title: Copy.engineGroupGitHub(bundle: bundle, locale: locale), rows: [
            EngineRow(
                id: .orchestratorProfile, title: Copy.engineProfileTitle(bundle: bundle, locale: locale),
                detail: configured ? Copy.engineProfileDetail(bundle: bundle, locale: locale) : Copy.engineProfileNotConfigured(bundle: bundle, locale: locale),
                problem: identityFailure ?? identityProblem(configured: configured, identity: identity, bundle: bundle, locale: locale)
            ),
        ]),
        EngineGroup(id: "files", title: Copy.engineGroupFiles(bundle: bundle, locale: locale), rows: [
            file(.carrierFolder, Copy.engineFolderTitle(bundle: bundle, locale: locale), Copy.engineFolderDetail(bundle: bundle, locale: locale), folder, .reveal),
            file(.logs, Copy.engineLogsTitle(bundle: bundle, locale: locale), Copy.engineLogsDetail(bundle: bundle, locale: locale), CarrierPlaces(environment: places, home: home).engineLogs, .reveal),
            file(
                .startLog, Copy.engineStartLogTitle(bundle: bundle, locale: locale), Copy.engineStartLogDetail(bundle: bundle, locale: locale),
                CarrierPlaces(environment: places, home: home).engineStartLog, .open),
        ]),
    ]
}

/// A file that is there but is not a JSON object says so; one that names an undeclared profile says it is kept.
private func identityProblem(configured: Bool, identity: EngineIdentity?, bundle: Bundle?, locale: Locale) -> String? {
    guard let identity else { return configured ? Copy.engineIdentityUnreadable(bundle: bundle, locale: locale) : nil }
    return identity.undeclared.map { Copy.engineIdentityUndeclared(name: $0, bundle: bundle, locale: locale) }
}

/// What a row says of a version: still reading, the version, or that the program did not answer (a problem).
private func versionLine(_ version: String?, read: Bool, program: String, bundle: Bundle?, locale: Locale) -> (detail: String?, problem: String?) {
    guard read else { return (Copy.engineVersionReading(bundle: bundle, locale: locale), nil) }
    guard let version else { return (nil, Copy.engineVersionNoAnswer(program: program, bundle: bundle, locale: locale)) }
    return (Copy.engineVersion(version: String(version.trimmingPrefix("v")), bundle: bundle, locale: locale), nil)
}

/// The programs' names are the commands, not words: the same in every language.
private let carrierProgram = "carrier", nodeProgram = "node", pathVariable = "PATH"

private func programRows(_ programs: EnginePrograms, bundle: Bundle?, locale: Locale) -> [EngineRow] {
    let setup = programs.setup
    let nodeFound = setup.node.isEmpty == false
    var carrierRow = EngineRow(id: .carrier, title: carrierProgram, detail: "", note: programs.carrier ?? Copy.engineNotFound(bundle: bundle, locale: locale), offersHomebrew: programs.carrierIsOwn)
    if let carrier = programs.carrier {
        // a script with no node is not run for its version: the node row already says what is missing
        let version = carrierNeedsNode(carrier) && nodeFound == false
            ? (detail: nil, problem: nil) : versionLine(programs.carrierVersion, read: programs.versionsRead, program: carrierProgram, bundle: bundle, locale: locale)
        carrierRow.detail = [programs.carrierIsOwn ? Copy.engineOwnCarrier(bundle: bundle, locale: locale) : nil, version.detail].compactMap { $0 }.joined(separator: " · ")
        carrierRow.problem = programs.carrierRuns ? version.problem : Copy.engineNothingRuns(bundle: bundle, locale: locale)
    }
    var nodeRow = EngineRow(id: .node, title: nodeProgram, detail: "", note: nodeFound ? setup.node : Copy.engineNotFound(bundle: bundle, locale: locale))
    if nodeFound {
        let version = versionLine(programs.nodeVersion, read: programs.versionsRead, program: nodeProgram, bundle: bundle, locale: locale)
        nodeRow.detail = version.detail ?? ""
        nodeRow.problem = version.problem
    }
    return [
        carrierRow,
        nodeRow,
        EngineRow(
            id: .path, title: pathVariable,
            detail: setup.path.isEmpty ? Copy.enginePathMissing(bundle: bundle, locale: locale) : Copy.enginePathDetail(bundle: bundle, locale: locale),
            note: enginePath(detected: setup.path, node: setup.node)
        ),
        EngineRow(
            id: .lookAgain, title: Copy.engineLookAgainTitle(bundle: bundle, locale: locale),
            detail: Copy.engineLookAgainDetail(bundle: bundle, locale: locale)
        ),
    ]
}
