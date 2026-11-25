import Foundation
import Testing

@testable import CarrierCore

// The Projects area in Spanish (design/copy/es.json): each pure function that builds a sentence says its Spanish words, and every plural and select it uses has a
// Spanish case asserted. The English words are asserted in the other files of this folder, with `english`. A size is the system's own words and a relative time follows
// the person's locale in its own change (`timeText`), so those read as the system and the time format say them.

private let b = spanish.bundle
private let l = spanish.locale
private let utc = TimeFormat(style: .relative, hours: .h24, timeZone: TimeZone(identifier: "UTC")!)
private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func ms(daysAgo days: Double) -> Double { (now.timeIntervalSince1970 - days * 86_400) * 1000 }
private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-projects-es-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

// MARK: the list

@Test func theListGroupsAndFiltersAreSaidInSpanish() {
    #expect(ProjectGrouping.allCases.map { $0.title(bundle: b, locale: l) } == ["Ninguno", "Etiqueta", "Carrier"])
    let table = projectsWithWatched([
        ProjectRow(path: "/p/web", name: "Web", repo: "acme/web", tags: ["swift"]),
        ProjectRow(path: "/p/notes", name: "Notes", repo: nil),
    ], repos: ["acme/web"])
    #expect(projectList(table, groupBy: .carrier, bundle: b, locale: l).map(\.title) == ["Vigilando", "Sin vigilar"])
    #expect(projectList(table, groupBy: .tag, bundle: b, locale: l).map(\.title) == ["swift", "sin etiqueta"])
    #expect(table.map { $0.carrierText(bundle: b, locale: l) } == ["Vigilando", "Sin vigilar"])
    #expect(projectRemovalWords(bundle: b, locale: l) == "Su carpeta y sus worktrees se quedan donde están, y sus sesiones también. Si Carrier lo vigila, eso no cambia.")
    #expect(ProjectStatus.notFound.text(bundle: b, locale: l) == "Carpeta no encontrada" && ProjectStatus.ready.text(bundle: b, locale: l) == nil)
}

@Test func aRowSaysItsCloneInSpanish() {
    #expect(ProjectRow(clone: ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .cloning)).line(bundle: b, locale: l) == "Clonando…")
    #expect(ProjectRow(clone: ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .failed)).line(bundle: b, locale: l) == "La clonación falló")
    let coded = ProjectClone(repo: "acme/web", folder: "/p/acme/web", state: .failed, error: "words", code: "project.repoTaken", params: ["repo": "acme/web"])
    #expect(ProjectRow(clone: coded).line(bundle: b, locale: l) == "acme/web ya es un proyecto")
    #expect(ProjectRow(path: "/p/x", name: "x", repo: "acme/x").line(bundle: b, locale: l) == "acme/x")
}

@Test func aFolderThatIsNotAGitRepositorySaysWhyInSpanish() {
    let plain = ProjectPage(for: ProjectRow(path: "/p/notes", name: "Notes", repo: nil, isGit: false), bundle: b, locale: l)
    #expect(plain.notice == "No es un repositorio git, así que no tiene worktrees, rama base ni interruptor de Carrier.")
}

@Test func theProblemsOfTheFileAreSaidInSpanishWithTheFieldNamed() throws {
    func problems(_ json: String) -> [String] {
        do { _ = try readProjects(Data(json.utf8), bundle: b, locale: l); return [] } catch ProjectsFileError.invalid(let found) {
            return found.map { $0.text(bundle: b, locale: l) }
        } catch { return ["\(error)"] }
    }
    #expect(problems("{") == ["projects.json no es un JSON válido"])
    #expect(problems("[]") == ["projects.json debe ser un objeto"])
    #expect(problems(#"{"projects":{}}"#) == ["projects.json: projects debe ser una lista"])
    #expect(problems(#"{"projects":[{"origin":"added","colour":"red"}]}"#) == ["projects.json: projects.0.colour no es una clave de projects.json", "projects.json: projects.0.path es obligatorio"])
    #expect(problems(#"{"projects":[{"path":7,"origin":"added"}]}"#) == ["projects.json: projects.0.path debe ser una cadena de texto"])
    #expect(problems(#"{"projects":[{"path":"a","origin":"added"}]}"#) == ["projects.json: projects.0.path debe ser una ruta absoluta o empezar por ~/"])
    #expect(problems(#"{"projects":[{"path":"/a","name":" ","origin":"added"}]}"#) == ["projects.json: projects.0.name no debe estar en blanco"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"bought"}]}"#) == ["projects.json: projects.0.origin debe ser uno de cloned, created, added"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","pinned":"yes"}]}"#) == ["projects.json: projects.0.pinned debe ser true o false"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","tags":"x"}]}"#) == ["projects.json: projects.0.tags debe ser una lista"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","tags":[1]}]}"#) == ["projects.json: projects.0.tags.0 debe ser una cadena de texto"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","tags":[" "]}]}"#) == ["projects.json: projects.0.tags.0 no debe estar en blanco"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","tags":["Web"]}]}"#) == ["projects.json: projects.0.tags.0 debe estar sin espacios en los extremos y en minúsculas"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","tags":["web","web"]}]}"#) == ["projects.json: projects.0.tags no debe repetir una etiqueta"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","icon":{"color":""}}]}"#) == ["projects.json: projects.0.icon.color no debe estar vacío"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added","icon":"teal"}]}"#) == ["projects.json: projects.0.icon debe ser un objeto"])
    #expect(problems(#"{"projects":[{"path":"/a","origin":"added"},{"path":"/a","origin":"added"}]}"#) == ["projects.json: projects.1.path repite la ruta de un proyecto anterior"])
}

