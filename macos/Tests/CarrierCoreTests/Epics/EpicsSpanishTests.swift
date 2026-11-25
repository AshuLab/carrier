import Foundation
import Testing

@testable import CarrierCore

// The Epics area in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish words, and every plural and select it
// uses has a Spanish case asserted. The English words are asserted in the other files of this folder, with `english`.
// Dates and times follow the person's locale in their own change (`agoText`, `formatDuration`), so a relative time here still reads in English.

private let b = spanish.bundle
private let l = spanish.locale
private let utc = TimeFormat(style: .relative, hours: .h24, timeZone: TimeZone(identifier: "UTC")!)

private func fixture(_ change: (inout PanelSnapshot) -> Void = { _ in }) throws -> PanelSnapshot {
    var snapshot = try decodeSnapshot(Data(contentsOf: testPaths().fixtures.appendingPathComponent("snapshot.json")))
    change(&snapshot)
    return snapshot
}

private func epic(
    _ issue: Int, _ status: PanelEpic.Status = .running, stage: PanelEpic.Stage? = .ship, round: Int? = nil, maxReviews: Int = 5,
    slices: PanelEpic.Slices? = nil, reason: String? = nil, kind: String? = nil, blockers: Int = 0
) -> PanelEpic {
    var made = PanelEpic(
        repo: "acme/web", issue: issue, status: status, stage: stage, round: round, maxReviews: maxReviews, blockers: blockers, stageSince: 0,
        lastActivityAt: nil, issueUrl: "https://example.test/\(issue)", prUrl: nil, lastError: nil, needsHumanReason: reason, slices: slices, executionId: nil
    )
    made.needsHumanKind = kind
    return made
}

// MARK: the lines of the Carrier home

@Test func theHeaderLinesAreSpanish() throws {
    var snapshot = try fixture()
    #expect(uptimeLine(snapshot, bundle: b, locale: l) == "en marcha desde hace 1m")
    #expect(nextCheckLine(snapshot, bundle: b, locale: l) == "próxima comprobación en 1m")
    #expect(nextCheckValue(snapshot, bundle: b, locale: l) == "en 1m")
    #expect(overviewSubtitle(snapshot, repos: 5, bundle: b, locale: l) == "5 repos · en marcha desde hace 1m · próxima comprobación en 1m")
    #expect(overviewSubtitle(snapshot, repos: 1, bundle: b, locale: l).hasPrefix("1 repo · "))
    snapshot.nextCheckAt = snapshot.now
    #expect(nextCheckLine(snapshot, bundle: b, locale: l) == "comprobando ahora" && nextCheckValue(snapshot, bundle: b, locale: l) == "comprobando ahora")
    snapshot.nextCheckAt = nil
    #expect(nextCheckLine(snapshot, bundle: b, locale: l) == "iniciando" && nextCheckValue(snapshot, bundle: b, locale: l) == "iniciando")
    #expect(agoLine(nil, now: 100_000, bundle: b, locale: l) == "hace un tiempo")
}

@Test func theSlicesAndRoundLinesAreSpanish() throws {
    let epics = try fixture().epics
    #expect(slicesLine(epics[0].slices, bundle: b, locale: l) == "3/5 slices")
    #expect(roundLine(epics[0], bundle: b, locale: l) == "ronda 2/5")
}

