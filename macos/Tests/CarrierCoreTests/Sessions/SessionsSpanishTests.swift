import Foundation
import Testing

@testable import CarrierCore

// The Sessions area in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish words, and every plural and select
// it uses has a Spanish case asserted. The English words are asserted in the other files of this folder, with `english`.

private let es = (bundle: spanish.bundle, locale: spanish.locale)
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func row(
    _ id: String, workspace: String = "web", state: SessionState = .idle, ago: TimeInterval = 60, archived: Bool = false, asleep: Bool = false,
    unread: Bool = false
) -> SessionRow {
    SessionRow(
        id: id, title: "t\(id)", workspace: workspace, agent: "claude", state: state, updatedAt: now.addingTimeInterval(-ago), archived: archived,
        asleep: asleep, unread: unread
    )
}

// MARK: empty states, statuses and the pull request

@Test func everyEmptyStateSaysItsWordsInSpanish() {
    for state in EmptyState.allCases {
        #expect(state.title(bundle: es.bundle, locale: es.locale) != state.title(bundle: english.bundle, locale: english.locale), "\(state)")
        #expect(state.line(bundle: es.bundle, locale: es.locale) != state.line(bundle: english.bundle, locale: english.locale), "\(state)")
    }
    #expect(EmptyState.noSessions.title(bundle: es.bundle, locale: es.locale) == "Aún no hay sesiones")
    #expect(EmptyState.noSessions.line(bundle: es.bundle, locale: es.locale) == "Las sesiones que inicies aparecen aquí.")
    #expect(EmptyState.noSessionsMatch.title(bundle: es.bundle, locale: es.locale) == "Ninguna sesión coincide")
    #expect(EmptyState.nothingArchived.title(bundle: es.bundle, locale: es.locale) == "Nada archivado")
    #expect(EmptyState.noEpics.line(bundle: es.bundle, locale: es.locale).contains("solve:epic:ready"))
    #expect(EmptyState.noResultsLine(for: "zzz", bundle: es.bundle, locale: es.locale) == "Nada coincide con «zzz»")
}

@Test func theFiveStatusesAreSaidInSpanish() {
    #expect(SessionStatus.allCases.map { $0.title(bundle: es.bundle, locale: es.locale) } == ["Te necesita", "Trabajando", "Sin leer", "Inactiva", "Dormida"])
}

@Test func aPullRequestsChipAndItsSpokenWordsAreSpanish() {
    func pr(_ state: PullRequestState, _ checks: PullRequestChecks? = nil) -> SessionPullRequest {
        SessionPullRequest(number: 412, url: "https://example.test/412", state: state, checks: checks)
    }
    #expect(pr(.draft).chipText(bundle: es.bundle, locale: es.locale) == "#412 · Borrador")
    #expect(pr(.open).chipText(bundle: es.bundle, locale: es.locale) == "#412")
    #expect(pr(.open, .passing).chipText(bundle: es.bundle, locale: es.locale) == "#412 · ✓")
    #expect(pr(.open, .failing).chipText(bundle: es.bundle, locale: es.locale) == "#412 · CI ✕")
    #expect(pr(.open, .pending).chipText(bundle: es.bundle, locale: es.locale) == "#412 · CI en curso")
    #expect(pr(.merged).chipText(bundle: es.bundle, locale: es.locale) == "#412 · Fusionado")
    #expect(pr(.closed).chipText(bundle: es.bundle, locale: es.locale) == "#412 · Cerrado")
    #expect(pr(.open, .passing).spoken(bundle: es.bundle, locale: es.locale) == "Pull request 412, abierto, checks aprobados")
    #expect(pr(.open, .failing).spoken(bundle: es.bundle, locale: es.locale) == "Pull request 412, abierto, checks fallidos")
    #expect(pr(.draft, .pending).spoken(bundle: es.bundle, locale: es.locale) == "Pull request 412, borrador, checks en curso")
    #expect(pr(.merged).spoken(bundle: es.bundle, locale: es.locale) == "Pull request 412, fusionado")
    #expect(pr(.closed).spoken(bundle: es.bundle, locale: es.locale) == "Pull request 412, cerrado")
}