@MainActor @Test func theModelSaysItsFailuresInSpanish() async throws {
    let carrier = try temporaryFolder()
    let work = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: carrier)
        try? FileManager.default.removeItem(atPath: work)
    }
    for name in ["first", "second"] { try FileManager.default.createDirectory(atPath: work + "/" + name, withIntermediateDirectories: true) }
    let repos = [work + "/first": "acme/app", work + "/second": "acme/app"]
    let model = ProjectsModel(host: CloneHost(writing: carrier), file: ProjectsFile(folder: carrier), bundle: b, locale: l) { repos[$0] }
    model.reload()
    #expect(await model.add(folder: work + "/first") == .added(work + "/first"))
    #expect(await model.add(folder: work + "/second") == nil)
    #expect(model.failure == "Los worktrees de first ya usan la carpeta acme/app; dos proyectos no pueden compartirla")
    #expect(await model.locate(path: work + "/first", to: work + "/missing") == false)
    #expect(model.failure == "Esa carpeta no existe")
    try Data("{".utf8).write(to: ProjectsFile(folder: carrier).url)
    model.reload()
    #expect(model.problems.map { $0.text(bundle: b, locale: l) } == ["projects.json no es un JSON válido"])
    #expect(ProjectIconStoreError.unreadableImage.words(bundle: b, locale: l) == "El archivo elegido no se pudo leer como imagen.")
    #expect(ProjectIconStoreError.encodingFailed.words(bundle: b, locale: l) == "La imagen no se pudo guardar como PNG.")
}

// MARK: the project's page

@Test func theActionsOfAProjectAreSaidInSpanish() {
    #expect(ProjectActionWhen.allCases.map { $0.title(bundle: b, locale: l) } == ["Worktree nuevo", "Después de clonar"])
    #expect(ProjectActionOnFail.allCases.map { $0.title(bundle: b, locale: l) } == ["Avisar y continuar", "Detener la sesión"])
    let blank = projectActionProblems(ProjectAction(when: .newWorktree), bundle: b, locale: l)
    #expect(blank[.name] == "El nombre no debe estar en blanco" && blank[.command] == "El comando no debe estar en blanco")
    #expect(projectActionsSummary(0, bundle: b, locale: l) == "Ninguna")
    #expect(projectActionsSummary(1, bundle: b, locale: l) == "1 acción")
    #expect(projectActionsSummary(3, bundle: b, locale: l) == "3 acciones")
}

@Test func theWorktreeRowsAreSaidInSpanish() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: nil), worktrees: [
        .init(path: "/w/a", branch: "carrier/a", session: .init(id: "1", title: "Add retry"), lastActiveAt: ms(daysAgo: 3), activity: .sessionOpen, integration: .prOpen, pullRequest: .init(number: 7, url: "https://github.com/a/b/pull/7")),
        .init(path: "/w/b", branch: "carrier/b", session: .init(id: "2"), lastActiveAt: ms(daysAgo: 1), integration: .merged, pullRequest: .init(number: 6, url: "https://github.com/a/b/pull/6")),
        .init(path: "/w/c", branch: nil, session: nil, lastActiveAt: ms(daysAgo: 0), activity: .uncommitted, integration: .notPushed),
        .init(path: "/w/d", branch: "carrier/d", session: nil, lastActiveAt: ms(daysAgo: 12), integration: .inMain),
        .init(path: "/w/e", branch: "carrier/e", session: nil, lastActiveAt: ms(daysAgo: 2), integration: .prClosed),
        .init(path: "/w/f", branch: "carrier/f", session: nil, lastActiveAt: ms(daysAgo: 2), integration: .pushed),
    ])
    let rows = worktreeRows(reply, now: now, format: utc, bundle: b, locale: l)
    #expect(rows[0].branch == "HEAD desacoplado" && rows[0].detail(bundle: b, locale: l) == "Clon principal")
    #expect(rows.dropFirst().map(\.activity) == ["Sesión abierta", nil, "Cambios sin confirmar", nil, nil, nil])
    #expect(rows.dropFirst().compactMap(\.integration) == ["PR abierto", "Fusionado", "Sin subir", "En main", "PR cerrado", "Subido"])
    #expect(rows[2].session == "Sesión sin título" && rows[3].session == "Sin sesión" && rows[3].branch == "HEAD desacoplado")
    #expect(rows[1].detail(bundle: b, locale: l) == "Add retry · \(rows[1].age ?? "")")
    #expect(rows.map { $0.removeBlockedBy(bundle: b, locale: l) } == [nil, "Su sesión está abierta", nil, nil, nil, nil, nil])
    #expect(worktreeOpenWords(bundle: b, locale: l) == "Su sesión está abierta")
}

