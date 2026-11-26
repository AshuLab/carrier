import Foundation
import Testing

@testable import CarrierCore

// The Chat area in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish words, and every plural and select it uses
// has a Spanish case asserted. The English words are asserted in the other files of this folder, with `english`.

private let es = (bundle: spanish.bundle, locale: spanish.locale)
private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func row(
    _ id: String, workspace: String = "web", state: SessionState = .idle, ago: TimeInterval = 60, archived: Bool = false, kept: Bool = false,
    deleteAt: Date? = nil, branch: String? = nil, background: [BackgroundTask] = []
) -> SessionRow {
    SessionRow(
        id: id, title: "t\(id)", workspace: workspace, agent: "claude", state: state, updatedAt: now.addingTimeInterval(-ago), archived: archived, branch: branch,
        folder: "/Users/dev/web", kept: kept, deleteAt: deleteAt, background: background
    )
}

private func event(_ id: Int, _ kind: String, at: Int = 0, text: String? = nil, callId: String? = nil, tool: String? = nil, arg: String? = nil, output: [String]? = nil, status: String? = nil) -> ChatEvent {
    ChatEvent(id: id, at: at, kind: kind, text: text, callId: callId, tool: tool, arg: arg, output: output, status: status)
}

/// A call that started and ended.
private func call(_ id: Int, _ tool: String, _ arg: String = "", output: [String]? = nil, status: String = "ok") -> [ChatEvent] {
    [event(id * 2, "tool_start", callId: "c\(id)", tool: tool, arg: arg), event(id * 2 + 1, "tool_end", at: 100, callId: "c\(id)", tool: tool, output: output, status: status)]
}

private func group(_ events: [ChatEvent]) -> ToolGroup {
    chatFeed(events, bundle: es.bundle, locale: es.locale).compactMap { if case .tools(_, let group) = $0 { group } else { nil } }[0]
}

// MARK: the archive

@Test func theLineUnderAnArchivedRowIsSpanishInItsThreeCases() {
    #expect(archiveNote(row("a", kept: true), now: now, bundle: es.bundle, locale: es.locale) == "Se conserva porque su worktree tiene trabajo sin guardar")
    #expect(archiveNote(row("a", deleteAt: now.addingTimeInterval(-5)), now: now, bundle: es.bundle, locale: es.locale) == "Se elimina pronto")
    #expect(archiveNote(row("a", deleteAt: now.addingTimeInterval(86400)), now: now, bundle: es.bundle, locale: es.locale) == "Se elimina en 1 día")
    #expect(archiveNote(row("a", deleteAt: now.addingTimeInterval(86400 * 12)), now: now, bundle: es.bundle, locale: es.locale) == "Se elimina en 12 días")
    #expect(archiveNote(row("a"), now: now, bundle: es.bundle, locale: es.locale) == nil)
}

@Test func theArchivePageIsTitledAndCountedInSpanish() {
    let rows = [row("a", ago: 86400 * 3, archived: true), row("b", ago: 86400 * 60, archived: true), row("c")]
    let page = archivePage(rows, now: now, bundle: es.bundle, locale: es.locale)
    #expect(page.subtitle == "2 sesiones" && page.groups.map(\.title) == ["Últimos 30 días", "Anteriores"])
    #expect(archivePage([rows[0]], now: now, bundle: es.bundle, locale: es.locale).subtitle == "1 sesión")
    let found = archivePage(rows, query: "ta", now: now, bundle: es.bundle, locale: es.locale)
    #expect(found.subtitle == "1 resultado" && found.groups.map(\.title) == ["Resultados"])
    #expect(archivePage(rows, query: "t", now: now, bundle: es.bundle, locale: es.locale).subtitle == "2 resultados")
    #expect(archivePage([], now: now, bundle: es.bundle, locale: es.locale).subtitle == "")
}

@Test func theQuestionsBeforeDeletingAreSpanishWithAndWithoutLostWork() {
    let r = row("a")
    let plain = deleteSessionQuestion(r, bundle: es.bundle, locale: es.locale)
    #expect(plain.title == "¿Eliminar «ta»?" && plain.confirm == "Eliminar" && plain.message == "Su transcripción se elimina y no se puede recuperar.")
    let clean = deleteSessionQuestion(r, worktree: .init(path: "/w", branch: "b", dirty: 0, unpushed: 0), bundle: es.bundle, locale: es.locale)
    #expect(clean.message == "Su worktree se eliminará. Su transcripción se elimina y no se puede recuperar.")
    let files = deleteSessionQuestion(r, worktree: .init(path: "/w", branch: "b", dirty: 1, unpushed: 0), bundle: es.bundle, locale: es.locale)
    #expect(files.message == "Su worktree se eliminará y se perderá: 1 archivo sin confirmar. Su transcripción se elimina y no se puede recuperar.")
    let commits = deleteSessionQuestion(r, worktree: .init(path: "/w", branch: "b", dirty: 0, unpushed: 3), bundle: es.bundle, locale: es.locale)
    #expect(commits.message.hasPrefix("Su worktree se eliminará y se perderá: 3 commits que no existen en ningún otro lugar."))
    let one = deleteSessionQuestion(r, worktree: .init(path: "/w", branch: "b", dirty: 3, unpushed: 1), bundle: es.bundle, locale: es.locale)
    #expect(one.message.hasPrefix("Su worktree se eliminará y se perderá: 3 archivos sin confirmar y 1 commit que no existe en ningún otro lugar."))
}

