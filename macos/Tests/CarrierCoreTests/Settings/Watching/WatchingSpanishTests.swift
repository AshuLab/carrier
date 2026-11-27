import Foundation
import Testing

@testable import CarrierCore

// The Watching page in Spanish (design/copy/es.json): the problems a repo name can have, the epics' counts and the confirmation to stop watching, the rows' lines,
// the four checks of "Listo para Carrier", the choices of projects and the banner of a refused config. Every plural and select has a Spanish case asserted, `one`
// included. The English words are asserted in the other files of this folder, with `english`.

private let b = spanish.bundle
private let l = spanish.locale

private let fixtures = testPaths().fixtures

private func running() throws -> PanelSnapshot { try decodeSnapshot(Data(contentsOf: fixtures.appendingPathComponent("snapshot.json"))) }

// MARK: the list

@Test func aRepoIsRefusedForItsFormatItsNameOrItsFolderInSpanish() {
    #expect(repoProblem("acme/api", joining: ["acme/web"], bundle: b, locale: l) == nil)
    #expect(repoProblem("bad name", joining: [], bundle: b, locale: l) == "bad name debe ser propietario/nombre")
    #expect(repoProblem("ACME/Web", joining: ["acme/web"], bundle: b, locale: l) == "ACME/Web ya se vigila")
    #expect(repoProblem("other/web", joining: ["acme/web"], bundle: b, locale: l)
        == "other/web tiene el mismo nombre de carpeta que acme/web; las rutas de worktree de Solve no llevan propietario")
    #expect(reposProblem(["acme/web", "ok/ok", "acme/web"], bundle: b, locale: l) == "acme/web ya se vigila")
}

@Test func theEpicsOfARepoAreCountedWithTheOneOfEachPluralInSpanish() {
    #expect(RepoEpics(running: 1, queued: 1, needsYou: 1).line(bundle: b, locale: l) == "1 en marcha · 1 en cola · 1 te necesita")
    #expect(RepoEpics(running: 2, queued: 3, needsYou: 4).line(bundle: b, locale: l) == "2 en marcha · 3 en cola · 4 te necesitan")
    #expect(RepoEpics(running: 0, queued: 2, needsYou: 1).line(separator: ", ", bundle: b, locale: l) == "2 en cola, 1 te necesita")
    #expect(RepoEpics().line(bundle: b, locale: l) == "")
}

@Test func theConfirmationToStopWatchingSaysWhatHappensToTheEpicsInSpanish() {
    let some = RepoEpics(running: 0, queued: 2, needsYou: 1)
    #expect(removalText(some, appliesNow: true, bundle: b, locale: l)
        == "Tiene epics (2 en cola, 1 te necesita). Se detienen donde están, intactos, y continúan si vuelves a añadir el repositorio. No se borra nada. Surte efecto de inmediato.")
    #expect(removalText(RepoEpics(), appliesNow: true, bundle: b, locale: l) == "No tiene epics. Puedes volver a añadirlo cuando quieras. Surte efecto de inmediato.")
    #expect(removalText(nil, appliesNow: true, bundle: b, locale: l).hasPrefix("Sus epics, si tiene alguno, se detienen donde están"))
    #expect(removalText(RepoEpics(), appliesNow: false, bundle: b, locale: l).hasPrefix("No tiene epics. Puedes volver a añadirlo cuando quieras. Carrier lee la lista"))
    #expect(removalText(some, appliesNow: false, bundle: b, locale: l).hasPrefix("Tiene epics (2 en cola, 1 te necesita)."))
}

@Test func theRowsSayHowEachRepoIsInSpanish() throws {
    var snapshot = try running()
    let name = try #require(snapshot.watched?.first?.repo)
    let agents = try #require(snapshot.watched?.first?.agents)
    snapshot.watched = [PanelSnapshot.Watched(repo: name, lastCheckedAt: snapshot.now - 120_000, ok: true, error: nil, agents: agents),
                        PanelSnapshot.Watched(repo: "bad/repo", lastCheckedAt: snapshot.now, ok: false, error: nil, agents: agents)]
    let rows = repoRows(draft: [name, "bad/repo", "later/one", "new/repo"], saved: [name, "bad/repo", "later/one"], snapshot: snapshot, bundle: b, locale: l)
    #expect(rows[0].line.hasPrefix("Comprobado"))
    #expect(rows[1].line == "GitHub lo rechazó")
    #expect(rows[2].line == "Aún no se usa")
    #expect(rows[3].line == "Aún sin comprobar")
    #expect(repoRows(draft: ["a/b"], saved: ["a/b"], snapshot: nil, bundle: b, locale: l)[0].line == "Carrier está detenido")
}

