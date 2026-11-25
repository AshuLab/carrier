import Foundation
import Testing

@testable import CarrierCore

// The tabs, the preparation steps and the plan of an epic in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish
// words, and every plural and select it uses has a Spanish case asserted, as does each key a view calls by itself.

private let b = spanish.bundle
private let l = spanish.locale
private let utc = TimeFormat(style: .relative, hours: .h24, timeZone: TimeZone(identifier: "UTC")!)
/// 2025-01-10 15:00 UTC.
private let now = 1_736_521_200_000
private let hour = 3_600_000

private let claude = PanelSnapshot.Agent(harness: "claude", model: "opus", provider: nil)
private let codex = PanelSnapshot.Agent(harness: "codex", model: "gpt-5", provider: nil)

private func active(
    _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .review, round: Int? = 2, blockers: Int = 0, kind: String? = nil,
    slices: PanelEpic.Slices? = .init(done: 3, total: 3), lastActivity: Int? = now - 30_000
) -> EpicSubject {
    var epic = PanelEpic(
        repo: "acme/web", issue: 12, status: status, stage: stage, round: round, maxReviews: 5, blockers: blockers, stageSince: now - 5 * 60_000,
        lastActivityAt: lastActivity, issueUrl: "https://github.com/acme/web/issues/12", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: slices, executionId: nil
    )
    epic.needsHumanKind = kind
    epic.startedAt = now - 2 * hour - 3 * 60_000
    epic.branch = "feat/x/epic"
    epic.agents = PanelSnapshot.Agents(author: claude, reviewer: codex)
    return .active(epic)
}

private func reply(pr: EpicReply.PullRequest? = nil, rounds: [EpicReply.Round] = [], slices: [EpicReply.Slice] = []) -> EpicReply {
    EpicReply(
        stages: [.init(stage: "queued", startedAt: now - 3 * hour, endedAt: now - 2 * hour), .init(stage: "ship", startedAt: now - 2 * hour, endedAt: nil)],
        rounds: rounds, slices: slices, worktrees: [.init(kind: "lane", lane: 1, path: "/w--lane-1")], branch: "feat/x/epic", pr: pr
    )
}

private func pull(_ passing: Int, _ failing: Int, _ pending: Int) -> EpicReply.PullRequest {
    .init(number: 50, url: "https://github.com/acme/web/pull/50", draft: false, mergeState: "clean", reviewDecision: nil, checks: .init(passing: passing, failing: failing, pending: pending))
}

private func rows(_ model: DetailsTabModel) -> [String: DetailsRow] {
    Dictionary(model.groups.flatMap(\.rows).map { ($0.label, $0) }) { first, _ in first }
}

private func details(_ subject: EpicSubject?, _ reply: EpicReply? = nil, sessions: SessionsReply? = nil) -> DetailsTabModel {
    detailsTab(subject, reply: reply, sessions: sessions, now: now, time: utc, bundle: b, locale: l)
}

// MARK: details

@Test func theDetailsTabSaysItsGroupsAndLabelsInSpanish() {
    let model = details(active(), reply(pr: pull(5, 0, 0)))
    #expect(model.groups.map(\.title) == ["Tiempos", "Progreso", "Pull request", "Ejecución"])
    #expect(model.groups.map { $0.rows.map(\.label) } == [
        ["Etapa", "Última actividad", "Inicio", "Tiempo total"], ["Slices", "Ronda de revisión", "Bloqueantes"],
        ["Pull request", "Checks", "Rama"], ["Agente", "Carriles", "Repositorio"],
    ])
    let r = rows(model)
    #expect(r["Etapa"]?.note == "En revisión" && r["Última actividad"]?.note == "salida del agente")
    #expect(r["Slices"]?.note == "todos fusionados" && r["Slices"]?.value == "3 de 3")
    #expect(r["Ronda de revisión"]?.note == "en curso" && r["Ronda de revisión"]?.value == "2 de 5")
    #expect(r["Bloqueantes"]?.note == "ninguno abierto" && r["Bloqueantes"]?.value == "ninguno")
    #expect(r["Pull request"]?.note == "se abre en GitHub" && r["Checks"]?.note == "en el PR" && r["Checks"]?.value == "5 aprobados")
    #expect(r["Carriles"]?.value == "1" && details(active(), reply()).groups[3].rows[1].value == "1")
    #expect(rows(details(active(), reply(pr: pull(1, 1, 1))))["Checks"]?.value == "1 aprobado · 1 fallido · 1 pendiente")
    #expect(rows(details(active(), reply(pr: pull(5, 2, 3))))["Checks"]?.value == "5 aprobados · 2 fallidos · 3 pendientes")
    #expect(rows(details(active(), EpicReply(stages: [], rounds: [], slices: [], worktrees: [], branch: nil, pr: .init(number: 1, url: "https://x.test/pull/1", draft: false, mergeState: "clean", reviewDecision: nil, checks: nil))))["Checks"]?.value == "sin checks")
}