@Test func theQuestionBeforeClearingTheArchiveIsSpanishInItsSingularAndPluralCases() {
    func worktree(_ dirty: Int, _ unpushed: Int) -> SessionDeletePreview { SessionDeletePreview(sessionId: "s", worktree: .init(path: "/w", branch: "b", dirty: dirty, unpushed: unpushed)) }
    let one = clearSessionsQuestion(count: 1, bundle: es.bundle, locale: es.locale)
    #expect(one.title == "¿Eliminar la sesión archivada?" && one.confirm == "Eliminar" && one.message == "Sus transcripciones se eliminan y no se pueden recuperar.")
    let many = clearSessionsQuestion(count: 4, bundle: es.bundle, locale: es.locale)
    #expect(many.title == "¿Eliminar las 4 sesiones archivadas?" && many.confirm == "Eliminar todas")
    let kept = clearSessionsQuestion(count: 2, previews: [worktree(0, 0)], bundle: es.bundle, locale: es.locale)
    #expect(kept.message.hasSuffix("1 de ellas trabaja en un worktree, que también se eliminará."))
    let keptMany = clearSessionsQuestion(count: 3, previews: [worktree(0, 0), worktree(0, 0)], bundle: es.bundle, locale: es.locale)
    #expect(keptMany.message.hasSuffix("2 de ellas trabajan en worktrees, que también se eliminarán."))
    let losing = clearSessionsQuestion(count: 2, previews: [worktree(2, 0)], bundle: es.bundle, locale: es.locale)
    #expect(losing.message.hasSuffix("1 de ellas trabaja en un worktree que perdería trabajo; al eliminarlo se perderá: 2 archivos sin confirmar."))
    let losingMany = clearSessionsQuestion(count: 3, previews: [worktree(1, 1), worktree(0, 2)], bundle: es.bundle, locale: es.locale)
    #expect(losingMany.message.hasSuffix("2 de ellas trabajan en worktrees que perderían trabajo; al eliminarlos se perderá: 1 archivo sin confirmar y 3 commits que no existen en ningún otro lugar."))
}

@Test func whyASessionCannotBeArchivedOrDeletedIsSaidInSpanish() {
    let task = BackgroundTask(id: "b", kind: "shell", description: "x")
    #expect(archiveBlock(row("a", state: .working), bundle: es.bundle, locale: es.locale) == "Detén la sesión para archivarla")
    #expect(archiveBlock(row("a", state: .waiting), bundle: es.bundle, locale: es.locale) == "Responde o detén la sesión para archivarla")
    #expect(archiveBlock(row("a", background: [task]), bundle: es.bundle, locale: es.locale) == "Detén la tarea en segundo plano para archivarla")
    #expect(archiveBlock(row("a", background: [task, task]), bundle: es.bundle, locale: es.locale) == "Detén las tareas en segundo plano para archivarla")
    #expect(deleteBlock(row("a", state: .working), bundle: es.bundle, locale: es.locale) == "Detén la sesión para eliminarla")
    #expect(deleteBlock(row("a", state: .waiting), bundle: es.bundle, locale: es.locale) == "Responde o detén la sesión para eliminarla")
    #expect(deleteBlock(row("a", background: [task]), bundle: es.bundle, locale: es.locale) == "Detén la tarea en segundo plano para eliminarla")
    #expect(deleteBlock(row("a", background: [task, task]), bundle: es.bundle, locale: es.locale) == "Detén las tareas en segundo plano para eliminarla")
    #expect(archiveBlock(row("a"), bundle: es.bundle, locale: es.locale) == nil)
}

@Test func theMenuOfASessionRowIsSpanish() {
    func titles(_ sections: [[SessionMenuItem]]) -> [[String]] { sections.map { $0.map(\.title) } }
    #expect(titles(sessionMenu(row("a"), bundle: es.bundle, locale: es.locale)) == [["Fijar"], ["Renombrar…"], ["Abrir en Terminal", "Copiar"], ["Archivar", "Eliminar…"]])
    let context = SessionMenuContext(marksUnread: true, viewing: true, startsSessions: true, projectKnown: true)
    let full = sessionMenu(row("a", state: .working, branch: "fix/x"), pinned: true, canFilter: true, canRegenerateTitle: true, context: context, bundle: es.bundle, locale: es.locale)
    #expect(titles(full) == [
        ["Detener", "Desfijar", "Marcar como no leída"], ["Renombrar…", "Regenerar título"],
        ["Nueva sesión en fix/x", "Ajustes del proyecto…", "Abrir en Terminal", "Copiar", "Filtrar por «web»"], ["Archivar", "Eliminar…"],
    ])
    #expect(full[0][2].disabledReason == "Está abierta: al abrir una sesión se marca como leída")
    #expect(full[3][0].disabledReason == "Detén la sesión para archivarla")
    #expect(full[2][3].children.map(\.title) == ["Ruta", "Nombre de la rama", "ID de la sesión"])
    var unread = row("a")
    unread.unread = true
    #expect(sessionMenu(unread, context: SessionMenuContext(marksUnread: true), bundle: es.bundle, locale: es.locale)[0].map(\.title) == ["Fijar", "Marcar como leída"])
    #expect(sessionMenu(row("a", archived: true), bundle: es.bundle, locale: es.locale).last?.first?.title == "Restaurar")
    #expect(newSessionTitle(row("a"), bundle: es.bundle, locale: es.locale) == "Nueva sesión en este proyecto")
    #expect(newSessionTitle(row("a", branch: "carrier/a-very-long-branch-name-that-has-to-be-cut-in-the-middle"), bundle: es.bundle, locale: es.locale).hasPrefix("Nueva sesión en carrier/a-very-l…"))
}