@Test func theRunningCardsSayTheirRolesRoundsAndTheRoomInSpanish() throws {
    let section = runningSection(try fixture(), time: utc, bundle: b, locale: l)
    #expect(section.cards[0].progressLine == "ronda 2/5" && section.cards[1].progressLine == "ship")
    let reviewers = section.cards[0].agents
    #expect(reviewers.map(\.role) == ["Revisor", "Revisor"] && reviewers.map(\.round) == ["ronda 2/5", "ronda 2/5"])
    #expect(reviewers.map(\.action) == ["Read src/auth/token.ts", "trabajando"] && reviewers[0].since == "desde 00:00")
    #expect(section.cards[1].agents.map(\.role) == ["Constructor"])
    #expect(runningSection(try fixture { $0.epics[1].stage = nil }, time: utc, bundle: b, locale: l).cards[1].progressLine == "iniciando")
    // the room: free (one and many), all in use (one slot and many) and nothing waiting
    #expect(section.room == FreeRoom(title: "1 libre", line: "web #20 empieza en la próxima comprobación"))
    #expect(runningSection(try fixture { $0.slots.busy = 0 }, time: utc, bundle: b, locale: l).room.title == "3 libres")
    let full = runningSection(try fixture { $0.slots.busy = 3 }, time: utc, bundle: b, locale: l).room
    #expect(full == FreeRoom(title: "Todos los 3 en uso", line: "web #20 empieza cuando termine uno", hasRoom: false))
    #expect(runningSection(try fixture { $0.slots = .init(busy: 1, total: 1) }, time: utc, bundle: b, locale: l).room.title == "1 en uso")
    #expect(runningSection(try fixture { $0.slots.busy = 3; $0.queue = [] }, time: utc, bundle: b, locale: l).room.line == "Nada en espera")
}

@Test func theUpNextRowsSayTheirPlaceInTheQueueInSpanish() throws {
    let rows = upNext(try fixture(), bundle: b, locale: l)
    #expect(rows.map(\.line) == ["1.ª en la cola · esperando 1m", "2.ª en la cola · esperando 1m"])
    #expect(upNext(try fixture { $0.queue[0].queuedAt = nil }, bundle: b, locale: l)[0].line == "1.ª en la cola")
}

@Test func theQueuePlaceTellsItsOrdinalKindsApartInSpanishToo() {
    // English tells 1st, 2nd, 3rd, 4th, 11th, 12th, 13th, 21st apart; the place of the other languages is the same words for all of them
    #expect([1, 2, 3, 4, 11, 12, 13, 21, 22, 23, 101, 111].map { queuePlaceLine($0, bundle: b, locale: l) }
        == ["1.ª en la cola", "2.ª en la cola", "3.ª en la cola", "4.ª en la cola", "11.ª en la cola", "12.ª en la cola", "13.ª en la cola", "21.ª en la cola", "22.ª en la cola", "23.ª en la cola", "101.ª en la cola", "111.ª en la cola"])
}

@Test func yourTurnSaysWhatNeedsThePersonInSpanish() throws {
    let stopped = try fixture {
        var limit = epic(4, .needsHuman, stage: .review, round: 5, kind: "review_limit", blockers: 1)
        limit.finishedAt = 90_000
        var two = epic(5, .needsHuman, stage: .ship, kind: "agent_needs_human", blockers: 2)
        two.finishedAt = 80_000
        $0.epics = [limit, two]
        $0.problem = "something is wrong"
    }
    let items = yourTurn(stopped, bundle: b, locale: l)
    #expect(items[0].title == "Carrier" && items[0].detail == "something is wrong")
    #expect(items[1].detail.hasPrefix("Límite de revisiones alcanzado (5/5) · 1 bloqueante abierto · "))
    #expect(items[2].detail.hasPrefix("El agente te necesita · 2 bloqueantes abiertos · "))
    #expect(items[3].detail.hasPrefix("Listo para probar · PR #77 · "))
    #expect(items[4].detail.hasPrefix("Listo para probar · "))
}

// MARK: the menu bar and the header

@Test func theEpicMenuIsSpanishForEachState() throws {
    func snapshot(_ epics: [PanelEpic] = [], queue: [PanelSnapshot.QueuedEpic] = [], done: [PanelSnapshot.DoneEpic] = []) -> PanelSnapshot {
        PanelSnapshot(now: 0, slots: .init(busy: 0, total: 2), queue: queue, epics: epics, startedAt: 0, repos: 1, nextCheckAt: nil, problem: nil, paused: false, done: done)
    }
    let all = snapshot(
        [epic(1, stage: .review, round: 2, slices: .init(done: 3, total: 5)), epic(2, .needsHuman, slices: .init(done: 1, total: 4)), epic(5, stage: nil)],
        queue: [.init(repo: "acme/api", issue: 3, title: nil, queuedAt: nil)],
        done: [.init(repo: "acme/web", issue: 4, prNumber: 9, finishedAt: nil, executionId: nil), .init(repo: "acme/web", issue: 6, prNumber: nil, finishedAt: nil, executionId: nil)]
    )
    let menu = try #require(epicMenu(all, showEpics: true, bundle: b, locale: l))
    #expect(menu.items.map(\.detail) == ["requiere atención", "revisión · ronda 2/5", "iniciando"])
    #expect(menu.more == "… y 3 más")
    let rest = try #require(epicMenu(snapshot(queue: all.queue, done: all.done), showEpics: true, bundle: b, locale: l))
    #expect(rest.items.map(\.detail) == ["en espera", "listo para probar · PR #9", "listo para probar"] && rest.more == nil)
}