@Test func theCleanUpAndTheDiskAreSaidInSpanish() {
    let one = ProjectCleanup(removed: [.init(path: "/w/a", bytes: 1_000_000_000)], skipped: [])
    #expect(cleanUpWords(one, bundle: b, locale: l) == "1 worktree, \(size(1_000_000_000))")
    let two = ProjectCleanup(
        removed: [.init(path: "/w/a", bytes: 1_000_000_000), .init(path: "/w/b", bytes: 500_000_000)],
        skipped: [.init(path: "/h/worktrees/o/r/busy", reason: "Its session is open", code: "worktree.sessionOpen")]
    )
    #expect(cleanUpWords(two, bundle: b, locale: l) == "2 worktrees, \(size(1_500_000_000))")
    #expect(cleanUpReport(two, bundle: b, locale: l) == "Se eliminaron 2 worktrees, \(size(1_500_000_000)). Sus ramas y sus sesiones se quedan.\nSe omitió busy: Su sesión está abierta.")
    #expect(cleanUpReport(ProjectCleanup(removed: [], skipped: []), bundle: b, locale: l) == "No hay nada que limpiar.")
    #expect(diskTotalWords(nil, measuring: true, now: now, format: utc, bundle: b, locale: l) == "Midiendo ahora")
    #expect(diskTotalWords(nil, measuring: false, now: now, format: utc, bundle: b, locale: l) == "Aún sin medir")
    let fresh = ProjectDiskFigure(folder: "/p", bytes: 1, measuredAt: now.timeIntervalSince1970 * 1000)
    #expect(diskTotalWords(fresh, measuring: false, now: now, format: utc, bundle: b, locale: l) == "Medido ahora mismo")
    let old = ProjectDiskFigure(folder: "/p", bytes: 1, measuredAt: ms(daysAgo: 3))
    #expect(diskTotalWords(old, measuring: false, now: now, format: utc, bundle: b, locale: l) == "Medido hace \(timeText(Date(timeIntervalSince1970: ms(daysAgo: 3) / 1000), now: now, format: utc, bundle: b))")
}

@Test func theOfferToDeleteAndItsRefusalsAreSaidInSpanish() throws {
    #expect(deleteFromDiskWords(worktrees: 0, bytes: nil, bundle: b, locale: l) == "Mueve su carpeta a la Papelera. El espacio se libera cuando se vacía la Papelera.")
    #expect(deleteFromDiskWords(worktrees: 1, bytes: nil, bundle: b, locale: l) == "Mueve su carpeta y 1 worktree a la Papelera. El espacio se libera cuando se vacía la Papelera.")
    #expect(deleteFromDiskWords(worktrees: 3, bytes: nil, bundle: b, locale: l) == "Mueve su carpeta y 3 worktrees a la Papelera. El espacio se libera cuando se vacía la Papelera.")
    #expect(deleteFromDiskWords(worktrees: 0, bytes: 2_000_000, bundle: b, locale: l) == "Mueve su carpeta (\(size(2_000_000))) a la Papelera. El espacio se libera cuando se vacía la Papelera.")
    #expect(deleteFromDiskWords(worktrees: 1, bytes: 2_000_000, bundle: b, locale: l) == "Mueve su carpeta y 1 worktree (\(size(2_000_000))) a la Papelera. El espacio se libera cuando se vacía la Papelera.")
    #expect(deleteFromDiskWords(worktrees: 3, bytes: 2_000_000, bundle: b, locale: l) == "Mueve su carpeta y 3 worktrees (\(size(2_000_000))) a la Papelera. El espacio se libera cuando se vacía la Papelera.")

    func session(_ id: String, state: String, title: String?, live: Bool = true) throws -> ChatSession {
        let name = title.map { "\"\($0)\"" } ?? "null"
        let json = #"{"id":"\#(id)","agent":"codex","harness":"codex","folder":"/p/app","title":\#(name),"state":"\#(state)","createdAt":1,"lastActiveAt":1,"archived":false,"live":\#(live)}"#
        return try JSONDecoder().decode(ChatSession.self, from: Data(json.utf8))
    }
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: "main", state: nil), worktrees: [
        .init(path: "/w/x", branch: "carrier/x", session: .init(id: "9"), lastActiveAt: 0, activity: .sessionOpen, integration: .inMain),
        .init(path: "/w/y", branch: nil, session: .init(id: "8"), lastActiveAt: 0, activity: .sessionOpen, integration: .inMain),
    ])
    let refused = projectDeletionCheck(
        path: "/p/app", reply: reply,
        sessions: [try session("1", state: "working", title: "Add retry"), try session("2", state: "waiting_approval", title: "Spike"), try session("3", state: "idle", title: nil)],
        bundle: b, locale: l
    )
    #expect(refused.refusals == [
        "«Add retry» está trabajando", "«Spike» te está esperando", "«Sesión sin título» está abierta",
        "Hay una sesión de carrier/x abierta", "Hay una sesión de un worktree abierta",
        "El host de chat es más antiguo y no puede decir si la carpeta tiene trabajo sin guardar; reinícialo",
    ])
    let unsaved = projectDeletionCheck(
        path: "/p/app",
        reply: ProjectWorktrees(main: .init(path: "/p/app", branch: "main", state: .notPushed), worktrees: [
            .init(path: "/w/a", branch: "carrier/a", session: nil, lastActiveAt: 0, activity: .uncommitted, integration: .pushed),
            .init(path: "/w/b", branch: "carrier/b", session: nil, lastActiveAt: 0, integration: .notPushed),
        ]),
        sessions: [], bundle: b, locale: l
    )
    #expect(unsaved.unsaved == ["app tiene commits sin subir", "carrier/a tiene cambios sin confirmar", "carrier/b tiene commits sin subir"])
    #expect(projectDeletionCheck(path: "/p/app", reply: ProjectWorktrees(main: .init(path: "/p/app", branch: "main", state: .uncommitted), worktrees: []), sessions: [], bundle: b, locale: l).unsaved == ["app tiene cambios sin confirmar"])
}