@Test func theBackgroundWorkLinesAreSpanishInTheirSingularAndPluralCases() {
    let one = [BackgroundTask(id: "1", kind: "shell", description: "pnpm build")]
    let three = one + [BackgroundTask(id: "2", kind: "shell", description: "pnpm test"), BackgroundTask(id: "3", kind: "shell", description: "")]
    #expect(backgroundWords(one, tick: 0, bundle: es.bundle, locale: es.locale) == "Esperando a pnpm build")
    #expect(backgroundCount(one, bundle: es.bundle, locale: es.locale) == nil)
    #expect(backgroundCount(three, bundle: es.bundle, locale: es.locale) == "· 3 tareas")
    #expect(Copy.sessionBackgroundCount(count: 1, bundle: es.bundle, locale: es.locale) == "· 1 tarea")
    #expect(waitingOnText(one, bundle: es.bundle, locale: es.locale) == "Esperando a pnpm build")
    #expect(waitingOnText(Array(three.prefix(2)), bundle: es.bundle, locale: es.locale) == "Esperando a pnpm build y 1 más")
    #expect(waitingOnText(three, bundle: es.bundle, locale: es.locale) == "Esperando a pnpm build y 2 más")
}

@Test func theBackgroundProcessesOfARowAreSpokenInSpanishInSingularAndPlural() {
    let process = { (id: String) in BackgroundTask(id: id, kind: "local_bash", description: "pnpm dev", agentWork: false) }
    func spoken(_ count: Int) -> String? {
        var processes = row("p")
        processes.background = (1...count).map { process("\($0)") }
        return SessionRowContent(processes, showsWorkspace: false, parts: SessionRowParts(), now: now).processesSpoken(bundle: es.bundle, locale: es.locale)
    }
    #expect(spoken(1) == "1 proceso en segundo plano")
    #expect(spoken(2) == "2 procesos en segundo plano")
    #expect(Copy.chatPeekRunning(bundle: es.bundle, locale: es.locale) == "En ejecución")
}

// MARK: the lists

@Test func theOpenCountsNameIsSpanishInSingularAndPlural() {
    #expect(Sessions(rows: [row("a")]).openLabel(bundle: es.bundle, locale: es.locale) == "1 sesión abierta")
    #expect(Sessions(rows: [row("a"), row("b"), row("c", archived: true)]).openLabel(bundle: es.bundle, locale: es.locale) == "2 sesiones abiertas")
}

@Test func theGroupsOfTheListsAreTitledInSpanish() {
    let utc = { () -> Calendar in var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    let midnight = Date(timeIntervalSince1970: 20_000 * 86400)
    let noon = midnight.addingTimeInterval(15 * 3600)
    func at(_ id: String, _ date: Date, archived: Bool = false) -> SessionRow {
        SessionRow(id: id, title: id, workspace: "w", agent: "claude", state: .idle, updatedAt: date, archived: archived)
    }
    let aged = [at("a", noon), at("b", midnight.addingTimeInterval(-3600)), at("c", midnight.addingTimeInterval(-3 * 86400)), at("d", midnight.addingTimeInterval(-30 * 86400))]
    #expect(sessionGroups(aged, by: .age, now: noon, calendar: utc, bundle: es.bundle, locale: es.locale).map(\.title) == ["Hoy", "Ayer", "Últimos 7 días", "Anteriores"])
    let archived = [at("a", noon, archived: true), at("d", midnight.addingTimeInterval(-30 * 86400), archived: true)]
    #expect(archivedGroups(archived, now: noon, calendar: utc, bundle: es.bundle, locale: es.locale).map(\.title) == ["Hoy", "Anteriores"])
    let states = [row("a", state: .waiting), row("b", state: .working), row("c", unread: true), row("d"), row("e", asleep: true)]
    #expect(
        sessionGroups(states, by: .status, now: now, bundle: es.bundle, locale: es.locale).map(\.title)
            == ["Te necesita", "Trabajando", "Sin leer", "Inactiva", "Dormida"]
    )
    #expect(sessionGroups(states, pinned: ["a"], now: now, bundle: es.bundle, locale: es.locale).first?.title == "Fijadas")
}