@Test func theHeaderStatusIsSpanishForEachKindOfEpic() throws {
    let snapshot = try fixture()
    func status(_ subject: EpicSubject) -> String { epicHeader(subject, bundle: b, locale: l).status }
    #expect(status(.active(snapshot.epics[0])) == "En marcha · revisión · ronda 2/5")
    #expect(status(.active(snapshot.epics[2])) == "Requiere atención · límite de revisiones alcanzado")
    #expect(status(.queued(snapshot.queue[0], position: 2)) == "A continuación · 2.ª en la cola")
    #expect(status(.finished(snapshot.done[0])) == "Listo para probar")
    #expect(status(.ended(snapshot.finished[0])) == "Hecho")
    #expect(status(.ended(snapshot.finished[1])) == "Cancelado · final PR closed without merge")
    var bare = snapshot.finished[1]
    bare.cancelReason = nil
    #expect(status(.ended(bare)) == "Cancelado")
    var untitled = snapshot.queue[0]
    untitled.title = nil
    #expect(epicHeader(.queued(untitled, position: 1), bundle: b, locale: l).title == "Epic #20")
    #expect(epicHeader(.finished(snapshot.done[0]), bundle: b, locale: l).prLabel == "PR #77")
}

@Test func thePipelineAndTheStateLabelsAreSpanish() throws {
    let snapshot = try fixture()
    func names(_ subject: EpicSubject) -> [String] { pipelineSteps(subject, bundle: b, locale: l).map(\.name) }
    #expect(names(.queued(snapshot.queue[0], position: 1)) == ["En cola", "Ship", "Revisión / Corrección", "Listo"])
    let ended = pipelineSteps(.ended(snapshot.finished[1]), bundle: b, locale: l)
    #expect(ended.compactMap(\.label) == ["cancelado"])
    #expect(pipelineSteps(.active(snapshot.epics[2]), bundle: b, locale: l).compactMap(\.label) == ["límite de revisiones alcanzado"])
    let states: [EpicMenuState] = [.needsYou, .running, .waiting, .ready, .done, .cancelled]
    #expect(states.map { $0.label(bundle: b, locale: l) } == ["Requiere atención", "En marcha", "A continuación", "Listo para probar", "Hecho", "Cancelado"])
    #expect(EpicMenuState.ready.glyphLook(bundle: b, locale: l).label == "Listo para probar")
    #expect(EpicTab.allCases.map { $0.title(bundle: b, locale: l) } == ["Salida del agente", "Archivos modificados"])
    #expect(EpicTab.filesChanged.title(filesChanged: 3, bundle: b, locale: l) == "Archivos modificados · 3")
    #expect(InspectorTab.allCases.map { $0.title(bundle: b, locale: l) } == ["Slices", "Revisión", "Detalles"])
}