// MARK: ready for Carrier

private let config = Data(#"""
{"repos":[{"name":"o/r"}],
 "profiles":{"me":{"kind":"gh"},"bot-a":{"kind":"forge"},"bot-c":{"kind":"forge"}},
 "agents":{"author":{"profile":"bot-a"},"reviewer":{"profile":"bot-c"}}}
"""#.utf8)

private func roles() -> [RepoRoleRow] { repoRoles(json: config, repo: "o/r")?.rows ?? [] }

@Test func theFourChecksOfARepoAreNamedInSpanishAndWaitingSaysItHasNotBeenChecked() {
    let waiting = repoChecks(repo: "o/r", roles: roles(), doctor: .checks([]), bundle: b, locale: l)
    #expect(waiting.rows.map(\.title) == ["Carrier puede leerlo", "Autor puede firmar aquí", "Revisor puede firmar aquí", "Solve está configurado"])
    #expect(waiting.rows.allSatisfy { $0.status == .waiting && $0.detail == "Aún sin comprobar" })
}

@Test func theDoctorsStateIsSaidAboveTheRowsInSpanish() {
    #expect(repoChecks(repo: "o/r", roles: [], doctor: .running, bundle: b, locale: l).note == "Ejecutando carrier doctor…")
    #expect(repoChecks(repo: "o/r", roles: [], doctor: .unknown("boom"), bundle: b, locale: l).note == "No se pudo comprobar: boom")
    #expect(repoChecks(repo: "o/r", roles: [], doctor: .refused("nope"), bundle: b, locale: l).note == "Carrier rechaza la configuración: nope")
    #expect(repoChecks(repo: "o/r", roles: [], doctor: .idle, bundle: b, locale: l).note == nil)
}

// MARK: projects to watch

private func project(_ name: String, repo: String?) -> ProjectRow { ProjectRow(path: "/p/\(name)", name: name, repo: repo, clone: nil) }

@Test func theProjectsThatCannotBeWatchedSayWhyInSpanish() {
    let choices = watchChoices(projects: [project("notes", repo: nil), project("web-old", repo: "other/web"), project("lib", repo: "acme/lib")], watched: ["acme/web"], bundle: b, locale: l)
    #expect(choices.map(\.project.name) == ["lib", "notes", "web-old"])
    #expect(choices[1].reason == "Sin origin de GitHub: Carrier vigila repositorios de GitHub")
    #expect(choices[2].reason == "other/web tiene el mismo nombre de carpeta que acme/web; las rutas de worktree de Solve no llevan propietario")
}

// MARK: a refused config

private func configProblem(_ path: String, _ problem: String) -> Refusal {
    Refusal(code: "config.problem", params: ["path": .string(path), "problem": .string(problem)], text: "any words at all")
}

@Test func aRefusedFailoverStepIsToldInSpanishWithTheRolesNameAndTheStepsNumber() {
    let banner = refusalBanner(configProblem("failover.roles.author.0", "stepOwnRole"), bundle: b, locale: l)
    #expect(banner.title == "Carrier no está usando tu última configuración")
    #expect(banner.detail == "El paso de respaldo 1 de Autor es el mismo proveedor y modelo que el propio Autor, así que no llevaría a ninguna parte.")
    #expect(banner.consequence == "Carrier conservó la configuración que tenía: lo que guardaste espera hasta que esto se corrija.")
    #expect(banner.fix == .roles && banner.fixTitle?.hasPrefix("Abrir ") == true)
    #expect(refusalBanner(configProblem("failover.roles.leadReviewer.1", "stepRepeated"), bundle: b, locale: l).detail?.contains("Revisor líder") == true)
    #expect(refusalBanner(configProblem("failover.roles.reviewer.0", "providerNotDeclared"), bundle: b, locale: l).detail?.contains("paso de respaldo 1 de Revisor") == true)
}

@Test func theWordsOfARefusalWithoutACodeAreTheEnginesOwnAndAreNotTranslated() {
    let banner = refusalBanner(.words("x: something"), bundle: b, locale: l)
    #expect(banner.detail == nil && banner.raw == "x: something" && banner.title == "Carrier no está usando tu última configuración")
}