@Test func whatIsRefusedBeforeTheTrashIsSaidInSpanish() throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let carrier = root + "/carrier", home = root + "/home"
    let fm = FileManager.default
    for folder in [carrier + "/chat/projects/acme/app/.git", carrier + "/chat/worktrees/acme/app/k", home + "/plain", carrier + "/engine"] {
        try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }
    let project = carrier + "/chat/projects/acme/app"
    func refusal(_ path: String, _ worktrees: [String] = []) -> String? {
        projectTrashRefusal(path: path, worktrees: worktrees, carrierFolder: carrier, home: home, bundle: b, locale: l)
    }
    #expect(refusal(home) == "Esa es la carpeta personal o una carpeta que contiene las de Carrier, así que Carrier no la elimina")
    #expect(refusal(home + "/plain") == "La carpeta del proyecto no es un repositorio git, así que Carrier no la elimina")
    #expect(refusal("/") == "Esa carpeta está demasiado cerca de la raíz del disco para que Carrier la elimine")
    try fm.createSymbolicLink(atPath: home + "/link", withDestinationPath: project)
    #expect(refusal(home + "/link") == "La carpeta del proyecto es un enlace, no una carpeta propia")
    #expect(refusal(project, [home + "/plain"]) == "plain no es un worktree que haya creado Carrier, así que no se eliminó nada")
    #expect(refusal(carrier + "/engine")?.hasPrefix("Esa carpeta está dentro de la carpeta engine del propio Carrier") == true)
    // a move that cannot finish says what was put back, and what could not be
    struct Refused: LocalizedError { var errorDescription: String? { "sin permiso" } }
    #expect(throws: ProjectTrashError(words: "No se pudo mover app a la Papelera: sin permiso. No se eliminó nada.")) {
        try moveProjectToTrash(path: project, worktrees: [], carrierFolder: carrier, home: home, trash: { _ in throw Refused() }, bundle: b, locale: l)
    }
}

// MARK: the sheet

@Test func theSheetSaysItsModesInSpanish() {
    let settings = ProjectSheetMode.settings, newSession = ProjectSheetMode.newSession
    #expect(settings.title(bundle: b, locale: l) == "Añadir proyecto" && newSession.title(bundle: b, locale: l) == "Elige dónde trabajar")
    #expect(settings.subtitle(bundle: b, locale: l) == "Pega una dirección de GitHub, busca en tus repositorios o elige una carpeta de este Mac.")
    #expect(newSession.subtitle(bundle: b, locale: l).hasPrefix("Elige un proyecto, pega una dirección de GitHub o elige una carpeta."))
    #expect(settings.fieldPlaceholder(bundle: b, locale: l) == "Pega una dirección de GitHub, busca o escribe una ruta…")
    #expect([settings, newSession].map { $0.folderActionTitle(bundle: b, locale: l) } == ["Añadir", "Usar"])
    #expect([settings, newSession].map { $0.addFolderTitle(bundle: b, locale: l) } == ["Añadir carpeta", "Usar carpeta"])
    #expect([settings, newSession].map { $0.existingActionTitle(bundle: b, locale: l) } == ["Abrir", "Usar"])
    #expect([settings, newSession].map { $0.repoActionTitle(bundle: b, locale: l) } == ["Clonar", "Usar"])
    #expect([settings, newSession].map { $0.openPanelPrompt(bundle: b, locale: l) } == ["Añadir", "Usar"])
    #expect([settings, newSession].map { $0.openPanelMessage(bundle: b, locale: l) } == ["Elige la carpeta de un proyecto", "Elige la carpeta donde trabajar"])
    #expect(settings.existingDetail(bundle: b, locale: l) == "Ya es un proyecto · Abrir")
    #expect(repoNotVisibleLine(bundle: b, locale: l) == "Tu cuenta de GitHub no ve este repositorio. Revisa el nombre o inicia sesión con otra cuenta.")
    #expect(hostNotRunningWords(bundle: b, locale: l) == "El host de chat no se está ejecutando")
}

