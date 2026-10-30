import Foundation

// The rows of the Health tab (docs/specs/health-check-in-the-app.md): a pure function of what the app already knows, one section per
// layer. "This Mac" is the host's reply, "Carrier" is what only the app knows, "Engine setup" is the doctor's checks (`DoctorStore`).

public struct HealthRow: Equatable {
    /// How the row reads: `ok` is green, `problem` needs the person, `neutral` is neither (not checked, or stopped on purpose).
    public enum Mark: Equatable { case ok, warning, problem, neutral }

    public let title: String
    public let mark: Mark
    public let detail: String
    /// What the fixed list (`healthFix`) is asked about, with `state`; nil for a row with no fix.
    public let tool: HealthTool?
    public let state: ToolState
    /// What the doctor says to do, shown as text and never run.
    public let fix: String?

    public init(title: String, mark: Mark, detail: String, tool: HealthTool? = nil, state: ToolState = .ready, fix: String? = nil) {
        self.title = title
        self.mark = mark
        self.detail = detail
        self.tool = tool
        self.state = state
        self.fix = fix
    }
}

public struct HealthSection: Equatable {
    public let title: String
    /// Said in place of the rows when the layer could not be checked.
    public let note: String?
    public let rows: [HealthRow]
}

/// What the app knows of Carrier itself.
public struct CarrierFacts: Equatable {
    public var carrierFound: Bool
    /// What `carrier --version` printed; nil when it could not be read.
    public var installedVersion: String?
    public var hostRunning: Bool
    public var hostVersion: String?
    /// Whether the running host's hello lists `health`; false is a host too old to be asked.
    public var hostReportsHealth: Bool
    public var configExists: Bool
    public var engineRunning: Bool

    public init(carrierFound: Bool, installedVersion: String?, hostRunning: Bool, hostVersion: String?, hostReportsHealth: Bool, configExists: Bool, engineRunning: Bool) {
        self.carrierFound = carrierFound
        self.installedVersion = installedVersion
        self.hostRunning = hostRunning
        self.hostVersion = hostVersion
        self.hostReportsHealth = hostReportsHealth
        self.configExists = configExists
        self.engineRunning = engineRunning
    }
}

private func macRow(_ title: String, _ tool: HealthTool, _ state: ToolState) -> HealthRow {
    switch state {
    case .ready: HealthRow(title: title, mark: .ok, detail: "Ready", tool: tool, state: state)
    case .missing: HealthRow(title: title, mark: .problem, detail: "Not installed", tool: tool, state: state)
    case .signedOut: HealthRow(title: title, mark: .problem, detail: "Signed out", tool: tool, state: state)
    case .unknown: HealthRow(title: title, mark: .neutral, detail: "Could not check", tool: tool, state: state)
    }
}

/// `host` is the last reply of `health`; nil is no reply yet: a host that is not running, one too old to report it, or one whose answer is still on its way or failed. Each says so in place of the rows.
public func healthSections(host: HostHealth?, facts: CarrierFacts, doctor: DoctorState = .idle) -> [HealthSection] {
    let mac: HealthSection
    if let host {
        mac = HealthSection(
            title: "This Mac", note: nil,
            rows: [macRow("git", .git, host.git), macRow("gh", .gh, host.gh)]
                + host.agents.map { macRow($0.name, .agent(harness: $0.harness), $0.state) }
        )
    } else {
        let note = if facts.hostRunning == false {
            "The chat host is not running, so this Mac was not checked."
        } else if facts.hostReportsHealth == false {
            "The chat host is too old to check this Mac. Restart it to use the installed Carrier."
        } else {
            "This Mac has not been checked yet, or the check failed. Press Check again."
        }
        mac = HealthSection(title: "This Mac", note: note, rows: [])
    }

    let versionLine = facts.installedVersion.map { " · version \($0)" } ?? ""
    let carrier = facts.carrierFound
        ? HealthRow(title: "carrier", mark: .ok, detail: "Found" + versionLine)
        : HealthRow(title: "carrier", mark: .problem, detail: "Not found. Set its path in the Engine tab.")

    let hostRow: HealthRow
    if facts.hostRunning == false {
        hostRow = HealthRow(title: "Chat host", mark: .problem, detail: "Not running")
    } else if let running = facts.hostVersion, let installed = facts.installedVersion,
        hostReplacement(running: running, installed: installed, working: false) != .keep
    {
        hostRow = HealthRow(title: "Chat host", mark: .problem, detail: "Running version \(running), older than the installed \(installed). Restart it to update.")
    } else {
        hostRow = HealthRow(title: "Chat host", mark: .ok, detail: "Running" + (facts.hostVersion.map { " · version \($0)" } ?? ""))
    }

    let engine: HealthRow
    if let notConfigured = engineNotConfiguredNotice(configExists: facts.configExists) {
        engine = HealthRow(title: "Engine", mark: .problem, detail: notConfigured)
    } else if facts.engineRunning {
        engine = HealthRow(title: "Engine", mark: .ok, detail: "Running")
    } else {
        engine = HealthRow(title: "Engine", mark: .neutral, detail: "Configured, stopped")
    }

    return [mac, HealthSection(title: "Carrier", note: nil, rows: [carrier, hostRow, engine]), setupSection(doctor, configExists: facts.configExists)]
}

/// The engine's setup: the doctor's checks, or one line in place of them when it needs the config, is running, or could not answer.
private func setupSection(_ doctor: DoctorState, configExists: Bool) -> HealthSection {
    let title = "Engine setup"
    guard configExists else {
        return HealthSection(title: title, note: "The engine's setup needs the config: there is no config.json in the Carrier folder.", rows: [])
    }
    switch doctor {
    case .idle: return HealthSection(title: title, note: "Not checked yet.", rows: [])
    case .running: return HealthSection(title: title, note: "Running carrier doctor…", rows: [])
    case .unknown(let reason):
        return HealthSection(title: title, note: nil, rows: [HealthRow(title: "carrier doctor", mark: .neutral, detail: "Could not check: \(reason)")])
    case .checks(let checks):
        return HealthSection(title: title, note: nil, rows: checks.map { check in
            let mark: HealthRow.Mark = switch check.status { case .ok: .ok; case .warn: .warning; case .fail: .problem }
            return HealthRow(title: check.name, mark: mark, detail: check.detail ?? "", fix: check.fix)
        })
    }
}