@Test func theNoticesAroundTheMessageBoxAreSpanish() {
    #expect(archivedSessionNotice(bundle: es.bundle, locale: es.locale) == ("Esta sesión está archivada", "Estás leyendo su transcripción. Reanúdala para continuar."))
    let asleep = closedSessionNotice(bundle: es.bundle, locale: es.locale)
    #expect(asleep.title == "Esta sesión está dormida" && asleep.detail.hasPrefix("Su agente está echando una siesta. Envía un mensaje") && asleep.chosen.hasSuffix("en cuanto un mensaje lo despierte."))
    #expect(folderGoneNotice(bundle: es.bundle, locale: es.locale).title == "Se eliminó la carpeta de esta sesión")
    #expect(folderGoneNotice(bundle: es.bundle, locale: es.locale).detail.hasPrefix("Su proyecto se movió a la Papelera."))
}

// MARK: the feed

@Test func theBannersOfAFailureAreSpanishWithAndWithoutAnAgentsName() {
    #expect(failedTurnBanner(agent: "claude", error: "x", bundle: es.bundle, locale: es.locale).title == "Claude no pudo continuar")
    #expect(failedTurnBanner(agent: "", error: "x", bundle: es.bundle, locale: es.locale).title == "El agente no pudo continuar")
    let signedOut = Refusal(code: "agent.notLoggedIn", params: ["agent": "Claude"], text: "words of Node")
    let banner = refusalBanner(agent: "claude", reason: signedOut, bundle: es.bundle, locale: es.locale)
    #expect(banner.title == "Claude no ha iniciado sesión" && banner.hint == "Inicia sesión desde una terminal; Carrier nunca te pide la contraseña")
    #expect(refusalBanner(agent: "", reason: signedOut, bundle: es.bundle, locale: es.locale).title == "El agente no ha iniciado sesión")
    #expect(refusalBanner(agent: "codex", reason: .words("busy"), bundle: es.bundle, locale: es.locale).title == "Codex no pudo continuar")
    #expect(signInLine(refusal: .words("x"), bundle: es.bundle, locale: es.locale) == nil)
}

@Test func theDividersOfAnAgentChangeAClearAndACompactionAreSpanish() {
    #expect(handoffDetail(to: "Codex", bundle: es.bundle, locale: es.locale).hasPrefix("Codex continúa a partir de una selección de los mensajes de arriba"))
    #expect(clearedDetail(agent: "Lu", bundle: es.bundle, locale: es.locale) == "Los mensajes de arriba se quedan aquí para leerlos, pero Lu ya no los ve: empieza de nuevo con un contexto vacío.")
    #expect(clearedFreedText(38_800, bundle: es.bundle, locale: es.locale) == "38.8k tokens liberados" && clearedFreedText(nil, bundle: es.bundle, locale: es.locale) == nil)
    #expect(Compaction(auto: true).title(bundle: es.bundle, locale: es.locale) == "Contexto compactado")
    #expect(Compaction(error: "x").title(bundle: es.bundle, locale: es.locale) == "Falló la compactación")
    #expect(Compaction(auto: true).sizes(bundle: es.bundle, locale: es.locale) == "automática")
    #expect(Compaction(after: 18_400).sizes(bundle: es.bundle, locale: es.locale) == "quedan 18.4k tokens")
    #expect(Compaction(auto: true, before: 142_300, after: 18_400).sizes(bundle: es.bundle, locale: es.locale) == "automática · 142.3k → 18.4k tokens")
    #expect(Compaction(error: "Sin espacio").detail(agent: "Lu", bundle: es.bundle, locale: es.locale) == "El contexto no cambió. Sin espacio")
    #expect(Compaction(auto: true).detail(agent: "Lu", bundle: es.bundle, locale: es.locale) == "El contexto se llenó, así que Lu resumió la conversación anterior y siguió. Los mensajes de arriba se quedan aquí para leerlos.")
    #expect(Compaction(auto: true, ms: 14_000).detail(agent: "Lu", bundle: es.bundle, locale: es.locale).hasSuffix("Tardó \(formatDuration(14_000))."))
    #expect(Compaction().detail(agent: "Lu", bundle: es.bundle, locale: es.locale).hasPrefix("Lu resumió la conversación anterior para liberar espacio."))
    #expect(Compaction(ms: 14_000).detail(agent: "Lu", bundle: es.bundle, locale: es.locale).hasSuffix("trabaja desde el resumen. Tardó \(formatDuration(14_000))."))
}