@Test func theSheetsRowsAndSectionsAreSaidInSpanish() {
    let home = "/Users/ana"
    let recent = [RecentFolder(name: "web", path: "/Users/ana/web")]
    let suggested = projectSheetState(mode: .settings, query: "", recent: recent, projects: [], home: home, bundle: b, locale: l)
    #expect(suggested.sections.map(\.title) == ["Carpetas sugeridas"] && suggested.items.map(\.actionTitle) == ["Añadir"])
    let typed = projectSheetState(mode: .settings, query: "~/code/new", recent: [], projects: [], home: home, bundle: b, locale: l)
    #expect(typed.firstResult?.title == "Añadir carpeta" && typed.firstResult?.actionTitle == "Añadir")
    let existing = ProjectRow(path: "/Users/ana/web", name: "Web", repo: "acme/web")
    let known = projectSheetState(mode: .settings, query: "/Users/ana/web", recent: [], projects: [existing], home: home, bundle: b, locale: l)
    #expect(known.firstResult?.detail == "Ya es un proyecto · Abrir" && known.firstResult?.actionTitle == "Abrir")
    let picking = projectSheetState(mode: .newSession, query: "", recent: [], projects: [existing], home: home, bundle: b, locale: l)
    #expect(picking.sections.map(\.title) == ["Proyectos"] && picking.items.map(\.actionTitle) == ["Usar"])

    var github = ProjectSheetGithub(defaultParent: "/Users/ana/Carrier/projects")
    github.repos = [AvailableRepo(name: "acme/api", isPrivate: true, pushedAt: nil, about: "The API")]
    github.now = Date(timeIntervalSince1970: 1_800_000_000)
    let repos = projectSheetState(mode: .settings, query: "", recent: [], projects: [], github: github, home: home, bundle: b, locale: l)
    #expect(repos.sections.map(\.title) == ["Tus repositorios"] && repos.items.first?.chip == "Privado" && repos.items.first?.actionTitle == "Clonar")
    #expect(repos.items.first?.destination?.line == "Se clona en ~/Carrier/projects/acme/api")
    let pasted = projectSheetState(mode: .settings, query: "acme/new", recent: [], projects: [], github: github, home: home, bundle: b, locale: l)
    #expect(pasted.firstResult?.title == "Clonar acme/new")
    let planned = projectSheetState(mode: .newSession, query: "acme/new", recent: [], projects: [], github: github, home: home, bundle: b, locale: l)
    #expect(planned.firstResult?.destination?.line == "Se clona en ~/Carrier/projects/acme/new cuando envíes el primer mensaje")
    github.visibility["acme/new"] = .notVisible
    let hidden = projectSheetState(mode: .settings, query: "acme/new", recent: [], projects: [], github: github, home: home, bundle: b, locale: l)
    #expect(hidden.firstResult?.problem == "Tu cuenta de GitHub no ve este repositorio. Revisa el nombre o inicia sesión con otra cuenta.")
    github.canClone = false
    let older = projectSheetState(mode: .settings, query: "acme/new", recent: [], projects: [], github: github, home: home, bundle: b, locale: l)
    #expect(older.firstResult?.problem?.hasPrefix("El host de chat que se está ejecutando es más antiguo que esta app") == true)
}

@Test func whenARepositoryWasPushedIsSaidInSpanish() {
    func line(_ ago: TimeInterval) -> String {
        pushedLine(ISO8601DateFormatter().string(from: now.addingTimeInterval(-ago)), now: now, bundle: b, locale: l)
    }
    #expect(line(60) == "último push ahora mismo")
    #expect(line(3 * 3600) == "último push hace 3 h")
    #expect(line(86_400) == "último push ayer")
    #expect(line(5 * 86_400) == "último push hace 5 d")
    #expect(line(21 * 86_400) == "último push hace 3 sem")
    #expect(line(90 * 86_400) == "último push hace 3 m")
    #expect(line(365 * 86_400) == "último push hace 1 a")
    #expect(line(400 * 86_400) == "último push hace 1 a 1 m")
    #expect(pushedLine(nil, now: now, bundle: b, locale: l) == "")
}