@Test func theEpicCardSaysItsFactsAndTimesInSpanish() throws {
    let snapshot = try fixture()
    var running = snapshot.epics[0]
    running.queuedAt = 10_000
    running.startedAt = 20_000
    running.branch = "feat/x/epic"
    running.prUrl = "https://github.com/acme/web/pull/50"
    let card = epicCard(.active(running), now: 100_000, bundle: b, locale: l)
    #expect(card.steps.map(\.name) == ["Ship", "Revisión / Corrección", "Listo"])
    #expect(card.facts.map(\.label) == ["En esta etapa", "Revisión", "Slices", "PR", "Rama"])
    #expect(card.facts.map(\.value).prefix(3) == ["1m", "ronda 2/5", "3/5 cerrados"])
    #expect(card.timeline?.hasPrefix("en cola ") == true && card.timeline?.contains(" · empezó ") == true)
    let cancelled = epicCard(.ended(snapshot.finished[1]), now: 100_000, bundle: b, locale: l)
    #expect(cancelled.facts.map(\.label) == ["Motivo"] && cancelled.timeline?.hasPrefix("terminó ") == true)
    #expect(epicCard(.finished(snapshot.done[0]), now: 100_000, bundle: b, locale: l).timeline?.hasPrefix("terminó ") == true)
    #expect(epicCard(.queued(snapshot.queue[0], position: 1), now: 100_000, bundle: b, locale: l).timeline?.hasPrefix("en cola ") == true)
}

// MARK: resume

@Test func theResumeCardSaysItsReasonAndWhatResumingDoesInSpanish() {
    func card(_ kind: String?, maxReviews: Int = 5) -> ResumeCard? {
        resumeCard(epic(12, .needsHuman, maxReviews: maxReviews, kind: kind), canResume: true, bundle: b, locale: l)
    }
    #expect(card("review_limit")?.title == "Límite de revisiones alcanzado")
    #expect(card("review_limit")?.words == "Reanudar le da al epic 5 rondas de revisión nuevas.")
    #expect(card("review_limit", maxReviews: 1)?.words == "Reanudar le da al epic 1 ronda de revisión nueva.")
    #expect(card("agent_needs_human")?.words == "Haz primero lo que pidió el agente en el pull request y luego reanuda.")
    #expect(card("timeout")?.words == "Corrige primero la causa y luego reanuda para empezar el epic de nuevo desde ship.")
    #expect(card(nil)?.words == "Ocúpate primero de la causa y luego reanuda.")
    #expect(card("review_limit")?.sheet == [
        "solve:epic:ready vuelve a ponerse en el issue.",
        "El epic empieza de nuevo desde ship, reutilizando su worktree y su pull request.",
        "Las rondas de revisión empiezan de cero.",
        "Si la causa no se corrige, se detiene aquí otra vez.",
    ])
}

@Test func whyAResumeFailedIsSaidInSpanish() {
    func words(_ code: String) -> String? { resumeFailureWords(.refused(Refusal(code: code, text: "words of Node")), bundle: b, locale: l) }
    #expect(words("epic.unknown") == "Carrier no conoce este epic.")
    #expect(words("resume.notStopped") == "Este epic no está detenido, así que no hay nada que reanudar.")
    #expect(words("github.unavailable") == "GitHub no respondió, así que no se reanudó nada. Inténtalo de nuevo.")
    #expect(words("resume.didNotRestart") == "La etiqueta volvió al issue, pero el epic no arrancó en treinta segundos. La próxima comprobación lo recogerá.")
    #expect(words("request.internal") == "Carrier no pudo reanudar este epic (error interno).")
    #expect(resumeFailureWords(.stopped, bundle: b, locale: l) == "Carrier no está en marcha.")
    #expect(resumeFailureWords(.unsupported, bundle: b, locale: l) == "Este Carrier no puede reanudar epics. Actualízalo.")
    #expect(resumeFailureWords(.resumed, bundle: b, locale: l) == nil)
}

// MARK: slices and lanes

private func lane(
    _ state: SubagentState = .finished, slice: Int? = 730, number: Int? = nil, counts: SessionCounts = SessionCounts(calls: 38, edits: 11, tests: 7, errors: 1),
    pr: Int? = nil, prState: String? = nil, range: String? = "14:02–14:07"
) -> LaneSection {
    LaneSection(
        id: "a", startId: 1, title: "Título", sliceTitle: nil, state: state, duration: nil, startedAt: nil, endedAt: nil, resumes: 0, timeLabel: range, counts: counts,
        items: [.note(id: 1, text: "x")], slice: slice, laneNumber: number, pullRequest: "", prNumber: pr, prState: prState
    )
}

