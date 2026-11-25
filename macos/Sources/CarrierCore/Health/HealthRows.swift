import Foundation

// The rows of the Health tab (docs/specs/health-check-in-the-app.md): a pure function of what the app already knows, one section per
// layer. "This Mac" is the host's reply, "Carrier" is what only the app knows, "Engine setup" is the doctor's checks (`DoctorStore`).

/// The names of the commands a row is titled by: what is typed in a shell, the same in every language.
private let carrierCommand = "carrier"
private let carrierDoctorCommand = "carrier doctor"

public struct HealthRow: Equatable {
    /// How the row reads: `ok` is green, `problem` needs the person, `neutral` is neither (not checked, or stopped on purpose).
    public enum Mark: Equatable { case ok, warning, problem, neutral }

    /// What the search finds the row by (`SettingsIndex`), whatever its title says; nil for a row that is not searched.
    public let id: String?
    public let title: String
    public let mark: Mark
    public let detail: String
    /// What the fixed list (`healthFix`) is asked about, with `state`; nil for a row with no fix.
    public let tool: HealthTool?
    public let state: ToolState
    /// What the doctor says to do, shown as text and never run.
    public let fix: String?

    public init(id: String? = nil, title: String, mark: Mark, detail: String, tool: HealthTool? = nil, state: ToolState = .ready, fix: String? = nil) {
        self.id = id
        self.title = title
        self.mark = mark
        self.detail = detail
        self.tool = tool
        self.state = state
        self.fix = fix
    }
}