@Test func theLinesAboutAnApprovalAreSpanish() {
    let allow = ChatChoice(id: "allow", label: "Permitir una vez", allow: true)
    let deny = ChatChoice(id: "deny", label: "Rechazar", allow: false)
    func ask(_ id: Int, tool: String? = "Bash", arg: String? = "pnpm test", questions: [ChatQuestion]? = nil) -> ChatEvent {
        ChatEvent(id: id, at: 0, kind: "approval", tool: tool, arg: arg, approvalId: "p", choices: [allow, deny], questions: questions)
    }
    func answer(_ id: Int, _ choice: String, answers: [String: String]? = nil) -> ChatEvent { ChatEvent(id: id, at: 0, kind: "approval_answered", approvalId: "p", choiceId: choice, answers: answers) }
    func feed(_ events: [ChatEvent], pending: Set<String> = []) -> [FeedRow] { chatFeed(events, pending: pending, bundle: es.bundle, locale: es.locale) }
    if case .approval(_, let card) = feed([ask(1)], pending: ["p"])[0] { #expect(card.question == "¿Permitir Bash?") } else { Issue.record("no card") }
    if case .approval(_, let card) = feed([ask(1, tool: nil)], pending: ["p"])[0] { #expect(card.question == "¿Permitir la herramienta?") } else { Issue.record("no card") }
    if case .line(_, let text) = feed([ask(1)])[0] { #expect(text == "Bash pnpm test · ya no espera respuesta") } else { Issue.record("no line") }
    if case .decided(_, let text, _) = feed([ask(1), answer(2, "allow")], pending: ["p"])[0] { #expect(text == "Permitiste Bash pnpm test · Permitir una vez") } else { Issue.record("no line") }
    if case .decided(_, let text, _) = feed([ask(1), answer(2, "deny")], pending: ["p"])[0] { #expect(text == "Rechazaste Bash pnpm test · Rechazar") } else { Issue.record("no line") }
    if case .decided(_, let text, _) = feed([ask(1), answer(2, "other")], pending: ["p"])[0] { #expect(text == "Respondiste Bash pnpm test") } else { Issue.record("no line") }
    let questions = [ChatQuestion(question: "¿Cuál?", header: "Auth", options: [.init(label: "JWT", description: "")])]
    if case .decided(_, let text, _) = feed([ask(1, questions: questions), answer(2, "allow", answers: ["¿Cuál?": "JWT"])], pending: ["p"])[0] { #expect(text == "Respondiste\nAuth: JWT") } else { Issue.record("no line") }
    if case .decided(_, let text, _) = feed([ask(1, questions: questions), answer(2, "deny")], pending: ["p"])[0] { #expect(text == "Omitiste las preguntas") } else { Issue.record("no line") }
    if case .error(_, let text) = feed([event(1, "error")])[0] { #expect(text == "Algo salió mal") } else { Issue.record("no error") }
}

// MARK: the work of the agent

@Test func theTitleOfARunOfCallsIsSpanish() {
    #expect(group(call(1, "Read", "a") + call(2, "Grep", "b")).title(bundle: es.bundle, locale: es.locale) == "Exploró")
    #expect(group(call(1, "Edit", "a")).title(bundle: es.bundle, locale: es.locale) == "Cambió")
    #expect(group(call(1, "Bash", "ls")).title(bundle: es.bundle, locale: es.locale) == "Trabajó")
    #expect(group(call(1, "Bash", "ls", status: "err") + [ChatEvent(id: 9, at: 0, kind: "turn_end", outcome: "error")]).title(bundle: es.bundle, locale: es.locale) == "Falló")
    #expect(group([event(1, "tool_start", callId: "c", tool: "Bash")]).title(bundle: es.bundle, locale: es.locale) == "Trabajando")
    #expect(ToolGroup(calls: []).title(bundle: es.bundle, locale: es.locale) == "Pensó")
}

@Test func theSummaryOfARunOfCallsIsSpanishInTheSingularAndThePlural() {
    func summary(_ events: [ChatEvent]) -> String { group(events).summary(bundle: es.bundle, locale: es.locale) }
    #expect(summary(call(1, "Read", "a")) == "1 archivo leído")
    #expect(summary(call(1, "Read", "a") + call(2, "Read", "b")) == "2 archivos leídos")
    #expect(summary(call(1, "Grep", "x")) == "1 búsqueda" && summary(call(1, "Grep", "x") + call(2, "Glob", "y")) == "2 búsquedas")
    #expect(summary(call(1, "Edit", "a")) == "1 archivo cambiado" && summary(call(1, "Edit", "a") + call(2, "Edit", "b")) == "2 archivos cambiados")
    #expect(summary(call(1, "Bash", "a")) == "1 comando" && summary(call(1, "Bash", "a") + call(2, "shell", "b")) == "2 comandos")
    #expect(summary(call(1, "mcp__linear__create_issue")) == "1 llamada MCP" && summary(call(1, "mcp__linear__a") + call(2, "mcp__linear__b")) == "2 llamadas MCP")
    #expect(summary(call(1, "WebFetch", "u")) == "1 otra herramienta" && summary(call(1, "WebFetch", "u") + call(2, "Mystery")) == "2 otras herramientas")
    let thoughts = ToolGroup(calls: [], thoughts: [Thought(id: "a", text: "x", at: 0, before: 0)])
    #expect(thoughts.summary(bundle: es.bundle, locale: es.locale) == "1 pensamiento")
    #expect(ToolGroup(calls: [], thoughts: [Thought(id: "a", text: "x", at: 0, before: 0), Thought(id: "b", text: "y", at: 0, before: 0)]).summary(bundle: es.bundle, locale: es.locale) == "2 pensamientos")
    #expect(summary(call(1, "Bash", "x") + call(2, "Edit", "a") + call(3, "Read", "a")) == "1 archivo leído · 1 archivo cambiado · 1 comando")
}

@Test func whatACallIsDoingIsSpanishForEachKindWithAndWithoutItsArgument() {
    func doing(_ tool: String, _ arg: String?) -> String? { group([event(1, "tool_start", callId: "c", tool: tool, arg: arg)]).doing(bundle: es.bundle, locale: es.locale) }
    #expect(doing("Read", "src/a.ts") == "Leyendo src/a.ts" && doing("Read", nil) == "Leyendo")
    #expect(doing("Grep", "foo") == "Buscando foo" && doing("Grep", nil) == "Buscando")
    #expect(doing("Edit", "a.ts") == "Editando a.ts" && doing("Edit", nil) == "Editando")
    #expect(doing("Bash", "pnpm test") == "Ejecutando pnpm test" && doing("Bash", nil) == "Ejecutando")
    #expect(doing("WebFetch", "https://x.test") == "Usando WebFetch https://x.test" && doing("WebFetch", nil) == "Usando WebFetch")
    #expect(doing("mcp__linear__create_issue", "{}") == "create_issue")
}

@Test func theResultOfACallIsSpanishInEveryCase() {
    func result(_ events: [ChatEvent]) -> String { group(events).calls[0].result(bundle: es.bundle, locale: es.locale) }
    #expect(result(call(1, "Read", "a", output: ["x"])) == "1 línea" && result(call(1, "Read", "a", output: ["x", "y", "z"])) == "3 líneas")
    #expect(result(call(1, "Grep", "a", output: [])) == "sin coincidencias")
    #expect(result(call(1, "Grep", "a", output: ["a:1"])) == "1 coincidencia" && result(call(1, "Grep", "a", output: ["a:1", "b:2"])) == "2 coincidencias")
    #expect(result(call(1, "Bash", "a")) == "hecho" && result(call(1, "Edit", "a", output: ["not a diff"])) == "hecho")
    #expect(result(call(1, "Edit", "a", output: ["@@ -1 +1 @@", "-a", "+b"])) == "+1 −1")
    #expect(result(call(1, "Bash", "a", status: "err")) == "falló")
    #expect(result(call(1, "Bash", "a", output: ["Listo"])) == "hecho")
    #expect(result(call(1, "WebFetch", "u", output: ["Listo"])) == "Listo")
    #expect(group([event(1, "tool_start", callId: "c", tool: "Bash"), ChatEvent(id: 2, at: 0, kind: "turn_end", outcome: "interrupted")]).calls[0].result(bundle: es.bundle, locale: es.locale) == "detenida")
    #expect(group([event(1, "tool_start", callId: "c", tool: "Bash")]).calls[0].result(bundle: es.bundle, locale: es.locale) == "")
}

@Test func theChipsOfTheLiveLineAreSpanish() {
    #expect([KindChip.thinking, .read, .search, .edit, .shell].map { $0.label(bundle: es.bundle, locale: es.locale) } == ["Pensando", "Leer", "Buscar", "Editar", "Shell"])
    #expect(KindChip.mcp(server: "linear").label(bundle: es.bundle, locale: es.locale) == "linear" && KindChip.subagent(type: "Explore").label(bundle: es.bundle, locale: es.locale) == "Explore")
    #expect(KindChip.subagents(1).label(bundle: es.bundle, locale: es.locale) == "1 subagente" && KindChip.subagents(3).label(bundle: es.bundle, locale: es.locale) == "3 subagentes")
    #expect(KindChip.needsYou.label(bundle: es.bundle, locale: es.locale) == "Te necesita")
}

@Test func aSubagentsRowAndItsHeaderAreSpanish() {
    func task(_ id: Int, _ state: String, text: String? = nil, lastTool: String? = nil, ms: Int? = nil) -> ChatEvent {
        ChatEvent(id: id, at: id * 1000, kind: "task", text: text, callId: "n1", taskId: "t1", state: state, agentType: "Explore", lastTool: lastTool, ms: ms)
    }
    func subagent(_ events: [ChatEvent]) -> Subagent {
        group([task(1, "started", text: "Look inside")] + events).subagents[0]
    }
    func launched(_ rest: [ChatEvent]) -> [ChatEvent] { [event(0, "tool_start", callId: "n1", tool: "Agent")] + rest }
    #expect(group(launched([task(1, "started", text: "Look inside")])).subagents[0].words(bundle: es.bundle, locale: es.locale) == "Iniciando")
    #expect(group(launched([task(1, "started", text: "Look inside"), task(2, "progress", lastTool: "Grep")])).subagents[0].words(bundle: es.bundle, locale: es.locale) == "Usando Grep")
    func inside(_ kind: String, tool: String? = nil, arg: String? = nil) -> ChatEvent { ChatEvent(id: 5, at: 5000, kind: kind, callId: "i", tool: tool, arg: arg, parentCallId: "n1") }
    func words(_ inner: ChatEvent) -> String { group(launched([task(1, "started", text: "Look inside"), inner])).subagents[0].words(bundle: es.bundle, locale: es.locale) }
    #expect(words(inside("reasoning", arg: nil)) == "Pensando" && words(inside("assistant")) == "Respondiendo")
    #expect(words(inside("tool_start", tool: "Read", arg: "a.ts")) == "Leyendo a.ts")
    #expect(group(launched([task(1, "started", text: "Look inside"), task(2, "completed")])).subagents[0].words(bundle: es.bundle, locale: es.locale) == "Terminó")
    #expect(group(launched([task(1, "started", text: "Look inside"), task(2, "failed")])).subagents[0].words(bundle: es.bundle, locale: es.locale) == "Falló")
    #expect(group(launched([task(1, "started", text: "Look inside"), task(2, "stopped")])).subagents[0].words(bundle: es.bundle, locale: es.locale) == "Detenido")
    func header(_ state: SubagentStatus, started: Int? = 0, ms: Int? = nil, epic: String? = nil) -> SubagentHeader { SubagentHeader(title: "t", type: "Explore", state: state, startedAt: started, durationMs: ms, epic: epic) }
    #expect(header(.running).stateWords(now: 72_000, bundle: es.bundle, locale: es.locale) == "En marcha 1m 12s")
    #expect(header(.running, started: nil).stateWords(now: 0, bundle: es.bundle, locale: es.locale) == "En marcha")
    #expect(header(.completed, ms: 42_000).stateWords(now: 0, bundle: es.bundle, locale: es.locale) == "Terminó · 42 s")
    #expect(header(.failed).stateWords(now: 0, bundle: es.bundle, locale: es.locale) == "Falló" && header(.stopped).stateWords(now: 0, bundle: es.bundle, locale: es.locale) == "Detenido")
    #expect(header(.running).subtitle(of: "Arreglar el login", bundle: es.bundle, locale: es.locale) == "Explore · Subagente de Arreglar el login")
    #expect(header(.running, epic: "Mi epic").subtitle(of: "x", bundle: es.bundle, locale: es.locale) == "Explore · Mi epic")
}

// MARK: the options, the picker and the attachments

@Test func theWordsOfTheOptionsAreSpanish() {
    #expect(choiceLabel(option: "effort", value: "xhigh", label: "xhigh", bundle: es.bundle, locale: es.locale) == "Extra alto")
    let details: [(String, String, String)] = [
        ("permissionMode", "default", "Pregunta antes de editar un archivo o ejecutar un comando."), ("permissionMode", "acceptEdits", "Edita archivos sin preguntar; los comandos siguen preguntando."),
        ("permissionMode", "plan", "Lee y planifica; no cambia nada."), ("permissionMode", "auto", "Decide por sí mismo qué es seguro hacer."),
        ("permissionMode", "dontAsk", "No pregunta: lo que no se permitió de antemano se rechaza."), ("sandbox", "read-only", "Puede leer la carpeta; no cambia nada."),
        ("sandbox", "workspace-write", "Puede editar archivos de la carpeta."), ("effort", "low", "Las respuestas más rápidas, con el menor razonamiento."),
        ("effort", "medium", "Un equilibrio entre velocidad y razonamiento."), ("effort", "high", "Razona más tiempo en el trabajo difícil."),
        ("effort", "xhigh", "Razona mucho antes de responder; más lento."), ("effort", "max", "El máximo razonamiento posible."),
    ]
    for (option, value, words) in details { #expect(choiceDetail(option: option, value: value, bundle: es.bundle, locale: es.locale) == words, "\(option) \(value)") }
    #expect(choiceDetail(option: "model", value: "x", bundle: es.bundle, locale: es.locale) == nil)
    let options = [
        ChatOption(id: "model", label: "Model", values: [.init(id: "a", label: "A")], current: "a"),
        ChatOption(id: "effort", label: "Effort", values: [.init(id: "low", label: "low"), .init(id: "xhigh", label: "xhigh")], current: "low"),
        ChatOption(id: "permissionMode", label: "Permissions", values: [.init(id: "default", label: "Ask"), .init(id: "auto", label: "Auto")], current: "default"),
    ]
    let menu = composerMenu(options, bundle: es.bundle, locale: es.locale)
    #expect(menu.reasoning?.title == "Razonamiento" && menu.reasoning?.steps.map(\.label) == ["Low", "Extra alto"] && menu.access[0].title == "Acceso")
    #expect(menu.reasoning?.steps.last?.detail == "Razona mucho antes de responder; más lento.")
    #expect(optionRows(options, bundle: es.bundle, locale: es.locale)[1].choices[1].label == "Extra alto")
    let steps = effortSteps(bundle: es.bundle, locale: es.locale)
    #expect(steps.map(\.label) == ["Predeterminado", "Bajo", "Medio", "Alto", "Extra alto", "Máximo"])
    #expect(steps.map(\.detail) == [
        "El nivel propio del CLI, sea cual sea hoy.", "Las respuestas más rápidas, con el menor razonamiento.", "Equilibrado: algo de razonamiento antes de responder.",
        "Lo piensa a fondo; más lento y más cuidadoso.", "Mucho razonamiento, para problemas difíciles.", "El máximo razonamiento que puede hacer; el más lento.",
    ])
}

@Test func theAttachmentsAndThePasteReasonsAreSpanish() {
    #expect(AttachedFile(path: "/x/dir", kind: .folder, items: 1).detail(bundle: es.bundle, locale: es.locale) == "1 elemento")
    #expect(AttachedFile(path: "/x/dir", kind: .folder, items: 14).detail(bundle: es.bundle, locale: es.locale) == "14 elementos")
    #expect(AttachedFile(path: "/x/a.pdf", kind: .pdf, problem: .missing).problemText(bundle: es.bundle, locale: es.locale) == "No se encontró")
    #expect(AttachedFile(path: "/x/a.db", kind: .data, size: 640 << 20, problem: .tooBig(640 << 20)).problemText(bundle: es.bundle, locale: es.locale)?.hasPrefix("Demasiado grande · 6") == true)
    #expect(AttachedFile(path: "/x/a.db", kind: .data, problem: .carrierOwn).problemText(bundle: es.bundle, locale: es.locale) == "Archivo propio de Carrier")
    #expect(AttachedFile(path: "/x/a.db", kind: .data).problemText(bundle: es.bundle, locale: es.locale) == nil)
    #expect([PasteReason.noField, .noPermission, .secureField].map { $0.explanation(bundle: es.bundle, locale: es.locale) } == [
        "Ningún campo de texto tiene el cursor, así que el texto no se pegó.",
        "La accesibilidad está desactivada para Carrier, o macOS la quitó al actualizarse la app, así que el texto no se pegó.",
        "El campo es seguro, así que el texto no se pegó.",
    ])
    #expect(codeLanguageName(nil, resolved: nil, bundle: es.bundle, locale: es.locale) == "Código" && codeLanguageName("js", resolved: "javascript", bundle: es.bundle, locale: es.locale) == "JavaScript")
}

// MARK: the sessions of the chat host, the peek and the closing line

@Test func theSessionsOfTheHostAndTheirTitleBarAreSpanish() throws {
    func decoded(_ extra: String) throws -> ChatSession {
        try JSONDecoder().decode(
            ChatSession.self,
            from: Data(#"{"id":"x","agent":"claude","harness":"claude","folder":"/Users/dev/web","title":null,"state":"idle","createdAt":1,"lastActiveAt":2,"archived":false,"live":true\#(extra)}"#.utf8))
    }
    let untitled = sessionRows([try decoded("")], bundle: es.bundle, locale: es.locale)[0]
    #expect(untitled.title == "Sesión sin título" && conversationTitle(untitled, bundle: es.bundle, locale: es.locale) == "Nueva sesión")
    #expect(openMenuItems(untitled, bundle: es.bundle, locale: es.locale).map(\.title) == ["Mostrar en el Finder", "Copiar ruta"])
    let worktree = row("w", branch: "carrier/fix")
    #expect(openMenuItems(worktree, bundle: es.bundle, locale: es.locale).map(\.title) == ["Mostrar en el Finder", "Copiar ruta", "Copiar nombre de la rama"])
}

@Test func theSessionPeekIsSpanish() {
    var worktree = row("w", branch: "carrier/fix")
    worktree.branchFrom = "origin/main"
    worktree.turns = 3
    worktree.model = "claude-sonnet-5-5"
    let card = sessionPeek(worktree, now: now, bundle: es.bundle, locale: es.locale)
    #expect(card.facts.map(\.label) == ["Dónde", "Rama", "Carpeta", "Agente", "Modelo", "Turnos"])
    #expect(card.facts[0].value == "Worktree de web" && card.facts[1].detail == "creada desde origin/main")
    #expect(sessionPeek(row("a"), now: now, bundle: es.bundle, locale: es.locale).facts[0].value == "Carpeta base")
    #expect(card.subtitle == "Inactiva" && card.timeline.hasPrefix("actualizada "))
    #expect(sessionPeek(row("a", state: .waiting), now: now, bundle: es.bundle, locale: es.locale).subtitle == "Esperándote")
    #expect(sessionPeek(row("a", state: .working), now: now, bundle: es.bundle, locale: es.locale).subtitle == "Trabajando…")
    var unread = row("a")
    unread.unread = true
    #expect(sessionPeek(unread, now: now, bundle: es.bundle, locale: es.locale).subtitle == "Lista")
    var background = row("a", background: [BackgroundTask(id: "b", kind: "shell", description: "x")])
    background.asleep = false
    #expect(sessionPeek(background, now: now, bundle: es.bundle, locale: es.locale).subtitle == "Esperando trabajo en segundo plano…")
}

@Test func theLineThatClosesATurnAndTheContextAreSpanish() {
    let summary = TurnSummary(model: "claude-sonnet-5-5", duration: "9s", input: 1500, cacheRead: 2000, cacheWrite: 500, output: 310, contextTokens: 181_200)
    #expect(summary.text(bundle: es.bundle, locale: es.locale) == "sonnet 5.5 · 9s · 181.2k de contexto · 310 de salida")
    #expect(summary.contextText(bundle: es.bundle, locale: es.locale) == "181.2k de contexto" && summary.outText(bundle: es.bundle, locale: es.locale) == "310 de salida")
    #expect(TurnSummary(duration: "9s", input: 540_100).contextText(bundle: es.bundle, locale: es.locale) == "540.1k de entrada")
    #expect(summary.breakdown(bundle: es.bundle, locale: es.locale) == "Contexto al final: 181.200\n\nTodas las llamadas al modelo del turno:\nEntrada nueva: 1.500\nLeído de la caché: 2.000\nEscrito en la caché: 500\nSalida: 310")
    #expect(TurnSummary(output: 5).breakdown(bundle: es.bundle, locale: es.locale) == "Todas las llamadas al modelo del turno:\nSalida: 5")
    #expect(ContextUse(tokens: 45_700, window: 1_000_000).text(bundle: es.bundle, locale: es.locale) == "45.7k de 1M")
    #expect(ContextUse(tokens: 900).text(bundle: es.bundle, locale: es.locale) == "900")
}

@Test func theKeysViewsCallDirectlyAreSpanishInEveryPluralBranch() {
    #expect(Copy.chatBackgroundSpoken(count: 1, names: "npm test", bundle: es.bundle, locale: es.locale) == "Esperando una tarea en segundo plano, npm test")
    #expect(Copy.chatBackgroundSpoken(count: 3, names: "a, b, c", bundle: es.bundle, locale: es.locale) == "Esperando 3 tareas en segundo plano, a, b, c")
    #expect(Copy.chatToolFailedCount(count: 1, bundle: es.bundle, locale: es.locale) == "1 falló" && Copy.chatToolFailedCount(count: 2, bundle: es.bundle, locale: es.locale) == "2 fallaron")
    #expect(Copy.chatToolEarlierSteps(count: 1, bundle: es.bundle, locale: es.locale) == "1 paso anterior")
    #expect(Copy.chatToolEarlierSteps(count: 5, bundle: es.bundle, locale: es.locale) == "5 pasos anteriores")
    #expect(Copy.chatDiffShowMore(count: 1, bundle: es.bundle, locale: es.locale) == "Mostrar 1 línea más")
    #expect(Copy.chatDiffShowMore(count: 40, bundle: es.bundle, locale: es.locale) == "Mostrar 40 líneas más")
    #expect(Copy.chatSettingsTextSizeValue(size: 1, bundle: es.bundle, locale: es.locale) == "1 punto")
    #expect(Copy.chatSettingsTextSizeValue(size: 14, bundle: es.bundle, locale: es.locale) == "14 puntos")
    #expect(Copy.chatSubagentSteps(count: 1, bundle: es.bundle, locale: es.locale) == "1 paso" && Copy.chatSubagentSteps(count: 7, bundle: es.bundle, locale: es.locale) == "7 pasos")
    #expect(Copy.chatToolDoingLive(doing: "Leyendo a.ts", bundle: es.bundle, locale: es.locale) == "Leyendo a.ts…")
    #expect(Copy.chatContextTokens(count: "900", bundle: es.bundle, locale: es.locale) == "900 de contexto")
    #expect(Copy.chatToolUnnamed(bundle: es.bundle, locale: es.locale) == "herramienta" && Copy.chatSubagentTypeDefault(bundle: es.bundle, locale: es.locale) == "Agente")
    #expect(Copy.chatSubagentResult(bundle: es.bundle, locale: es.locale) == "Resultado")
    #expect(Copy.chatSubagentResultShowMore(bundle: es.bundle, locale: es.locale) == "Mostrar más")
    #expect(Copy.chatSubagentResultShowLess(bundle: es.bundle, locale: es.locale) == "Mostrar menos")
    #expect(Copy.chatSubagentBrief(bundle: es.bundle, locale: es.locale) == "Encargo")
    #expect(Copy.chatSubagentBriefShowMore(bundle: es.bundle, locale: es.locale) == "Mostrar más")
    #expect(Copy.chatSubagentBriefShowLess(bundle: es.bundle, locale: es.locale) == "Mostrar menos")
    #expect(Copy.chatSubagentBriefExpandSpoken(bundle: es.bundle, locale: es.locale) == "Mostrar todo el encargo")
    #expect(Copy.chatSubagentBriefCollapseSpoken(bundle: es.bundle, locale: es.locale) == "Plegar el encargo")
    #expect(Copy.chatFailed(bundle: es.bundle, locale: es.locale) == "Falló")
    #expect(Copy.chatSubagentsButtonSpoken(count: 1, bundle: es.bundle, locale: es.locale) == "1 subagente")
    #expect(Copy.chatSubagentsButtonSpoken(count: 3, bundle: es.bundle, locale: es.locale) == "3 subagentes")
    #expect(Copy.chatSubagentsButtonRunningSpoken(count: 1, running: 1, bundle: es.bundle, locale: es.locale) == "1 subagente, 1 en marcha")
    #expect(Copy.chatSubagentsButtonRunningSpoken(count: 3, running: 2, bundle: es.bundle, locale: es.locale) == "3 subagentes, 2 en marcha")
    #expect(Copy.chatSubagentsButtonFailedSpoken(count: 1, failed: 1, bundle: es.bundle, locale: es.locale) == "1 subagente, 1 falló")
    #expect(Copy.chatSubagentsButtonFailedSpoken(count: 4, failed: 2, bundle: es.bundle, locale: es.locale) == "4 subagentes, 2 fallaron")
}