@Test func theSessionsPageSaysItsSubtitleInSpanishForEachShapeAndPlural() {
    let sample = [row("a", state: .working), row("b", state: .waiting), row("c"), row("d"), row("x", archived: true)]
    func page(_ rows: [SessionRow], query: String = "", filter: SessionFilter = SessionFilter()) -> SessionsPage {
        sessionsPage(rows, query: query, filter: filter, now: now, bundle: es.bundle, locale: es.locale)
    }
    #expect(page(sample).subtitle == "4 activas · 1 te espera")
    #expect(page([sample[0], sample[1], row("w", state: .waiting)]).subtitle == "3 activas · 2 te esperan")
    #expect(page([sample[0], sample[2]]).subtitle == "2 activas")
    #expect(page([sample[2]]).subtitle == "1 activa")
    #expect(page([sample[4]]).subtitle == "")
    #expect(page([sample[0], sample[2], sample[3]], filter: SessionFilter(statuses: [.working])).subtitle == "1 de 3")
    #expect(page(sample, filter: SessionFilter(statuses: [.needsYou])).subtitle == "1 de 4 · 1 te espera")
    #expect(page(sample, query: "t").subtitle == "5 resultados")
    #expect(page(sample, query: "td").subtitle == "1 resultado")
    #expect(page(sample, query: "t").groups.map(\.title) == ["Resultados"])
    #expect(page(sample, query: "zzz").emptyState == .noSessionsMatch)
}

// MARK: the Agent output list

private func section(
    _ state: SessionSection.State = .done, id: String = "a", role: String = "Constructor", place: String = "Ship", profile: String? = nil,
    account: String? = nil, model: String? = nil, counts: SessionCounts? = nil, time: String? = "31m", result: ResultCard? = nil, duration: Int? = nil
) -> SessionSection {
    SessionSection(
        id: id, state: state, agent: "Claude", initial: "C", role: role, place: place, counts: counts, timeLabel: time, openByDefault: false,
        result: result, engineRole: "author", profile: profile, account: account, model: model, durationMs: duration
    )
}

@Test func aResultAndItsVerdictAreSaidInSpanish() {
    func card(_ outcome: String, ci: String? = nil) -> ResultCard? {
        resultCard(
            SessionResult(outcome: outcome, summary: "s", verification: ci.map { .init(ci: $0, evidence: "e") }, reason: nil), bundle: es.bundle, locale: es.locale
        )
    }
    #expect(card("completed")?.outcome == "Completado")
    #expect(card("changes_requested")?.outcome == "Cambios solicitados")
    #expect(card("needs_human")?.outcome == "Necesita a una persona")
    #expect(card("gave_up")?.outcome == "Gave Up")
    #expect(ciVerdictText("passed", bundle: es.bundle, locale: es.locale) == "CI superado")
    #expect(ciVerdictText("absent", bundle: es.bundle, locale: es.locale) == "Sin CI")
    #expect(ciVerdictText("flaky", bundle: es.bundle, locale: es.locale) == "CI flaky")
}

@Test func theRolesPlacesAndSinceOfTheSessionsAreSpanish() {
    func session(_ id: String, _ stage: String, round: Int? = nil, status: String) -> SessionsReply.Session {
        SessionsReply.Session(
            executionId: id, stage: stage, role: "author", round: round, agent: PanelSnapshot.Agent(harness: "claude", model: "m", provider: nil),
            status: status, startedAt: 1000, finishedAt: nil, resume: nil
        )
    }
    let list = sessionList(
        SessionsReply(sessions: [session("c", "fix", round: 2, status: "running"), session("b", "review", status: "finished"), session("a", "ship", status: "finished")]),
        bundle: es.bundle, locale: es.locale
    )
    #expect(list.sections.map(\.role) == ["Constructor", "Revisor", "Corrector"])
    #expect(list.sections.map(\.place) == ["Ship", "Revisión", "Ronda 2"])
    #expect(list.sections[2].timeLabel?.hasPrefix("desde ") == true)
    let later = sessionList(SessionsReply(sessions: [session("x", "fix", status: "finished")]), bundle: es.bundle, locale: es.locale)
    #expect(later.sections[0].place == "Corrección")
}