@Test func theDetailsTabSaysTheStageOfEachKindOfEpicInSpanish() throws {
    #expect(rows(details(active(stage: .ship, slices: nil), reply()))["Etapa"]?.note == "Entregando")
    #expect(rows(details(active(stage: .fix), reply()))["Etapa"]?.note == "Corrigiendo")
    let stuck = rows(details(active(.needsHuman, stage: .review, kind: "review_limit"), reply()))
    #expect(stuck["Etapa"]?.note == "En revisión · te necesita" && stuck["Última actividad"]?.note == "sin movimiento desde")
    #expect(stuck["Ronda de revisión"]?.note == "límite alcanzado")
    #expect(rows(details(active(lastActivity: nil), reply()))["Última actividad"]?.value == "Aún no hay actividad")
    let shipping = rows(details(active(stage: .ship, slices: .init(done: 1, total: 3)), reply()))
    #expect(shipping["Ronda de revisión"]?.note == "empieza después de ship" && shipping["Slices"]?.note == "2 restantes")
    #expect(rows(details(active(stage: .ship, slices: .init(done: 2, total: 3)), reply()))["Slices"]?.note == "1 restante")
    #expect(shipping["Pull request"]?.note == "se abre cuando todos los slices estén fusionados" && shipping["Pull request"]?.value == "todavía no")
    #expect(rows(details(active(blockers: 1), reply()))["Bloqueantes"]?.note == "abierto" && rows(details(active(blockers: 2), reply()))["Bloqueantes"]?.note == "abiertos")
    let queued = PanelSnapshot.QueuedEpic(repo: "acme/web", issue: 20, title: nil, queuedAt: now - 60_000)
    #expect(rows(details(.queued(queued, position: 2), nil))["Etapa"]?.note == "2.ª en la cola")
    let done = PanelSnapshot.DoneEpic(repo: "acme/web", issue: 30, prNumber: 77, finishedAt: now - 60_000, executionId: nil)
    let approved = EpicReply.Round(round: 2, reviewer: codex, verdict: "approved", blockers: [], reviewMs: nil, fixMs: nil, reviewedSha: nil, fixedSha: nil, commits: [])
    let finished = rows(details(.finished(done), reply(rounds: [approved])))
    #expect(finished["Etapa"]?.note == "Terminado" && finished["Ronda de revisión"]?.note == "aprobada")
    let ended = PanelSnapshot.FinishedEpic(repo: "acme/web", issue: 31, title: nil, labels: [], prNumber: nil, finishedAt: now - 60_000, status: .cancelled, cancelReason: nil, executionId: nil)
    let cancelled = rows(details(.ended(ended), reply(rounds: [approved])))
    #expect(cancelled["Etapa"]?.note == "Cancelado" && cancelled["Ronda de revisión"]?.note == "cancelada")
}

@Test func theDetailsTabNamesWhoBuiltAndWhoReviewedInSpanish() {
    let done = PanelSnapshot.DoneEpic(repo: "acme/web", issue: 30, prNumber: 77, finishedAt: now - 60_000, executionId: nil)
    let sessions = SessionsReply(sessions: [
        .init(executionId: "a", stage: "ship", role: "author", round: nil, agent: claude, status: "finished", startedAt: now, finishedAt: now, resume: nil),
        .init(executionId: "r", stage: "review", role: "reviewer", round: 1, agent: codex, status: "finished", startedAt: now, finishedAt: now, resume: nil),
    ])
    let run = details(.finished(done), reply(), sessions: sessions).groups[3].rows
    #expect(run.map(\.label) == ["Constructor", "Revisor", "Repositorio"])
}

// MARK: the review tab and the findings card

private func blocker(_ id: String?, _ title: String, _ mark: String = "new") -> EpicReply.Blocker {
    EpicReply.Blocker(id: id, title: title, url: nil, mark: mark, approximate: id == nil)
}