@Test func theNewProjectFormAndTheDropAreSaidInSpanish() async throws {
    var form = NewProjectForm(defaultParent: "/Users/ana/Carrier/projects")
    #expect(form.problem(taken: { _ in false }, bundle: b, locale: l) == nil)
    #expect(form.destinationLine(home: "/Users/ana", bundle: b, locale: l) == "Crea ~/Carrier/projects/local/<name>")
    form.name = "mi-idea"
    #expect(form.destinationLine(home: "/Users/ana", bundle: b, locale: l) == "Crea ~/Carrier/projects/local/mi-idea")
    #expect(form.problem(taken: { _ in true }, bundle: b, locale: l) == "mi-idea ya es un proyecto; elige otro nombre")
    form.name = "-no"
    #expect(form.problem(taken: { _ in false }, bundle: b, locale: l) == "Un nombre empieza con una letra, un dígito o _")
    form.name = "a b"
    #expect(form.problem(taken: { _ in false }, bundle: b, locale: l) == "Usa solo letras, dígitos, _, . y -")
    #expect(await applyDroppedProjectPaths([], bundle: b, locale: l) { _ in (nil, nil) } == .refused("No se pudo leer nada de lo que soltaste"))
    #expect(await applyDroppedProjectPaths(["/a"], bundle: b, locale: l) { _ in (nil, nil) } == .refused("Esa carpeta no se puede añadir"))
    #expect(await applyDroppedProjectPaths(["/a", "/b"], bundle: b, locale: l) { _ in (nil, "no se puede") } == .refused("a: no se puede\nb: no se puede"))
}

// MARK: the Carrier switch, the repository card and the start

@Test func theCarrierSwitchIsSaidInSpanish() {
    let none = projectWatchRow(repo: nil, repos: [], state: nil, canReload: false, outcome: nil, failure: nil, bundle: b, locale: l)
    #expect(none.detail == "Sin origin de GitHub: Carrier vigila repositorios de GitHub, y esta carpeta no tiene ninguno.")
    let broken = projectWatchRow(repo: "acme/web", repos: nil, state: nil, canReload: false, outcome: nil, failure: nil, bundle: b, locale: l)
    #expect(broken.problem == "El motor no está configurado: falta engine.json en la carpeta de Carrier o no es un objeto JSON.")
    let off = projectWatchRow(repo: "acme/web", repos: [], state: nil, canReload: true, outcome: nil, failure: nil, bundle: b, locale: l)
    #expect(off.detail.isEmpty == false)
    let stopped = projectWatchRow(repo: "acme/web", repos: [], state: .stopped, canReload: false, outcome: nil, failure: nil, bundle: b, locale: l)
    #expect(stopped.detail == "Carrier no busca epics en acme/web. Carrier lee la lista cuando arranca.")
}

@Test func theStartAndTheTabsAreSaidInSpanish() {
    #expect(WorktreeStart.allCases.map { $0.title(bundle: b, locale: l) } == ["Rama remota (la más reciente)", "Rama local"])
    #expect(WorktreeStart.allCases.map { $0.tabTitle(bundle: b, locale: l) } == ["Remota", "Local"])
    #expect(worktreeStartOffReason(workIn: .baseFolder, bundle: b, locale: l) == "Solo para un worktree nuevo")
    #expect(worktreeStartOffReason(workIn: .newWorktree, bundle: b, locale: l) == nil)
}

@Test func theCountsOfARepositoryAreSaidInSpanishWithTheirPlural() {
    func status(queued: Int, running: Int, needsYou: Int) -> String? {
        let row = RepoRow(name: "a/b", health: .ok, line: "", epics: RepoEpics(running: running, queued: queued, needsYou: needsYou), isNew: false, isLoaded: true)
        return repoStatus(row, engine: "/e", cloneExists: false, notLoaded: "n", bundle: b, locale: l).epics
    }
    #expect(status(queued: 0, running: 0, needsYou: 0) == "Ninguno listo · ninguno en marcha")
    #expect(status(queued: 3, running: 1, needsYou: 0) == "3 listos · 1 en marcha")
    #expect(status(queued: 3, running: 1, needsYou: 1) == "3 listos · 1 en marcha · 1 te necesita")
    #expect(status(queued: 3, running: 1, needsYou: 2) == "3 listos · 1 en marcha · 2 te necesitan")
}

// MARK: the words the views call straight from Copy

@Test func everyKeyOfTheAreaWithNoArgumentIsInTheSpanishCatalogWithItsSpanishWords() throws {
    let file = testPaths().root.appendingPathComponent("design/copy/es.json")
    let words = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
    let plain = words.filter { key, value in ["projects", "newSession", "cleanupGroup"].contains { key.hasPrefix($0) } && value.contains("{") == false }
    #expect(plain.count > 150)
    for (key, value) in plain {
        #expect(b.localizedString(forKey: key, value: "missing", table: nil) == value, Comment(rawValue: key))
    }
}