@Test func theRowsWordsAndItsSummaryAreSpanishInEveryPlural() {
    let text = sessionRowText(section(profile: "acme-author", account: "pro", model: "sonnet"), bundle: es.bundle, locale: es.locale)
    #expect(text.details == ["cuenta pro", "sonnet"])
    func said(_ summary: SessionSummary) -> String { summary.text(bundle: es.bundle, locale: es.locale) }
    func summary(_ section: SessionSection, open: Bool = true) -> SessionSummary { sessionSummary(section, open: open, bundle: es.bundle, locale: es.locale) }
    #expect(said(summary(section(.running, counts: SessionCounts(calls: 62), time: "desde 16:09"))) == "Trabajando, desde 16:09, 62 llamadas")
    #expect(said(summary(section(.running, counts: SessionCounts(calls: 1), time: nil))) == "Trabajando, 1 llamada")
    #expect(said(.stopped(reason: "killed: SIGKILL")) == "detenida, killed: SIGKILL")
    #expect(said(.stopped(reason: nil)) == "detenida")
    let many = SessionCounts(calls: 229, edits: 23, added: 10, removed: 2, tests: 27, errors: 9)
    #expect(said(summary(section(counts: many))) == "229 llamadas, 23 ediciones +10 −2, 27 ejecuciones de tests, 9 errores, 31m")
    let single = SessionCounts(calls: 1, edits: 1, added: 3, removed: 1, tests: 1, errors: 1)
    #expect(said(summary(section(counts: single))) == "1 llamada, 1 edición +3 −1, 1 ejecución de tests, 1 error, 31m")
    let done = ResultCard(outcome: "Completado", tone: .good, ci: .init(verdict: "passed", evidence: "ok"), reason: nil)
    #expect(said(summary(section(result: done), open: false)) == "Completado, CI superado, 31m")
    #expect(sessionRowLabel(section(counts: SessionCounts(calls: 4)), open: true, bundle: es.bundle, locale: es.locale) == "Claude. Constructor · Ship. 4 llamadas, 31m. Abierto")
    #expect(sessionRowLabel(section(), open: false, bundle: es.bundle, locale: es.locale) == "Claude. Constructor · Ship. 31m. Plegado")
}

@Test func theEarlierSessionsRowIsSpanishInSingularAndPlural() {
    let four = EarlierSessions(sections: (0..<4).map { section(id: "s\($0)", role: "Revisor") })
    #expect(four.title(bundle: es.bundle, locale: es.locale) == "4 sesiones anteriores")
    #expect(four.label(bundle: es.bundle, locale: es.locale) == "4 sesiones anteriores, Revisor")
    #expect(EarlierSessions(sections: [section()]).title(bundle: es.bundle, locale: es.locale) == "1 sesión anterior")
}

@Test func theCountsLineIsSpanishInSingularAndPlural() {
    let many = SessionCounts(calls: 8, edits: 2, added: 42, removed: 8, tests: 2, errors: 2)
    #expect(countsLine(many, bundle: es.bundle, locale: es.locale) == "8 llamadas a herramientas · 2 ediciones +42 −8 · 2 ejecuciones de tests · 2 errores")
    let one = SessionCounts(calls: 1, edits: 1, added: 0, removed: 0, tests: 1, errors: 1)
    #expect(countsLine(one, bundle: es.bundle, locale: es.locale) == "1 llamada a herramienta · 1 edición +0 −0 · 1 ejecución de tests · 1 error")
}

// MARK: the ages

