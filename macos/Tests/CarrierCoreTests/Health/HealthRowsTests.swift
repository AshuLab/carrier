import Testing
@testable import CarrierCore

// The rows of the Health tab: what the host says of this Mac and what the app knows of Carrier.

/// `healthSections` in English.
private func sections(host: HostHealth?, facts: CarrierFacts, doctor: DoctorState = .idle) -> [HealthSection] {
    healthSections(host: host, facts: facts, doctor: doctor, bundle: english.bundle, locale: english.locale)
}

private let allWell = CarrierFacts(carrierFound: true, installedVersion: "1.4.0", hostRunning: true, hostVersion: "1.4.0", hostReportsHealth: true, configExists: true, engineRunning: true)

private func health(git: ToolState = .ready, gh: ToolState = .ready, claude: ToolState = .ready, codex: ToolState = .ready) -> HostHealth {
    HostHealth(git: git, gh: gh, agents: [
        .init(name: "claude", harness: "claude", state: claude), .init(name: "codex", harness: "codex", state: codex),
    ])
}

@Test func thisMacListsGitAndGhWithTheirStateAndNoAgentRows() throws {
    let mac = try #require(sections(host: health(gh: .signedOut, codex: .missing), facts: allWell).first)
    #expect(mac.title == "This Mac" && mac.note == nil)
    #expect(mac.rows.map(\.title) == ["git", "gh"])
    #expect(mac.rows.map(\.detail) == ["Ready", "Signed out"])
    #expect(mac.rows.map(\.mark) == [.ok, .problem])
}

@Test func aRowAsksTheFixedListAboutItsToolAndState() throws {
    let mac = try #require(sections(host: health(git: .missing, gh: .signedOut), facts: allWell).first)
    #expect(mac.rows[0].tool == .git && mac.rows[0].state == .missing)
    #expect(mac.rows[1].tool == .gh && mac.rows[1].state == .signedOut)
    #expect(healthFix(.agent(harness: "claude"), .signedOut)?.label == "claude auth login")
}

@Test func anUnknownProbeIsNeitherAProblemNorReady() throws {
    let mac = try #require(sections(host: health(gh: .unknown), facts: allWell).first)
    #expect(mac.rows[1].mark == .neutral && mac.rows[1].detail == "Could not check")
}

@Test func withoutHealthTheMacSaysWhyAndCarrierIsStillThere() {
    var tooOld = allWell
    tooOld.hostReportsHealth = false
    let old = sections(host: nil, facts: tooOld)
    #expect(old[0].rows.isEmpty && old[0].note?.contains("too old") == true)
    #expect(old[1].title == "Carrier" && old[1].rows.count == 3)

    // a host that lists `health` but has not answered (in flight, or the request failed) is not called old
    let pending = sections(host: nil, facts: allWell)[0]
    #expect(pending.rows.isEmpty && pending.note?.contains("too old") == false && pending.note?.contains("Check again") == true)

    var stopped = allWell
    stopped.hostRunning = false
    #expect(sections(host: nil, facts: stopped)[0].note?.contains("not running") == true)
}

@Test func carrierIsFoundWithItsVersionOrNot() {
    #expect(sections(host: nil, facts: allWell)[1].rows[0] == HealthRow(title: "carrier", mark: .ok, detail: "Found · version 1.4.0"))
    var facts = allWell
    facts.installedVersion = nil
    #expect(sections(host: nil, facts: facts)[1].rows[0].detail == "Found")
    facts.carrierFound = false
    let row = sections(host: nil, facts: facts)[1].rows[0]
    #expect(row.mark == .problem && row.detail.hasPrefix("Not found") && row.tool == .carrier && row.state == .missing)
}

@Test func theChatHostRunsStaleOrNot() {
    func host(_ facts: CarrierFacts) -> HealthRow { sections(host: nil, facts: facts)[1].rows[1] }
    #expect(host(allWell) == HealthRow(id: "chat-host", title: "Chat host", mark: .ok, detail: "Running · version 1.4.0"))
    var older = allWell
    older.hostVersion = "1.3.0"
    #expect(host(older).mark == .problem && host(older).detail.contains("Restart it"))
    var unreadable = allWell
    unreadable.installedVersion = nil
    #expect(host(unreadable).mark == .ok)
    var stopped = allWell
    stopped.hostRunning = false
    #expect(host(stopped) == HealthRow(id: "chat-host", title: "Chat host", mark: .problem, detail: "Not running"))
}

@Test func theEngineIsNotConfiguredStoppedOrRunning() {
    func engine(_ facts: CarrierFacts) -> HealthRow { sections(host: nil, facts: facts)[1].rows[2] }
    var facts = allWell
    #expect(engine(facts) == HealthRow(id: "engine", title: "Engine", mark: .ok, detail: "Running"))
    facts.engineRunning = false
    #expect(engine(facts) == HealthRow(id: "engine", title: "Engine", mark: .neutral, detail: "Configured, stopped"))
    facts.configExists = false
    #expect(engine(facts).mark == .problem && engine(facts).detail.contains("not configured"))
}