private func round(
    _ number: Int, _ verdict: String = "changes_requested", _ blockers: [EpicReply.Blocker] = [], fixed: Bool = false, commits: Int = 0,
    observations: [EpicReply.Observation] = []
) -> EpicReply.Round {
    EpicReply.Round(
        round: number, reviewer: codex, verdict: verdict, blockers: blockers, observations: observations, reviewMs: 20_000, fixMs: fixed ? 30_000 : nil,
        reviewedSha: "aaaaaaaaaa", fixedSha: fixed ? "bbbbbbbbbb" : nil, commits: (0..<commits).map { .init(sha: "c0ffee\($0)abcdef", subject: "fix \($0)") }
    )
}

private func review(_ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .review, round: Int? = nil) -> EpicSubject {
    var made = PanelEpic(
        repo: "acme/web", issue: 1, status: status, stage: stage, round: round, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: nil,
        issueUrl: "https://example.test/1", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: nil, executionId: nil
    )
    made.agents = PanelSnapshot.Agents(author: claude, reviewer: codex)
    return .active(made)
}

private func repliesWith(_ rounds: [EpicReply.Round], stage: String? = nil, threads: [EpicReply.ReviewThread]? = nil, truncated: Bool = false) -> EpicReply {
    var made = EpicReply(stages: stage.map { [.init(stage: $0, startedAt: 0, endedAt: nil)] } ?? [], rounds: rounds, slices: [], worktrees: [], branch: nil, pr: nil)
    made.threads = threads
    made.threadsTruncated = truncated
    return made
}

@Test func theRoundBeingReviewedIsSpanish() throws {
    let model = reviewTab(review(round: 1), reply: repliesWith([]), bundle: b, locale: l)
    let card = try #require(model.card)
    #expect(card.heading == "Ahora · Ronda 1" && model.headline == "ronda 1 de 5" && card.view.chip.text == "revisando")
    #expect(card.view.steps.map(\.title) == ["Codex está revisando", "Corrección", "Veredicto"])
    #expect(card.view.steps.map(\.subtitle) == ["ronda 1", "si encuentra bloqueantes", "después de la revisión"])
    // no agents known yet: the words stand in for them
    let bare = reviewTab(review(round: 1), reply: repliesWith([]), bundle: b, locale: l)
    #expect(bare.card?.view.steps[0].title == "Codex está revisando")
    var noAgents = PanelEpic(
        repo: "acme/web", issue: 1, status: .running, stage: .review, round: 1, maxReviews: 5, blockers: 0, stageSince: 0, lastActivityAt: nil,
        issueUrl: "https://example.test/1", prUrl: nil, lastError: nil, needsHumanReason: nil, slices: nil, executionId: nil
    )
    noAgents.agents = nil
    #expect(reviewTab(.active(noAgents), reply: repliesWith([]), bundle: b, locale: l).card?.view.steps[0].title == "El revisor está revisando")
}