@Test func theAgesSayTheirProblemsAndTheirLineInSpanish() {
    func problems(_ archive: SessionAge, _ delete: SessionAge, unparsable: Set<SessionAgeField> = []) -> [SessionAgeField: String] {
        sessionAgeProblems(SessionAges(archive: archive, delete: delete), unparsable: unparsable, bundle: es.bundle, locale: es.locale)
    }
    #expect(problems(.days(0), .days(30))[.archive] == "Usa un número entero de días, 1 o más")
    #expect(problems(.days(30), .days(30))[.delete] == "Debe ser mayor que la edad de archivo (30 días)")
    #expect(problems(.days(1), .days(1))[.delete] == "Debe ser mayor que la edad de archivo (1 día)")
    #expect(problems(.days(15), .days(30), unparsable: [.archive])[.archive] == "Debe ser un número")
    #expect(deleteAgeOffReason(SessionAges(archive: .never, delete: .days(30)), bundle: es.bundle, locale: es.locale) == "Desactivado mientras archivar sea Nunca: el reloj no elimina nada")
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let today = utc.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 12))!
    func line(_ ages: SessionAges) -> String? { sessionAgesLine(ages, today: today, calendar: utc, bundle: es.bundle, locale: es.locale) }
    #expect(line(SessionAges(archive: .never, delete: .never)) == "Nunca se archiva ni se elimina")
    #expect(line(SessionAges(archive: .days(15), delete: .never)) == "Se archiva el 28 nov y nunca se elimina. La edad cuenta desde su última actividad")
    #expect(line(SessionAges()) == "Se archiva el 28 nov y se elimina el 13 dic. Ambas edades cuentan desde su última actividad")
    let lateInYear = utc.date(from: DateComponents(year: 2026, month: 12, day: 20, hour: 12))!
    #expect(
        sessionAgesLine(SessionAges(), today: lateInYear, calendar: utc, bundle: es.bundle, locale: es.locale)
            == "Se archiva el 4 de ene de 2027 y se elimina el 19 de ene de 2027. Ambas edades cuentan desde su última actividad")
}

// MARK: the sidebar

private func epic(_ issue: Int, _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, round: Int? = nil, slices: PanelEpic.Slices? = nil, kind: String? = nil) -> PanelEpic {
    var epic = PanelEpic(
        repo: "acme/web", issue: issue, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: nil,
        issueUrl: "https://example.test/\(issue)", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: slices, executionId: nil
    )
    epic.needsHumanKind = kind
    return epic
}

private func snapshot(_ epics: [PanelEpic] = [], queue: [PanelSnapshot.QueuedEpic] = [], done: [PanelSnapshot.DoneEpic] = [], finished: [PanelSnapshot.FinishedEpic] = []) -> PanelSnapshot {
    var snapshot = PanelSnapshot(
        now: 125_000, slots: .init(busy: 0, total: 3), queue: queue, epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: done
    )
    snapshot.finished = finished
    return snapshot
}

@Test func theSidebarsGroupsAndRowsAreSpanish() {
    let ended: (Int, PanelSnapshot.FinishedEpic.Status, Int?) -> PanelSnapshot.FinishedEpic = { issue, status, pr in
        .init(repo: "acme/web", issue: issue, title: nil, labels: [], prNumber: pr, finishedAt: 1, status: status, cancelReason: nil, executionId: nil)
    }
    let all = snapshot(
        [epic(1), epic(2, .needsHuman, kind: "timeout")], queue: [.init(repo: "acme/api", issue: 3, title: nil, queuedAt: nil)],
        done: [.init(repo: "acme/web", issue: 4, prNumber: 9, finishedAt: 5_000, executionId: nil), .init(repo: "acme/web", issue: 5, prNumber: nil, finishedAt: 5_000, executionId: nil)],
        finished: [ended(6, .merged, 12), ended(7, .merged, nil), ended(8, .cancelled, nil)]
    )
    let groups = sidebarGroups(all, by: .status, bundle: es.bundle, locale: es.locale)
    #expect(groups.map(\.title) == ["Requieren atención", "En marcha", "A continuación", "Listos para probar", "Hechos", "Cancelados"])
    #expect(groups[0].rows.map(\.detail) == ["tiempo agotado"])
    #expect(groups[1].rows.map(\.detail) == ["ship"])
    #expect(groups[2].rows.map(\.detail) == ["esperando un slot"])
    #expect(groups[3].rows.map(\.detail) == ["PR #9", "listo para probar"])
    #expect(groups[4].rows.map(\.detail) == ["PR #12 fusionado", "fusionado"])
    #expect(groups[5].rows.map(\.detail) == ["cancelado"])
}