@Test func theEnginesSetupShowsAChecksWithItsStateDetailAndFixTextAsOneCard() {
    let checks = [
        DoctorCheck(name: "config", status: .ok), DoctorCheck(name: "labels", status: .warn, detail: "old", fix: "carrier init"),
        DoctorCheck(name: "token", status: .fail, detail: "missing", fix: "agent-forge add"),
    ]
    let section = sections(host: nil, facts: allWell, doctor: .checks(checks))[2]
    #expect(section.title == "Engine setup" && section.note == nil)
    #expect(section.rows.map(\.title) == ["config", "labels", "token"])
    #expect(section.rows.map(\.mark) == [.ok, .warning, .problem])
    #expect(section.rows.map(\.detail) == ["", "old", "missing"])
    #expect(section.rows.map(\.fix) == [nil, "carrier init", "agent-forge add"])
    #expect(section.rows.allSatisfy { $0.tool == nil })
}

@Test func theDoctorsToolLoginAndAccessChecksAreGroupedIntoOneCardEach() {
    let checks = [
        DoctorCheck(name: "git installed", status: .ok), DoctorCheck(name: "gh installed", status: .ok),
        DoctorCheck(name: "claude provider pro is logged in", status: .ok), DoctorCheck(name: "agy provider ai-pro is logged in", status: .ok),
        DoctorCheck(name: "author and reviewer are different identities", status: .ok),
        DoctorCheck(name: "forge agent a-agent can mint a token for acme/web", status: .ok),
        DoctorCheck(name: "forge agent b-agent can mint a token for acme/web", status: .ok),
        DoctorCheck(name: "forge agent a-agent can read acme/web", status: .ok),
        DoctorCheck(name: "forge agent a-agent can mint a token for acme/api", status: .ok),
    ]
    let rows = sections(host: nil, facts: allWell, doctor: .checks(checks))[2].rows
    #expect(rows.map(\.title) == ["Tools installed", "Provider logins", "author and reviewer are different identities", "Repository access"])
    #expect(rows.map(\.detail) == ["git, gh", "claude pro, agy ai-pro", "", "2 repositories, 2 identities"])
    #expect(rows.allSatisfy { $0.mark == .ok })
}

@Test func aFailedCheckIsGroupedByTheCodeOfItsDetailWhateverItsNameSays() {
    // names that differ from today's: only the code of the detail puts each failed check in its card
    let checks = [
        DoctorCheck(name: "first", status: .fail, detail: "not found on PATH", detailCode: "doctor.notOnPath"),
        DoctorCheck(name: "second", status: .fail, detail: "not signed in", detailCode: "doctor.loginMissing"),
        DoctorCheck(name: "third", status: .fail, detail: "no token", detailCode: "doctor.mintFailed"),
        DoctorCheck(name: "fourth", status: .fail, detail: "something", detailCode: "doctor.somethingNew"),
    ]
    let rows = sections(host: nil, facts: allWell, doctor: .checks(checks))[2].rows
    #expect(rows.map(\.title) == ["Tools installed", "Provider logins", "Repository access", "fourth"])
}

@Test func aGroupedCardIsAsBadAsItsWorstCheckAndNamesTheOnesThatAreNotOk() {
    let checks = [
        DoctorCheck(name: "git installed", status: .ok), DoctorCheck(name: "agy installed", status: .fail, detail: "not found", fix: "install agy"),
        DoctorCheck(name: "forge agent a-agent can read acme/web", status: .warn, detail: "slow"),
    ]
    let rows = sections(host: nil, facts: allWell, doctor: .checks(checks))[2].rows
    #expect(rows[0].title == "Tools installed" && rows[0].mark == .problem && rows[0].fix == "install agy")
    #expect(rows[0].detail == "1 of 2 not ok\nagy installed: not found")
    #expect(rows[1].title == "Repository access" && rows[1].mark == .warning && rows[1].fix == nil)
}

@Test func theEnginesSetupNeedsTheConfigAndRunsNothingWithoutOne() {
    var facts = allWell
    facts.configExists = false
    for doctor in [DoctorState.idle, .running, .checks([DoctorCheck(name: "x", status: .ok)])] {
        let section = sections(host: nil, facts: facts, doctor: doctor)[2]
        #expect(section.rows.isEmpty && section.note?.contains("needs the config") == true)
    }
}

@Test func theEnginesSetupSaysItIsRunningAndShowsAnUnknownDoctorAsSuchWithItsReason() {
    #expect(sections(host: nil, facts: allWell, doctor: .running)[2].note?.contains("Running") == true)
    let row = sections(host: nil, facts: allWell, doctor: .unknown("did not finish"))[2].rows[0]
    #expect(row.mark == .neutral && row.detail == "Could not check: did not finish")
}