@Test func aRoundWithAFixAndAVerdictIsSpanishInEachCase() throws {
    let open = [blocker("b1", "Expiry"), blocker("b2", "Refresh")]
    let first = round(1, "changes_requested", open, fixed: true, commits: 3)
    // the next round carries one over and fixes the other
    let second = round(2, "changes_requested", [blocker("b1", "Expiry", "carried"), blocker("b2", "Refresh", "fixed")])
    let model = reviewTab(review(round: 2), reply: repliesWith([first, second]), bundle: b, locale: l)
    let history = try #require(model.history.first)
    #expect(history.steps.map(\.title) == ["Codex revisó", "Claude subió 3 commits", "Revisado de nuevo"])
    #expect(history.steps.map(\.subtitle) == ["2 bloqueantes · 20s", "30s", "en la ronda 2"])
    #expect(history.chip.text == "1 arrastrado" && history.blockerCount == 1)
    #expect(history.steps[0].blockers.map { $0.mark.text(bundle: b, locale: l) } == ["arrastrado", "corregido"])
    #expect(reviewTab(review(round: 2), reply: repliesWith([round(1, "changes_requested", [blocker("b1", "Expiry"), blocker("b2", "Refresh")], fixed: true, commits: 1), round(2, "changes_requested", [blocker("b1", "Expiry", "carried"), blocker("b2", "Refresh", "carried")], fixed: true, commits: 1), round(3, "changes_requested", [blocker("b1", "Expiry", "carried")])]), bundle: b, locale: l).history.map(\.chip.text).contains("2 arrastrados"))
    // a fix with no commits, a fix being made, a fix not made yet
    let noCommits = reviewTab(review(round: 1), reply: repliesWith([round(1, "changes_requested", open, fixed: true)]), bundle: b, locale: l)
    #expect(noCommits.history.first?.steps[1].title == "Claude subió una corrección" && noCommits.history.first?.chip.text == "cambios solicitados")
    let waiting = reviewTab(review(stage: .ship, round: 1), reply: repliesWith([round(1, "changes_requested", open)]), bundle: b, locale: l)
    #expect(waiting.history.first?.steps.map(\.subtitle).suffix(2) == ["esperando al autor", "Codex vuelve a comprobar cuando estén las correcciones"])
    #expect(waiting.history.first?.steps.map(\.title).suffix(2) == ["Corrección", "Nueva revisión"])
    let fixing = reviewTab(review(stage: .fix, round: 1), reply: repliesWith([round(1, "changes_requested", open)]), bundle: b, locale: l)
    #expect(fixing.card?.view.steps[1].title == "Claude está corrigiendo" && fixing.card?.view.chip.text == "corrigiendo ahora")
    let allFixed = reviewTab(review(round: 2), reply: repliesWith([round(1, "changes_requested", [blocker("b1", "Expiry")], fixed: true, commits: 1), round(2, "approved", [blocker("b1", "Expiry", "fixed")])]), bundle: b, locale: l)
    #expect(allFixed.card?.heading == "Resultado · Ronda 2" && allFixed.card?.view.chip.text == "aprobado")
    #expect(allFixed.card?.view.steps.last.map { [$0.title, $0.subtitle] } == ["Aprobado", "Listo para probar"])
    #expect(allFixed.card?.view.steps[0].subtitle == "sin bloqueantes · 20s")
    #expect(allFixed.history.first?.chip.text == "todo corregido")
    let limit = reviewTab(review(.needsHuman, round: 5), reply: repliesWith([round(5, "limit_reached", [blocker("b1", "Expiry")])]), bundle: b, locale: l)
    #expect(limit.card?.view.chip.text == "sigue abierto")
    #expect(limit.card?.view.steps.last.map { [$0.title, $0.subtitle] } == ["Límite alcanzado", "Carrier se detuvo y te espera"])
    #expect(ReviewMark.since(2).text(bundle: b, locale: l) == "desde R2" && ReviewMark.new.text(bundle: b, locale: l) == "nuevo")
}

@Test func theReviewThreadsNameTheirAuthorsInSpanish() throws {
    func thread(_ id: String, author: String?, bot: Bool = false) -> EpicReply.ReviewThread {
        .init(id: id, path: "a.ts", line: 3, resolved: false, outdated: false, author: author, bot: bot, firstLine: "x", commentCount: 1, url: "https://x.test/\(id)")
    }
    var reply = repliesWith([round(1)], threads: [thread("1", author: nil), thread("2", author: "ci", bot: true), thread("3", author: "ana")])
    reply.pr = .init(number: 5, url: "https://x.test/pull/5", draft: false, mergeState: "clean", reviewDecision: nil, checks: nil)
    let threads = try #require(reviewTab(review(round: 1), reply: reply, bundle: b, locale: l).threads)
    #expect(threads.rows.map(\.author) == ["desconocido", "ci (bot)", "ana"])
}

@Test func theFindingsCardIsSpanishWithItsSummariesAndMarks() throws {
    let suggestion = EpicReply.Observation(id: "s1", title: "Rename it", url: nil)
    func card(_ rounds: [EpicReply.Round], stage: String = "review", round: Int) -> FindingsCard? {
        findingsCard(repliesWith(rounds), stage: stage, round: round, bundle: b, locale: l)
    }
    let mixed = try #require(card([round(1, "changes_requested", [blocker("b1", "Expiry"), blocker("b2", "Refresh")], observations: [suggestion])], round: 1))
    #expect(mixed.title == "Cambios solicitados" && mixed.summary == "2 bloqueantes · 1 sugerencia")
    let one = try #require(card([round(1, "changes_requested", [blocker("b1", "Expiry")], observations: [suggestion, suggestion])], round: 1))
    #expect(one.summary == "1 bloqueante · 2 sugerencias")
    let partly = try #require(card([round(1, "changes_requested", [blocker("b1", "Expiry"), blocker("b2", "Refresh", "fixed"), blocker("b3", "Retry"), blocker("b4", "Log", "fixed")])], round: 1))
    #expect(partly.summary == "2 bloqueantes abiertos · 2 corregidos")
    let single = try #require(card([round(1, "changes_requested", [blocker("b1", "Expiry"), blocker("b2", "Refresh", "fixed")])], round: 1))
    #expect(single.summary == "1 bloqueante abierto · 1 corregido")
    let ready = try #require(card([round(1, "approved", [], observations: [suggestion])], round: 1))
    #expect(ready.title == "Listo" && ready.summary == "0 bloqueantes · 1 sugerencia")
    #expect(try #require(card([round(1, "approved")], round: 1)).summary == "sin hallazgos")
    #expect([FindingMark.new, .carried, .fixed].map { $0.text(bundle: b, locale: l) } == ["nuevo", "arrastrado", "corregido"])
}