@Test func theWordsWithArgumentsTheViewsCallAreSpanishWithTheirPluralsAndSelects() {
    #expect(Copy.projectsSortBy(title: "Disco", bundle: b, locale: l) == "Ordenar por Disco")
    #expect(Copy.projectsDismissClone(repo: "acme/web", bundle: b, locale: l) == "Descartar la clonación fallida de acme/web")
    #expect(Copy.projectsFolderGone(path: "/p/web", bundle: b, locale: l) == "/p/web ya no está ahí. Localízala para volver a abrir el proyecto.")
    #expect(Copy.projectsShowDetailHidden(name: "Web", bundle: b, locale: l).hasPrefix("Web no aparece en el selector de sesión nueva."))
    #expect(Copy.projectsShowDetailShown(name: "Web", bundle: b, locale: l) == "Web aparece cuando eliges dónde trabajar en una sesión nueva")
    #expect(Copy.projectsRemoveDetailDisk(name: "Web", bundle: b, locale: l) == "Saca Web de Carrier, y también sus archivos si lo eliges")
    #expect(Copy.projectsRemoveDetail(name: "Web", bundle: b, locale: l) == "Saca Web de Carrier; su carpeta y sus worktrees se quedan")
    #expect(Copy.projectsRemoveQuestion(name: "Web", bundle: b, locale: l) == "¿Quitar Web de Carrier?")
    #expect(Copy.projectsRemoveDialog(name: "Web", bundle: b, locale: l) == "¿Quitar Web?")
    #expect(Copy.projectsRemoveDialogMessage(words: "A", delete: "B", bundle: b, locale: l) == "A\n\nEliminar también del disco: B")
    #expect(Copy.projectsCleanUpQuestion(words: "3 worktrees, 1 GB", bundle: b, locale: l) == "¿Limpiar 3 worktrees, 1 GB?")
    #expect(Copy.projectsCleanUpTitle(bundle: b, locale: l) == "Worktrees terminados")
    #expect(Copy.projectsCleanUpDetail(words: "3 worktrees, 1 GB", bundle: b, locale: l) == "Fusionados o ya en main, nada los bloquea: 3 worktrees, 1 GB")
    #expect(Copy.projectsStopWatchingQuestion(repo: "acme/web", bundle: b, locale: l) == "¿Dejar de vigilar acme/web?")
    #expect(Copy.projectsLocateMessage(name: "Web", bundle: b, locale: l) == "Elige el nuevo lugar de Web")
    #expect(Copy.projectsIconSummary(color: "Teal", mark: "Star", bundle: b, locale: l) == "Teal, Star")
    #expect(Copy.projectsRemoveWorktreeLabel(branch: "carrier/a", bundle: b, locale: l) == "Quitar el worktree carrier/a")
    #expect(Copy.projectsCannotDeleteYet(name: "Web", bundle: b, locale: l) == "Web aún no se puede eliminar")
    #expect(Copy.projectsCannotDeleteMessage(refusals: "R", bundle: b, locale: l) == "R\n\nCierra primero las sesiones del proyecto. No se eliminó nada.")
    #expect(Copy.projectsUnsavedTitle(name: "Web", bundle: b, locale: l) == "Web tiene trabajo sin guardar")
    #expect(Copy.projectsUnsavedMessage(unsaved: "U", bundle: b, locale: l) == "U\n\nSi lo mueves a la Papelera, se queda ahí hasta que la vacíes.")
    #expect(Copy.projectsNotDeleted(name: "Web", bundle: b, locale: l) == "Web no se eliminó")
    #expect(Copy.projectsRemoveTag(tag: "swift", bundle: b, locale: l) == "Quitar swift" && Copy.projectsRemoveTagLabel(tag: "swift", bundle: b, locale: l) == "Quitar la etiqueta swift")
    #expect(Copy.projectsActionEnable(name: "Instalar", bundle: b, locale: l) == "Activar Instalar" && Copy.projectsActionDelete(name: "Instalar", bundle: b, locale: l) == "Eliminar Instalar")
    #expect(Copy.projectsCloneIntoMessage(repo: "acme/web", bundle: b, locale: l) == "Elige la carpeta en la que se clona acme/web")
    #expect(Copy.projectsCloneChooseWhere(repo: "acme/web", bundle: b, locale: l) == "Elegir dónde se clona acme/web")
    #expect(Copy.projectsProblemChoice(allowed: "a, b", bundle: b, locale: l) == "debe ser uno de a, b")
    #expect(Copy.projectsProblemUnreadable(reason: "x", bundle: b, locale: l) == "no se puede leer: x")
    #expect(Copy.projectsFolderStays(reason: "No", folder: "/p", bundle: b, locale: l) == "No. La carpeta de proyectos sigue siendo /p.")
    #expect(Copy.projectsImageNotSaved(reason: "x", bundle: b, locale: l) == "No se pudo guardar la imagen: x")
    #expect(Copy.projectsCannotChange(reason: "x", bundle: b, locale: l) == "projects.json no se puede cambiar: x")
    #expect(Copy.projectsDeleteFromDisk(worktrees: 2, bundle: b, locale: l).hasPrefix("Mueve su carpeta y 2 worktrees"))
    #expect(Copy.projectsActionsSummary(count: 0, bundle: b, locale: l) == "Ninguna")
    #expect(Copy.cleanupGroupAnnounceDone(seconds: "1.2", text: "Hola", bundle: b, locale: l) == "Limpiado en 1.2 segundos: Hola")
    #expect(Copy.cleanupGroupAnnounceFailed(reason: "x", bundle: b, locale: l) == "No se pudo limpiar: x" && Copy.cleanupGroupSeconds(seconds: "1.2", bundle: b, locale: l) == "1.2 s")
    #expect(Copy.newSessionBranchesIn(folder: "api", bundle: b, locale: l) == "Ramas en api")
    #expect(Copy.newSessionNoBranchMatches(query: "x", bundle: b, locale: l) == "Ninguna rama coincide con «x»")
    #expect(Copy.newSessionNoRemoteMatch(query: "x", bundle: b, locale: l) == "Ninguna rama remota coincide con «x»")
    #expect(Copy.newSessionNoLocalMatch(query: "x", bundle: b, locale: l) == "Ninguna rama local coincide con «x»")
    #expect(Copy.newSessionOtherTabHas(tab: "Local", bundle: b, locale: l) == "La pestaña Local tiene coincidencias.")
    #expect(Copy.newSessionBranchGenerated(prefix: "carrier/", bundle: b, locale: l) == "carrier/<se genera al enviar>")
    #expect(Copy.newSessionStepFetch(ref: "origin/main", bundle: b, locale: l) == "Traer lo último de origin/main")
    #expect(Copy.newSessionWhereFolderDetail(branch: "main", bundle: b, locale: l).hasPrefix("Trabaja en la propia carpeta, en la rama que está activa (main)."))
    #expect(Copy.newSessionWatchFailed(repo: "acme/web", reason: "x", bundle: b, locale: l) == "acme/web no se pudo añadir a la lista de Carrier: x.")
}