public struct HealthSection: Equatable {
    public let id: String
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

private func macRow(_ title: String, _ tool: HealthTool, _ state: ToolState, bundle: Bundle?, locale: Locale) -> HealthRow {
    switch state {
    case .ready: HealthRow(title: title, mark: .ok, detail: Copy.healthReady(bundle: bundle, locale: locale), tool: tool, state: state)
    case .missing: HealthRow(title: title, mark: .problem, detail: Copy.healthNotInstalled(bundle: bundle, locale: locale), tool: tool, state: state)
    case .signedOut: HealthRow(title: title, mark: .problem, detail: Copy.healthSignedOut(bundle: bundle, locale: locale), tool: tool, state: state)
    case .unknown: HealthRow(title: title, mark: .neutral, detail: Copy.healthCouldNotCheck(bundle: bundle, locale: locale), tool: tool, state: state)
    }
}

/// `host` is the last reply of `health`; nil is no reply yet: a host that is not running, one too old to report it, or one whose answer is still on its way or failed. Each says so in place of the rows.
public func healthSections(host: HostHealth?, facts: CarrierFacts, doctor: DoctorState = .idle, bundle: Bundle? = nil, locale: Locale = .current) -> [HealthSection] {
    let mac: HealthSection
    if let host {
        mac = HealthSection(
            id: "this-mac", title: Copy.healthThisMac(bundle: bundle, locale: locale), note: nil,
            rows: [macRow("git", .git, host.git, bundle: bundle, locale: locale), macRow("gh", .gh, host.gh, bundle: bundle, locale: locale)]
        )
    } else {
        let note = if facts.hostRunning == false {
            Copy.healthHostNotRunning(bundle: bundle, locale: locale)
        } else if facts.hostReportsHealth == false {
            Copy.healthHostTooOld(bundle: bundle, locale: locale)
        } else {
            Copy.healthMacNotChecked(bundle: bundle, locale: locale)
        }
        mac = HealthSection(id: "this-mac", title: Copy.healthThisMac(bundle: bundle, locale: locale), note: note, rows: [])
    }

    let found = facts.installedVersion.map { Copy.healthCarrierFoundVersion(version: $0, bundle: bundle, locale: locale) } ?? Copy.healthCarrierFound(bundle: bundle, locale: locale)
    let carrier = facts.carrierFound
        ? HealthRow(title: carrierCommand, mark: .ok, detail: found)
        : HealthRow(title: carrierCommand, mark: .problem, detail: Copy.healthCarrierNotFound(bundle: bundle, locale: locale), tool: .carrier, state: .missing)

    let chatHost = Copy.healthChatHost(bundle: bundle, locale: locale)

    let hostRow: HealthRow
    if facts.hostRunning == false {
        hostRow = HealthRow(id: "chat-host", title: chatHost, mark: .problem, detail: Copy.healthHostStopped(bundle: bundle, locale: locale))
    } else if let running = facts.hostVersion, let installed = facts.installedVersion,
        hostReplacement(running: running, installed: installed, working: false) != .keep
    {
        hostRow = HealthRow(id: "chat-host", title: chatHost, mark: .problem, detail: Copy.healthHostOlder(running: running, installed: installed, bundle: bundle, locale: locale))
    } else {
        hostRow = HealthRow(id: "chat-host", title: chatHost, mark: .ok, detail: facts.hostVersion.map { Copy.healthRunningVersion(version: $0, bundle: bundle, locale: locale) } ?? Copy.healthRunning(bundle: bundle, locale: locale))
    }

    let engine: HealthRow
    let engineTitle = Copy.healthEngine(bundle: bundle, locale: locale)
    if let notConfigured = engineNotConfiguredNotice(configExists: facts.configExists, bundle: bundle, locale: locale) {
        engine = HealthRow(id: "engine", title: engineTitle, mark: .problem, detail: notConfigured)
    } else if facts.engineRunning {
        engine = HealthRow(id: "engine", title: engineTitle, mark: .ok, detail: Copy.healthRunning(bundle: bundle, locale: locale))
    } else {
        engine = HealthRow(id: "engine", title: engineTitle, mark: .neutral, detail: Copy.healthConfiguredStopped(bundle: bundle, locale: locale))
    }

    return [
        mac, HealthSection(id: "carrier", title: Copy.appName(bundle: bundle, locale: locale), note: nil, rows: [carrier, hostRow, engine]),
        setupSection(doctor, configExists: facts.configExists, bundle: bundle, locale: locale),
    ]
}

/// The engine's setup: the doctor's checks, or one line in place of them when it needs the config, is running, or could not answer.
private func setupSection(_ doctor: DoctorState, configExists: Bool, bundle: Bundle?, locale: Locale) -> HealthSection {
    let title = Copy.healthEngineSetup(bundle: bundle, locale: locale)
    guard configExists else {
        return HealthSection(id: "engine-setup", title: title, note: Copy.healthSetupNeedsConfig(bundle: bundle, locale: locale), rows: [])
    }
    switch doctor {
    case .idle: return HealthSection(id: "engine-setup", title: title, note: Copy.healthSetupNotChecked(bundle: bundle, locale: locale), rows: [])
    case .running: return HealthSection(id: "engine-setup", title: title, note: Copy.healthSetupRunning(bundle: bundle, locale: locale), rows: [])
    case .unknown(let reason):
        return HealthSection(id: "engine-setup", title: title, note: nil, rows: [HealthRow(title: carrierDoctorCommand, mark: .neutral, detail: Copy.healthDoctorCouldNotCheck(reason: reason, bundle: bundle, locale: locale))])
    case .refused(let reason):
        return HealthSection(id: "engine-setup", title: title, note: nil, rows: [HealthRow(title: carrierDoctorCommand, mark: .neutral, detail: Copy.healthDoctorRefused(reason: reason, bundle: bundle, locale: locale))])
    case .checks(let checks):
        return HealthSection(id: "engine-setup", title: title, note: nil, rows: groupedChecks(checks, bundle: bundle, locale: locale))
    }
}

/// The doctor prints one check per tool, per login and per identity and repository; the tab shows one card for each of those kinds instead,
/// and any other check as it is. A card is as bad as its worst check, says what it covers while all are well and which checks are not when
/// not, with the first fix of the checks that have one.
func groupedChecks(_ checks: [DoctorCheck], bundle: Bundle? = nil, locale: Locale = .current) -> [HealthRow] {
    enum Kind: Hashable { case tools, logins, access, single(Int) }
    func kind(_ index: Int, _ check: DoctorCheck) -> Kind {
        // a check that failed says what it is by the code of its detail; one that passed has none, and its name says it
        switch check.detailCode {
        case "doctor.notOnPath": return .tools
        case "doctor.loginMissing", "doctor.loginMissingAt", "doctor.loginMissingInEnvironment", "doctor.loginCheckFailedAt", "doctor.loginCheckFailedInEnvironment", "doctor.agyLoginUnknown", "doctor.agyNotRunnable":
            return .logins
        case "doctor.mintFailed": return .access
        default: break
        }
        let name = check.name
        if name.hasSuffix(" installed") { return .tools }
        if name.contains(" provider "), name.hasSuffix(" is logged in") { return .logins }
        if name.hasPrefix("forge agent ") { return .access }
        return .single(index)
    }
    var order: [Kind] = []
    var members: [Kind: [DoctorCheck]] = [:]
    for (index, check) in checks.enumerated() {
        let found = kind(index, check)
        if members[found] == nil { order.append(found) }
        members[found, default: []].append(check)
    }
    return order.map { found in
        let group = members[found]!
        let mark: HealthRow.Mark = group.contains { $0.status == .fail } ? .problem : group.contains { $0.status == .warn } ? .warning : .ok
        let fix = group.first { $0.fix != nil && $0.status != .ok }?.shownFix(bundle: bundle, locale: locale)
        if case .single = found, let only = group.first {
            return HealthRow(title: only.name, mark: mark, detail: only.shownDetail(bundle: bundle, locale: locale) ?? "", fix: only.shownFix(bundle: bundle, locale: locale))
        }
        let title: String
        var covers: String
        switch found {
        case .tools:
            title = Copy.healthToolsInstalled(bundle: bundle, locale: locale)
            covers = group.map { String($0.name.dropLast(" installed".count)) }.joined(separator: ", ")
        case .logins:
            title = Copy.healthProviderLogins(bundle: bundle, locale: locale)
            covers = group.map { $0.name.replacingOccurrences(of: " provider ", with: " ").replacingOccurrences(of: " is logged in", with: "") }.joined(separator: ", ")
        default:
            title = Copy.healthRepositoryAccess(bundle: bundle, locale: locale)
            let words = group.map { $0.name.split(separator: " ").map(String.init) }
            let identities = Set(words.compactMap { $0.count > 2 ? $0[2] : nil }).count
            let repos = Set(words.compactMap(\.last)).count
            covers = Copy.healthAccessCovers(repos: repos, identities: identities, bundle: bundle, locale: locale)
        }
        if mark == .ok { return HealthRow(title: title, mark: mark, detail: covers) }
        let bad = group.filter { $0.status != .ok }.map { "\($0.name)\($0.shownDetail(bundle: bundle, locale: locale).map { ": \($0)" } ?? "")" }
        return HealthRow(title: title, mark: mark, detail: Copy.healthNotOk(bad: bad.count, total: group.count, bundle: bundle, locale: locale) + "\n" + bad.joined(separator: "\n"), fix: fix)
    }
}