@Test func aSliceCardSaysItsCountsWithTheirPluralsInSpanish() {
    let many = sliceCard(lane: lane(slice: 730, pr: 736, prState: "merged"), bundle: b, locale: l)
    #expect(many.quiet.map(\.text) == ["38 llamadas", "11 ediciones", "7 ejecuciones de pruebas", "1 error", "14:02–14:07"])
    #expect(many.spoken == "Slice 730, Título, terminado, 38 llamadas, 11 ediciones, 7 ejecuciones de pruebas, 1 error, 14:02–14:07, pull request 736 fusionado")
    let few = sliceCard(lane: lane(.failed, number: 2, counts: SessionCounts(calls: 1, edits: 1, tests: 1, errors: 2), range: nil), bundle: b, locale: l)
    #expect(few.quiet.map(\.text) == ["1 llamada", "1 edición", "1 ejecución de pruebas", "2 errores", "no se completó", "Carril 2"])
    #expect(few.spoken.hasPrefix("Slice 730, Título, falló, 1 llamada") && few.spoken.contains("2 errores") == true)
    let working = sliceCard(lane: lane(.running, number: 1, counts: SessionCounts(calls: 12), range: nil), bundle: b, locale: l)
    #expect(working.quiet.map(\.text) == ["12 llamadas hasta ahora", "Carril 1"] && working.spoken.contains(", trabajando, ") == true)
    #expect(sliceCard(lane: lane(.running, counts: SessionCounts(calls: 1), range: nil), bundle: b, locale: l).quiet.map(\.text) == ["1 llamada hasta ahora"])
    var starting = lane(.running, counts: SessionCounts(), range: nil)
    starting.items = []
    #expect(sliceCard(lane: starting, bundle: b, locale: l).quiet.map(\.text) == ["iniciando…"])
}

@Test func aSliceCardSpeaksItsPullRequestInEachStateInSpanish() {
    func spoken(_ state: String?) -> String { sliceCard(lane: lane(.finished, counts: SessionCounts(), pr: 5, prState: state, range: nil), bundle: b, locale: l).spoken }
    #expect(spoken("merged").hasSuffix("pull request 5 fusionado") && spoken("open").hasSuffix("pull request 5 abierto"))
    #expect(spoken("draft").hasSuffix("pull request 5 en borrador") && spoken("closed").hasSuffix("pull request 5 cerrado"))
    #expect(spoken(nil).hasSuffix("pull request 5"))
}

private func event(_ id: Int, _ kind: String, agent: String? = nil, text: String? = nil, arg: String? = nil, at: Int? = nil, status: String? = nil) -> ExecEvent {
    ExecEvent(id: id, at: at ?? id, kind: kind, text: text, callId: arg.map { _ in "c\(id)" }, agentId: agent, tool: arg == nil ? nil : "Bash", arg: arg, status: status)
}

private func transcript(_ events: [ExecEvent]) -> Transcript {
    var transcript = Transcript()
    transcript.apply(EventsReply(events: events, next: events.last?.id ?? 0, running: true, structured: true))
    return transcript
}