// MARK: the refusals the sheet builds itself

@Test func theRefusalsOfANameAFolderAndAClashAreShownInSpanish() throws {
    func shown(_ refusal: Refusal?) -> String? { refusal?.shown(bundle: b, locale: l) }
    #expect(shown(projectNameProblem("")) == "Escribe un nombre")
    #expect(shown(projectNameProblem(String(repeating: "a", count: 101))) == "Un nombre tiene como máximo 100 caracteres")
    #expect(shown(projectNameProblem("-x")) == "Un nombre empieza con una letra, un dígito o _")
    #expect(shown(projectNameProblem("a b")) == "Usa solo letras, dígitos, _, . y -")
    #expect(projectNameProblem("mi-idea") == nil)

    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(atPath: root) }
    let carrier = root + "/carrier"
    try FileManager.default.createDirectory(atPath: carrier + "/engine", withIntermediateDirectories: true)
    try Data("x".utf8).write(to: URL(fileURLWithPath: root + "/file.txt"))
    #expect(shown(projectsFolderRefusal("projects", carrierFolder: carrier)) == "La carpeta de proyectos debe ser una ruta absoluta")
    #expect(shown(projectsFolderRefusal(carrier + "/engine", carrierFolder: carrier)) == "Esa carpeta está dentro de la carpeta engine del propio Carrier; un chat nunca trabaja ahí")
    #expect(shown(projectFolderRefusal("relative", carrierFolder: carrier)) == "La carpeta debe ser una ruta absoluta")
    #expect(shown(projectFolderRefusal(root + "/nowhere", carrierFolder: carrier)) == "Esa carpeta no existe")
    #expect(shown(projectFolderRefusal(root + "/file.txt", carrierFolder: carrier)) == "Esa ruta no es una carpeta")
    #expect(shown(projectFolderRefusal(carrier + "/engine", carrierFolder: carrier)) == "Esa carpeta está dentro de la carpeta engine del propio Carrier; un proyecto no puede estar ahí")
    let first = ProjectRow(path: root + "/a", name: "first", repo: "acme/app")
    #expect(shown(worktreeClashRefusal(folder: root + "/b", repo: "acme/app", among: [first])) == "Los worktrees de first ya usan la carpeta acme/app; dos proyectos no pueden compartirla")
    #expect(worktreeClashRefusal(folder: root + "/b", repo: "other/app", among: [first]) == nil)
}