@Test func theRowsAndSectionsSaySpanishWhatTheyKnow() throws {
    func spanishSections(host: HostHealth?, facts: CarrierFacts, doctor: DoctorState = .idle) -> [HealthSection] {
        healthSections(host: host, facts: facts, doctor: doctor, bundle: spanish.bundle, locale: spanish.locale)
    }
    let mac = try #require(spanishSections(host: health(git: .missing, gh: .signedOut, claude: .unknown), facts: allWell).first)
    #expect(mac.title == "Este Mac" && mac.rows.map(\.detail) == ["No instalado", "Sin iniciar sesión"])
    #expect(try #require(spanishSections(host: health(gh: .unknown), facts: allWell).first).rows[1].detail == "No se pudo comprobar")
    #expect(try #require(spanishSections(host: health(), facts: allWell).first).rows[0].detail == "Listo")

    var stopped = allWell
    stopped.hostRunning = false
    #expect(spanishSections(host: nil, facts: stopped)[0].note == "El host de chat no se está ejecutando, así que no se comprobó este Mac.")
    var tooOld = allWell
    tooOld.hostReportsHealth = false
    #expect(spanishSections(host: nil, facts: tooOld)[0].note == "El host de chat es demasiado antiguo para comprobar este Mac. Reinícialo para usar el Carrier instalado.")
    #expect(spanishSections(host: nil, facts: allWell)[0].note == "Este Mac aún no se ha comprobado, o la comprobación falló. Pulsa Comprobar de nuevo.")

    let carrier = spanishSections(host: nil, facts: allWell)[1]
    #expect(carrier.title == "Carrier" && carrier.rows[0].detail == "Encontrado · versión 1.4.0")
    #expect(carrier.rows[1] == HealthRow(id: "chat-host", title: "Host de chat", mark: .ok, detail: "En marcha · versión 1.4.0"))
    #expect(carrier.rows[2] == HealthRow(id: "engine", title: "Motor", mark: .ok, detail: "En marcha"))
    var older = allWell
    older.hostVersion = "1.3.0"
    #expect(spanishSections(host: nil, facts: older)[1].rows[1].detail == "En marcha en la versión 1.3.0, más antigua que la instalada (1.4.0). Reinícialo para actualizar.")
    var off = allWell
    (off.hostRunning, off.engineRunning, off.carrierFound, off.installedVersion) = (false, false, false, nil)
    let rows = spanishSections(host: nil, facts: off)[1].rows
    #expect(rows.map(\.detail) == ["No encontrado", "No se está ejecutando", "Configurado, detenido"])
}

@Test func theEnginesSetupSaysSpanishWhatItNeedsAndWhatItFound() {
    func setup(_ facts: CarrierFacts, _ doctor: DoctorState) -> HealthSection { healthSections(host: nil, facts: facts, doctor: doctor, bundle: spanish.bundle, locale: spanish.locale)[2] }
    var noConfig = allWell
    noConfig.configExists = false
    #expect(setup(noConfig, .idle).note == "La configuración del motor necesita su archivo: no hay engine.json en la carpeta de Carrier.")
    #expect(setup(allWell, .idle).title == "Configuración del motor" && setup(allWell, .idle).note == "Aún sin comprobar.")
    #expect(setup(allWell, .running).note == "Ejecutando carrier doctor…")
    #expect(setup(allWell, .unknown("no terminó")).rows[0].detail == "No se pudo comprobar: no terminó")
    #expect(setup(allWell, .refused("Invalid config")).rows[0].detail == "Carrier rechaza la configuración: Invalid config")
}

@Test func theGroupedChecksSaySpanishWhatTheyCoverWithItsPlurals() {
    func rows(_ checks: [DoctorCheck]) -> [HealthRow] { healthSections(host: nil, facts: allWell, doctor: .checks(checks), bundle: spanish.bundle, locale: spanish.locale)[2].rows }
    let ok = [
        DoctorCheck(name: "git installed", status: .ok), DoctorCheck(name: "claude provider pro is logged in", status: .ok),
        DoctorCheck(name: "forge agent a-agent can mint a token for acme/web", status: .ok),
        DoctorCheck(name: "forge agent b-agent can mint a token for acme/api", status: .ok),
    ]
    #expect(rows(ok).map(\.title) == ["Herramientas instaladas", "Inicios de sesión de proveedores", "Acceso a repositorios"])
    #expect(rows(ok)[2].detail == "2 repositorios, 2 identidades")
    // the one of each: the singular forms of both plurals
    #expect(rows([DoctorCheck(name: "forge agent a-agent can mint a token for acme/web", status: .ok)])[0].detail == "1 repositorio, 1 identidad")
    let bad = rows([DoctorCheck(name: "git installed", status: .ok), DoctorCheck(name: "agy installed", status: .fail, detail: "no está", fix: "instálalo")])
    #expect(bad[0].detail == "1 de 2 con problemas\nagy installed: no está" && bad[0].fix == "instálalo")
}

@Test func theGroupedChecksSayEnglishWhatTheyCoverInTheSingular() {
    let row = sections(host: nil, facts: allWell, doctor: .checks([DoctorCheck(name: "forge agent a-agent can mint a token for acme/web", status: .ok)]))[2].rows[0]
    #expect(row.detail == "1 repository, 1 identity")
}