@Test func theEnginesPillAndTheRunningLinesAreSpanish() {
    func title(_ state: ConnectionState?) -> String { carrierCardState(state).title(bundle: es.bundle, locale: es.locale) }
    #expect(title(.running(snapshot())) == "Inactivo" && title(.stopped) == "Detenido" && title(nil) == "Conectando")
    #expect(title(.incompatible(update: nil)) == "Problema")
    var paused = snapshot()
    paused.paused = true
    #expect(title(.running(paused)) == "En pausa")
    var busy = snapshot()
    busy.slots = .init(busy: 1, total: 3)
    #expect(title(.running(busy)) == "En marcha")
    func line(_ epic: PanelEpic) -> String { runningLine(epic, bundle: es.bundle, locale: es.locale) }
    #expect(line(epic(1, stage: .ship, slices: .init(done: 3, total: 5))) == "ship · 3/5 slices")
    #expect(line(epic(2, stage: .review, round: 2)) == "revisión · ronda 2/5")
    #expect(line(epic(3, stage: .fix)) == "corrección")
    #expect(line(epic(4, stage: nil)) == "iniciando")
}

@Test func everyKindOfInterventionIsSpanish() {
    let kinds = [
        "review_limit": "límite de revisiones alcanzado", "agent_needs_human": "el agente te necesita", "retries_exhausted": "reintentos agotados",
        "timeout": "tiempo agotado", "auth": "falló la autenticación", "workspace": "problema con el espacio de trabajo",
        "pr_invalid": "pull request no válido", "skill_missing": "falta un skill", "reviewers_failed": "un revisor no dio veredicto",
        "lead_limit": "límite de la revisión líder alcanzado",
    ]
    for (kind, words) in kinds { #expect(interventionLine(epic(1, .needsHuman, kind: kind), bundle: es.bundle, locale: es.locale) == words, "\(kind)") }
    #expect(interventionLine(epic(1, .needsHuman), bundle: es.bundle, locale: es.locale) == "te necesita")
}

// MARK: the words views call straight from Copy

@Test func theCountsViewsSpeakAreSpanishInSingularAndPlural() {
    func sessions(_ count: Int) -> String { Copy.sessionsCount(count: count, bundle: es.bundle, locale: es.locale) }
    #expect(sessions(1) == "1 sesión")
    #expect(sessions(2) == "2 sesiones")
    #expect(sessions(0) == "0 sesiones")
    #expect(Copy.sessionTurns(count: 1, bundle: es.bundle, locale: es.locale) == "1 turno")
    #expect(Copy.sessionTurns(count: 7, bundle: es.bundle, locale: es.locale) == "7 turnos")
    #expect(Copy.archiveCount(count: 1, bundle: es.bundle, locale: es.locale) == "1 archivada")
    #expect(Copy.archiveCount(count: 3, bundle: es.bundle, locale: es.locale) == "3 archivadas")
    #expect(Copy.sessionDiffSpoken(added: 1, removed: "2", bundle: es.bundle, locale: es.locale) == "1 línea añadida, 2 eliminadas")
    #expect(Copy.sessionDiffSpoken(added: 12, removed: "0", bundle: es.bundle, locale: es.locale) == "12 líneas añadidas, 0 eliminadas")
    #expect(Copy.sidebarSlotsBusy(busy: 1, total: 3, bundle: es.bundle, locale: es.locale) == "1 de 3 slots ocupados")
    #expect(Copy.sidebarSlotsBusy(busy: 0, total: 1, bundle: es.bundle, locale: es.locale) == "0 de 1 slots ocupados")
    #expect(Copy.sessionsRemoveFilter(name: "Trabajando", bundle: es.bundle, locale: es.locale) == "Quitar el filtro Trabajando")
}
