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
        : HealthRow(title: "carrier", mark: .problem, detail: "Not found", tool: .carrier, state: .missing)

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
        return HealthSection(title: title, note: nil, rows: groupedChecks(checks))
    }
}

/// The doctor prints one check per tool, per login and per identity and repository; the tab shows one card for each of those kinds instead,
/// and any other check as it is. A card is as bad as its worst check, says what it covers while all are well and which checks are not when
/// not, with the first fix of the checks that have one.
func groupedChecks(_ checks: [DoctorCheck]) -> [HealthRow] {
    enum Kind: Hashable { case tools, logins, access, single(Int) }
    func kind(_ index: Int, _ name: String) -> Kind {
        if name.hasSuffix(" installed") { return .tools }
        if name.contains(" provider "), name.hasSuffix(" is logged in") { return .logins }
        if name.hasPrefix("forge agent ") { return .access }
        return .single(index)
    }
    var order: [Kind] = []
    var members: [Kind: [DoctorCheck]] = [:]
    for (index, check) in checks.enumerated() {
        let found = kind(index, check.name)
        if members[found] == nil { order.append(found) }
        members[found, default: []].append(check)
    }
    return order.map { found in
        let group = members[found]!
        let mark: HealthRow.Mark = group.contains { $0.status == .fail } ? .problem : group.contains { $0.status == .warn } ? .warning : .ok
        let fix = group.first { $0.fix != nil && $0.status != .ok }?.fix
        if case .single = found, let only = group.first {
            return HealthRow(title: only.name, mark: mark, detail: only.detail ?? "", fix: only.fix)
        }
        let title: String
        var covers: String
        switch found {
        case .tools:
            title = "Tools installed"
            covers = group.map { String($0.name.dropLast(" installed".count)) }.joined(separator: ", ")
        case .logins:
            title = "Provider logins"
            covers = group.map { $0.name.replacingOccurrences(of: " provider ", with: " ").replacingOccurrences(of: " is logged in", with: "") }.joined(separator: ", ")
        default:
            title = "Repository access"
            let words = group.map { $0.name.split(separator: " ").map(String.init) }
            let identities = Set(words.compactMap { $0.count > 2 ? $0[2] : nil }).count
            let repos = Set(words.compactMap(\.last)).count
            covers = "\(repos) \(repos == 1 ? "repository" : "repositories"), \(identities) \(identities == 1 ? "identity" : "identities")"
        }
        if mark == .ok { return HealthRow(title: title, mark: mark, detail: covers) }
        let bad = group.filter { $0.status != .ok }.map { "\($0.name)\($0.detail.map { ": \($0)" } ?? "")" }
        return HealthRow(title: title, mark: mark, detail: "\(bad.count) of \(group.count) not ok\n" + bad.joined(separator: "\n"), fix: fix)
    }
}