@Test func theLanesSayTheirPullRequestsAndTheirTimesInSpanish() {
    func pr(_ number: Int, _ pr: Int?, _ state: String?) -> EpicReply.Slice {
        EpicReply.Slice(number: number, title: "S\(number)", state: "open", blockedBy: [], prNumber: pr, closedAt: nil, readAt: 0, prState: state)
    }
    let slices = [pr(1, 11, "merged"), pr(2, 12, "open"), pr(3, 13, "draft"), pr(4, 14, "closed"), pr(5, nil, nil), pr(6, 16, nil)]
    let events = (1...7).map { event($0, "task", agent: "a\($0)", text: "Build slice #\($0)") } + [event(8, "say", agent: "z", text: "hi")]
    let lanes = transcript(events).laneSections(slices: slices, bundle: b, locale: l)
    #expect(lanes.map(\.pullRequest) == ["PR #11 fusionado", "PR #12 abierto", "PR #13 en borrador", "PR #14 cerrado", "aún sin PR", "PR #16", "aún sin PR", "aún sin PR"])
    #expect(lanes[7].title == "Subagente")
    let at1402 = 1_767_276_120_000
    let running = transcript([event(1, "task", agent: "a", text: "Build slice #5", at: at1402)]).laneSections(running: true, now: at1402 + 95_000, time: utc, bundle: b, locale: l)[0]
    #expect(running.timeLabel == "desde 14:02")
    let twice = transcript([
        event(1, "task", agent: "a", at: at1402), event(2, "task", agent: "a", at: at1402 + 60_000, status: "ok"), event(3, "task", agent: "a", at: at1402 + 300_000),
        event(4, "task", agent: "a", at: at1402 + 360_000, status: "ok"), event(5, "task", agent: "a", at: at1402 + 500_000), event(6, "task", agent: "a", at: at1402 + 520_000, status: "ok"),
    ]).laneSections(running: true, time: utc, bundle: b, locale: l)[0]
    #expect(twice.resumedLabel(bundle: b, locale: l) == "reanudado 2 veces")
    let once = transcript([
        event(1, "task", agent: "a", at: at1402), event(2, "task", agent: "a", at: at1402 + 60_000, status: "ok"), event(3, "task", agent: "a", at: at1402 + 300_000),
    ]).laneSections(running: true, time: utc, bundle: b, locale: l)[0]
    #expect(once.resumedLabel(bundle: b, locale: l) == "reanudado una vez")
}

@Test func theSlicesTabSaysItsTitlesAndRowsInSpanish() {
    func slice(_ number: Int, _ state: String, blockedBy: [Int] = [], lane: Int? = nil, activity: String? = nil, closedAt: Int? = nil) -> EpicReply.Slice {
        EpicReply.Slice(number: number, title: "S\(number)", state: state, blockedBy: blockedBy, prNumber: nil, closedAt: closedAt, readAt: 0, lane: lane, activity: activity)
    }
    let reply = EpicReply(
        stages: [], rounds: [], slices: [slice(1, "closed"), slice(2, "closed", closedAt: 99_000), slice(3, "in_progress", lane: 2, activity: "Edit a.ts"), slice(4, "in_progress"),
                                         slice(5, "open"), slice(6, "open", blockedBy: [3, 9])], worktrees: [], branch: nil, pr: nil
    )
    var snapshot = epic(12, stage: .ship, slices: .init(done: 2, total: 6))
    snapshot.repo = "acme/web"
    let model = slicesTabModel(.active(snapshot), reply: reply, now: 100_000, bundle: b, locale: l)
    #expect(model.rows.map(\.detail)[0] == "fusionado" && model.rows.map(\.detail)[1].isEmpty == false)
    #expect(Array(model.rows.map(\.detail)[2...]) == ["carril 2 · Edit a.ts", "trabajando", "listo para empezar", "después de #3 S3, #9"])
    #expect(model.caption(bundle: b, locale: l) == "fusionados")
    #expect(SliceGroup.allCases.map { $0.title(bundle: b, locale: l) } == ["Fusionados", "En curso", "Pendientes"])
    let done = slicesTabModel(.active(snapshot), reply: EpicReply(stages: [], rounds: [], slices: [slice(1, "closed")], worktrees: [], branch: nil, pr: nil), now: 100_000, bundle: b, locale: l)
    #expect(done.caption(bundle: b, locale: l) == "todos fusionados")
    let counts = slicesTabModel(.active(snapshot), reply: nil, now: 100_000, bundle: b, locale: l).unavailable
    #expect(counts?.title(bundle: b, locale: l) == "Lista de slices no disponible")
    #expect(counts?.line(bundle: b, locale: l) == "Este Carrier solo comparte totales. El conteo de arriba se sigue actualizando.")
    let unread = slicesTabModel(.active(snapshot), reply: EpicReply(stages: [], rounds: [], slices: [], worktrees: [], branch: nil, pr: nil), now: 100_000, bundle: b, locale: l).unavailable
    #expect(unread?.title(bundle: b, locale: l) == "Leyendo los slices")
    #expect(unread?.line(bundle: b, locale: l) == "Carrier aún no los ha leído de GitHub. Aparecen después de su próxima comprobación.")
}
