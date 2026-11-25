import Foundation
import Testing

@testable import CarrierCore

// The Engine page in Spanish (design/copy/es.json): its four groups and their rows, the programs' versions and problems, the identity's problems, the Files
// buttons, the readiness banner and what the page says when the engine did not apply a save. The English words are asserted in the other files of this folder,
// with `english`.

private let b = spanish.bundle
private let l = spanish.locale

private func programs(
    carrier: String? = "/opt/homebrew/bin/carrier", own: Bool = false, version: String? = "1.4.2", node: String = "/opt/homebrew/bin/node",
    path: String = "/opt/homebrew/bin:/usr/bin", nodeVersion: String? = "v22.1.0", runs: Bool = true, read: Bool = true
) -> EnginePrograms {
    EnginePrograms(
        carrier: carrier, carrierIsOwn: own, carrierVersion: version, setup: SetupSettings(node: node, path: path), nodeVersion: nodeVersion, carrierRuns: runs, versionsRead: read)
}

private func page(
    configured: Bool, programs: EnginePrograms = programs(), identity: EngineIdentity? = nil, exists: @escaping (String) -> Bool = { _ in true }
) -> [EngineGroup] {
    engineGroups(configured: configured, programs: programs, identity: identity, folder: "/h/.carrier", home: "/h", exists: exists, bundle: b, locale: l)
}

@Test func theEnginePageSaysItsGroupsAndTheStartingRowsInSpanish() {
    let groups = page(configured: true)
    #expect(groups.map(\.title) == ["Inicio", "Programas", "Identidad en GitHub", "Archivos"])
    #expect(groups[0].rows.map(\.title) == ["Iniciar Carrier al abrir la app", "Preguntar antes de detener Carrier"])
    #expect(groups[0].rows[0].detail == "Carrier empieza a trabajar en los epics listos en cuanto se abre la app")
    #expect(groups[0].rows[1].detail == "Solo cuando detenerlo interrumpiría epics en marcha")
    #expect(page(configured: false)[0].rows[0].detail == "No hace nada hasta que el motor esté configurado")
}

@Test func theProgramsSayTheirVersionsAndWhatIsMissingInSpanish() {
    let rows = page(configured: true)[1].rows
    #expect(rows[0].detail == "Versión 1.4.2" && rows[1].detail == "Versión 22.1.0")
    #expect(rows[2].detail == "Con lo que se ejecutan el motor y el host del chat")
    #expect(rows[3].title == "Buscar las herramientas de nuevo")
    let reading = page(configured: true, programs: programs(version: nil, nodeVersion: nil, read: false))[1].rows
    #expect(reading[0].detail == "Leyendo la versión…" && reading[1].detail == "Leyendo la versión…")
    let silent = page(configured: true, programs: programs(version: nil, nodeVersion: nil))[1].rows
    #expect(silent[0].problem == "No respondió a “carrier --version”" && silent[1].problem == "No respondió a “node --version”")
    let none = page(configured: true, programs: programs(carrier: nil, node: "", path: ""))[1].rows
    #expect(none[0].note == "No encontrado" && none[1].note == "No encontrado")
    #expect(none[2].detail == "Aún no se encontró, así que el motor y el host del chat parten del PATH del sistema")
    let own = page(configured: true, programs: programs(own: true, runs: false))[1].rows[0]
    #expect(own.detail == "Tu propio carrier · Versión 1.4.2" && own.problem == "No se ejecuta nada en esta ruta" && own.offersHomebrew)
}

@Test func theIdentityRowSaysItsProblemsInSpanish() throws {
    let identity = try #require(EngineIdentity(config: Data(#"{"profiles":{"bot":{}},"orchestratorProfile":"gone"}"#.utf8)))
    let row = page(configured: true, identity: identity)[2].rows[0]
    #expect(row.title == "Carrier actúa en GitHub como" && row.problem == "“gone” no está en profiles; se conserva hasta que elijas otra")
    #expect(row.detail == "Lee issues y PRs y cambia etiquetas. Por defecto es la identidad del autor")
    #expect(page(configured: true, identity: nil)[2].rows[0].problem == "engine.json de la carpeta de Carrier no se pudo leer o no es un objeto JSON")
    #expect(page(configured: false)[2].rows[0].detail == "Disponible cuando el motor esté configurado")
}

@Test func theFilesRowsAndTheirButtonsAreSaidInSpanish() {
    let present = page(configured: true)[3].rows
    #expect(present.map(\.title) == ["Carpeta de Carrier", "Registros", "Registro de inicio"])
    #expect(present.map { $0.file?.buttonTitle(bundle: b, locale: l) } == ["Mostrar", "Mostrar", "Abrir"])
    let missing = page(configured: true, exists: { $0 == "/h/.carrier" })[3].rows
    #expect(missing.map { $0.file?.buttonTitle(bundle: b, locale: l) } == ["Mostrar", "Aún no creado", "Aún no creado"])
}

@Test func theReadinessBannerSaysWhatCarrierNeedsInSpanishWithTwoNamesJoinedByY() {
    #expect(readinessBanner(missing: [], detecting: false, bundle: b, locale: l).title == "Iniciar Carrier está listo")
    #expect(readinessBanner(missing: [], detecting: false, bundle: b, locale: l).detail == "Se encontró todo lo que necesita.")
    #expect(readinessBanner(missing: ["carrier"], detecting: false, bundle: b, locale: l).title == "Iniciar Carrier necesita carrier")
    #expect(readinessBanner(missing: ["carrier", "node"], detecting: false, bundle: b, locale: l).title == "Iniciar Carrier necesita carrier y node")
    #expect(readinessBanner(missing: ["carrier"], detecting: false, bundle: b, locale: l).detail
        == "Instala carrier con Homebrew, o usa “Usar otro…” y luego Detectar en Programas, en la página Motor.")
    #expect(readinessBanner(missing: [], detecting: true, bundle: b, locale: l).title == "Buscando lo que Carrier necesita")
}

@Test func whatThePageSaysWhenTheEngineDidNotApplyASaveIsSpanishAndTheEnginesReasonIsItsOwn() {
    #expect(reloadWords(.refused(.words("limits.maxReviews: bad")), bundle: b, locale: l) == "Guardado, pero Carrier conservó su configuración: limits.maxReviews: bad")
    #expect(reloadWords(.noAnswer, bundle: b, locale: l) == "Guardado, pero Carrier no respondió: puede que no lo haya aplicado.")
    // a reason with a code is said in Spanish too
    let coded = Refusal(code: "session.switching", text: "This session is switching to another agent; try again in a moment")
    #expect(reloadWords(.refused(coded), bundle: b, locale: l) == "Guardado, pero Carrier conservó su configuración: Esta sesión está cambiando a otro agente; inténtalo de nuevo en un momento")
    #expect(reloadWords(.applied, bundle: b, locale: l) == nil)
}

@MainActor @Test func theStatusOfTheLastAskWordsItsAnswerInSpanish() {
    let status = ReloadStatus(reload: { .applied })
    status.record(.noAnswer)
    #expect(status.words(bundle: b, locale: l) == "Guardado, pero Carrier no respondió: puede que no lo haya aplicado.")
}