// MARK: preparation, files and plan

private func step(_ id: Int, _ step: String, _ status: String, action: String? = nil) -> ChatEvent {
    ChatEvent(id: id, at: id, kind: "step", status: status, step: step, action: action, when: action == nil ? nil : "afterClone")
}

@Test func eachPreparationStepSaysWhereItStandsInSpanish() {
    let names = ["clone", "fetch", "project", "worktree", "checkout", "agent", "message", "deploy"]
    func lines(_ status: String) -> [String] {
        preparationSteps(names.enumerated().map { step($0.offset + 1, $0.element, status) }, preparation: .running, bundle: b, locale: l).map(\.line)
    }
    #expect(lines("running") == [
        "Clonando el repositorio…", "Actualizando el repositorio…", "Creando el proyecto…", "Creando el worktree…", "Cambiando a la rama…", "Iniciando el agente…",
        "Esperando la respuesta del agente…", "Trabajando en deploy…",
    ])
    #expect(lines("done") == [
        "Repositorio clonado", "Repositorio actualizado", "Proyecto creado", "Worktree creado", "Cambiado a la rama", "Agente iniciado", "El agente respondió", "Terminó deploy",
    ])
    #expect(lines("failed") == [
        "No se pudo clonar el repositorio", "No se pudo actualizar el repositorio", "No se pudo crear el proyecto", "No se pudo crear el worktree", "No se pudo cambiar a la rama",
        "No se pudo iniciar el agente", "El agente no respondió", "No se pudo terminar deploy",
    ])
    func action(_ status: String, _ name: String?) -> String? {
        preparationSteps([step(1, "action", status, action: name)], preparation: .running, bundle: b, locale: l).first?.line
    }
    #expect(["running", "done", "failed"].map { action($0, "Install") } == ["Ejecutando Install…", "Se ejecutó Install", "Install falló"])
    #expect(["running", "done", "failed"].map { action($0, nil) } == ["Ejecutando una acción…", "Se ejecutó una acción", "Una acción falló"])
}

@Test func theOutlineAddsTheStepsToComeInSpanish() {
    let rows = preparationSteps([step(1, "clone", "running")], preparation: .running, bundle: b, locale: l)
    #expect(preparationOutline(rows, bundle: b, locale: l).map(\.line) == ["Clonando el repositorio…", "Iniciar el agente", "Enviar tu mensaje"])
}

@Test func aFileThatCannotBeShownSaysWhySpanish() {
    func note(_ value: String?) -> FileFragment { fileFragment(FileDiffReply(rows: [], truncated: false, note: value), bundle: b, locale: l) }
    #expect(note("binary") == .note("Archivo binario: sin vista previa") && note("too-big") == .note("Demasiado grande: sin vista previa"))
    #expect(note(nil) == .note("Sin cambios: el archivo está como estaba") && note("other") == .note("Sin vista previa"))
}

@Test func theQueuedPlanSaysWhatWillHappenInSpanish() {
    let agents = PanelSnapshot.Agents(author: claude, reviewer: codex)
    func plan(position: Int, busy: Int, total: Int) -> QueuedPlan { queuedPlan(position: position, agents: agents, slots: .init(busy: busy, total: total), bundle: b, locale: l) }
    let rows = plan(position: 1, busy: 0, total: 2).rows
    #expect(rows.map(\.name) == ["Ship", "Revisión", "Corrección", "Listo"])
    #expect(rows.map(\.line) == [
        "Construye cada slice en su propio carril y lo fusiona en la rama del epic.", "Lee el PR y lista los bloqueantes con los que no aprobará.",
        "Corrige los bloqueantes; la revisión y la corrección se repiten hasta que el revisor apruebe.", "Tú lo pruebas y lo fusionas. Carrier nunca fusiona en main.",
    ])
    // a free slot: nobody ahead, one epic ahead, several ahead
    #expect(plan(position: 1, busy: 1, total: 3).footer == "Hay un slot libre (1 de 3 ocupados). Empieza solo en la próxima comprobación.")
    #expect(plan(position: 2, busy: 1, total: 3).footer == "Hay un slot libre (1 de 3 ocupados). Empieza solo después del 1 epic que tiene por delante.")
    #expect(plan(position: 4, busy: 1, total: 3).footer == "Hay un slot libre (1 de 3 ocupados). Empieza solo después de los 3 epics que tiene por delante.")
    // no slot free: one slot or many, one busy or many, nobody ahead, one ahead, several ahead
    #expect(plan(position: 1, busy: 3, total: 3).footer == "Empieza solo cuando se libere uno de los 3 slots. Ahora hay 3 ocupados.")
    #expect(plan(position: 2, busy: 1, total: 1).footer == "Empieza solo cuando se libere su slot. Ahora hay 1 ocupado. 1 epic va primero.")
    #expect(plan(position: 3, busy: 2, total: 2).footer == "Empieza solo cuando se libere uno de los 2 slots. Ahora hay 2 ocupados. 2 epics van primero.")
    #expect(queuedPlan(position: 1, agents: nil, slots: nil, bundle: b, locale: l).footer == "Empieza solo cuando haya un slot libre.")
}

@Test func theLeadReviewerSwitchSaysWhatIsMissingInSpanish() {
    var draft = LeadReviewerDraft()
    #expect(draft.hint(bundle: b, locale: l) == "Elige una identidad, un proveedor y un modelo para activarlo. No se escribe nada hasta entonces.")
    draft.apply(.bot("acme-lead"))
    #expect(draft.hint(bundle: b, locale: l) == "Elige un proveedor y un modelo para activarlo. No se escribe nada hasta entonces.")
    draft.apply(.provider("codex"))
    #expect(draft.hint(bundle: b, locale: l) == "Elige un modelo para activarlo. No se escribe nada hasta entonces.")
}

// MARK: the keys a view calls by itself

@Test func theCountsAViewWritesAreSpanishInTheirSingularAndPluralCases() {
    #expect(Copy.epicsItems(count: 1, bundle: b, locale: l) == "1 elemento" && Copy.epicsItems(count: 3, bundle: b, locale: l) == "3 elementos")
    #expect(Copy.epicsBlockers(count: 1, bundle: b, locale: l) == "1 bloqueante" && Copy.epicsBlockers(count: 0, bundle: b, locale: l) == "0 bloqueantes")
    #expect(Copy.epicsSuggestions(count: 1, bundle: b, locale: l) == "1 sugerencia" && Copy.epicsSuggestions(count: 4, bundle: b, locale: l) == "4 sugerencias")
    #expect(Copy.epicsFileWord(count: 1, bundle: b, locale: l) == "archivo" && Copy.epicsFileWord(count: 7, bundle: b, locale: l) == "archivos")
    #expect(Copy.epicsMoreCommits(count: 2, bundle: b, locale: l) == "+ 2 más")
    #expect(Copy.epicsRepos(count: 1, bundle: b, locale: l) == "1 repo" && Copy.epicsRepos(count: 2, bundle: b, locale: l) == "2 repos")
}

@Test func theSpokenFilesAreSpanishInTheirSingularAndPluralCases() {
    #expect(Copy.epicsFilesSpoken(files: 1, added: 1, removed: 1, bundle: b, locale: l) == "Total del epic: 1 archivo, 1 línea añadida, 1 eliminada")
    #expect(Copy.epicsFilesSpoken(files: 7, added: 166, removed: 12, bundle: b, locale: l) == "Total del epic: 7 archivos, 166 líneas añadidas, 12 eliminadas")
    #expect(Copy.epicsFileSpoken(path: "src/a.ts", added: 1, removed: 3, bundle: b, locale: l) == "src/a.ts, 1 línea añadida, 3 eliminadas")
    #expect(Copy.epicsFileSpoken(path: "src/a.ts", added: 2, removed: 1, bundle: b, locale: l) == "src/a.ts, 2 líneas añadidas, 1 eliminada")
    #expect(Copy.epicsFindingApproximately(mark: "nuevo", bundle: b, locale: l) == "nuevo aproximadamente")
}
