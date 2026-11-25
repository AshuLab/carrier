import Foundation
import Testing

@testable import CarrierCore

// The Providers page in Spanish (design/copy/es.json): who uses an account, what a tool and a server say of themselves, the first screen's summaries with their
// plural, what the page says in place of the list, the editor's names and checks and the search entries. Every plural and select has a Spanish case asserted, `one`
// included. The English words are asserted in the other files of this folder, with `english`.

private let b = spanish.bundle
private let l = spanish.locale

private let golden = testPaths().fixtures.appendingPathComponent("chat-providers.json")
private let now = 1_794_700_800_000

private func reply(_ json: String? = nil) throws -> HostProviders {
    try JSONDecoder().decode(HostProviders.self, from: json.map { Data($0.utf8) } ?? Data(contentsOf: golden))
}

private func page(_ json: String? = nil, config: Data? = nil) throws -> ProvidersPage { providersPage(try reply(json), config: config, chat: Data(#"{"agents":{}}"#.utf8)) }

private let config = Data(#"""
{"agents": {"author": {"provider": "claude"}, "reviewer": {"provider": "codex"}},
 "repos": [{"name": "acme/web", "agents": {"reviewer": {"provider": "claude-work"}}}],
 "failover": {"roles": {"author": [{"provider": "claude-work"}]}}}
"""#.utf8)

@Test func whoUsesAnAccountIsSaidInSpanish() throws {
    #expect(AccountUse.role(.leadReviewer).text(bundle: b, locale: l) == "Revisor líder")
    #expect(AccountUse.repoOverride(repo: "acme/web", role: .reviewer).text(bundle: b, locale: l) == "Revisor en acme/web")
    #expect(AccountUse.failover(nil).text(bundle: b, locale: l) == "Respaldo, orden por defecto")
    #expect(AccountUse.failover(.author).text(bundle: b, locale: l) == "Respaldo de Autor")
    #expect(AccountUse.chatAgent("work").text(bundle: b, locale: l) == "Agente de chat work")
    let found = try page(config: config)
    let work = try #require(found.tools[0].accounts.first { $0.name == "claude-work" })
    #expect(work.usedBy(bundle: b, locale: l) == "Lo usan: Revisor en acme/web, Respaldo de Autor")
    #expect(try #require(try page().tools[0].accounts.first).usedBy(bundle: b, locale: l) == "Aún sin uso")
}

@Test func eachStatusOfAToolIsSaidInSpanish() {
    typealias Status = ProviderTool.Status
    let all: [Status] = [.ready, .signedOut, .unknown, .missing, .foundNotAdded]
    #expect(all.map { $0.text(bundle: b, locale: l) } == ["Con sesión", "Sin sesión", "No se pudo comprobar", "No instalado", "Encontrado, sin añadir"])
}

@Test func theLocalServersSayWhetherTheyRunWithTheOneOfThePluralInSpanish() throws {
    let servers = try page().servers
    #expect(servers[0].status(bundle: b, locale: l) == "Detenido" && servers[1].status(bundle: b, locale: l) == "En marcha · 2 modelos")
    let one = try page(#"{"accounts":[],"unadded":[],"servers":[{"kind":"ollama","running":true,"models":["a"]}]}"#).servers[1]
    #expect(one.status(bundle: b, locale: l) == "En marcha · 1 modelo")
    #expect(servers.map { $0.generatorNote(bundle: b, locale: l) } == ["Detenido", nil])
    let empty = try page(#"{"accounts":[],"unadded":[],"servers":[{"kind":"lmstudio","running":true,"models":[]}]}"#).servers[0]
    #expect(empty.generatorNote(bundle: b, locale: l) == "Ningún modelo cargado")
}

@Test func theGeneratorInUseIsToldInSpanish() throws {
    let chosen = try page(#"{"accounts":[],"unadded":[],"servers":[{"kind":"ollama","running":true,"models":["qwen3:8b"]}],"textGenerator":{"name":"ollama","kind":"ollama","model":"qwen3:8b"}}"#)
    #expect(chosen.generatorInUse(bundle: b, locale: l) == "qwen3:8b en Ollama")
}

@Test func withoutAReplyThePageSaysWhyInSpanish() throws {
    #expect(ProvidersOutcome.unasked.note(bundle: b, locale: l) == "Mirando este Mac…")
    #expect(ProvidersOutcome.noHost.note(bundle: b, locale: l) == "El host del chat no está en marcha, así que no se miró este Mac. Abre Salud para ver por qué.")
    #expect(ProvidersOutcome.tooOld.note(bundle: b, locale: l)?.hasPrefix("El host del chat es demasiado antiguo") == true)
    #expect(ProvidersOutcome.failed("no responde").note(bundle: b, locale: l) == "El host del chat no pudo listar las herramientas de IA: no responde")
    let problem = try reply(#"{"accounts":[],"unadded":[],"servers":[],"problem":{"path":"providers.claude.harness","message":"Invalid option","code":"providers.invalid","params":{}}}"#)
    #expect(ProvidersOutcome.reply(problem).note(bundle: b, locale: l)?.hasPrefix("providers.json no es válido, así que no se muestra ninguna cuenta.") == true)
    #expect(ProvidersOutcome.reply(try reply()).note(bundle: b, locale: l) == nil)
}

@Test func theRetitleOutcomeCountsSessionsWithTheOneOfThePluralInSpanish() {
    #expect(RetitleOutcome.started(0).words(bundle: b, locale: l) == "Nada que titular: todas las sesiones ya tienen título")
    #expect(RetitleOutcome.started(1).words(bundle: b, locale: l) == "Se inició 1 sesión en segundo plano")
    #expect(RetitleOutcome.started(4).words(bundle: b, locale: l) == "Se iniciaron 4 sesiones en segundo plano")
    #expect(RetitleOutcome.refused("no").words(bundle: b, locale: l) == "no")
}

@Test func theFirstScreenSummarizesEachProviderWithThePluralOfTheAccountsThatNeedSomeone() throws {
    let directory = providersDirectory(try page(), quotas: [], now: now, bundle: b, locale: l)
    let summaries = Dictionary(uniqueKeysWithValues: directory.providers.map { ($0.id, $0.summary) })
    #expect(summaries["claude"] == "1 cuenta necesita atención" && summaries["codex"] == "No se pudo comprobar" && summaries["agy"] == "Encontrado, sin añadir")
    #expect(Copy.providersNeedAttention(count: 1, bundle: b, locale: l) == "1 cuenta necesita atención")
    #expect(Copy.providersNeedAttention(count: 3, bundle: b, locale: l) == "3 cuentas necesitan atención")
    #expect(Copy.providersAccountCount(count: 1, bundle: b, locale: l) == "1 cuenta" && Copy.providersAccountCount(count: 2, bundle: b, locale: l) == "2 cuentas")
    #expect(Copy.providersAllSignedIn(bundle: b, locale: l) == "Todas con sesión")
}

@Test func theSearchEntriesNameTheGroupsAndSayTheirDetailInSpanish() throws {
    let entries = providersSearchEntries(try page(), bundle: b, locale: l)
    let claude = try #require(entries.first { $0.rowID == "claude" && $0.groupID == "ai-providers" })
    #expect(claude.group == "Proveedores de IA" && claude.detail == "2 cuentas")
    let work = try #require(entries.first { $0.rowID == "claude-work" })
    #expect(work.detail == "Cuenta de Claude Code · claude-work")
}

@Test func theEditorsNamesOfIconsAndColorsAreSpanish() {
    #expect(AccountColor.allCases.prefix(3).map { $0.title(bundle: b, locale: l) } == ["Rojo", "Naranja", "Amarillo"])
    #expect(AccountColor.gray.title(bundle: b, locale: l) == "Gris")
    #expect(AccountIcon.bolt.title(bundle: b, locale: l) == "Rayo" && AccountIcon.star.title(bundle: b, locale: l) == "Estrella")
    #expect(IdleCompaction.allCases.map { $0.title(bundle: b, locale: l) } == ["Usar el valor por defecto", "Nunca", "Siempre"])
}

@Test func whatTheEditorChecksIsSaidInSpanish() {
    #expect(nameProblem("Bad Name", bundle: b, locale: l) == "El nombre debe ser una palabra en minúsculas: letras, dígitos y guiones, empezando por una letra, de hasta 40 caracteres.")
    #expect(nameProblem("work", bundle: b, locale: l) == nil)
    var draft = AccountDraft()
    draft.displayName = String(repeating: "x", count: 61)
    draft.label = String(repeating: "y", count: 40)
    draft.command = "relative/bin"
    draft.configDir = "x"
    draft.autoCompact = "5"
    draft.launchArgs = "--model\nopus"
    var problems = draftProblems(draft, harness: "claude", bundle: b, locale: l)
    #expect(problems["displayName"] == "El nombre visible es una sola línea de 60 caracteres como máximo.")
    #expect(problems["label"]?.hasPrefix("La etiqueta es una sola línea de ") == true)
    #expect(problems["command"] == "La ruta del binario debe ser absoluta o empezar por ~/.")
    #expect(problems["autoCompact"] == "Autocompactar después de, para Claude, es \"auto\" o un número de tokens de 100000 a 1000000.")
    #expect(problems["launchArgs"] == "Los argumentos de inicio no pueden repetir --model; Carrier ya lo define.")
    problems = draftProblems(draft, harness: "agy", bundle: b, locale: l)
    #expect(problems["configDir"] == "Antigravity no tiene ajuste de carpeta de configuración." && problems["autoCompact"] == "Antigravity no tiene ajuste de autocompactado.")
    draft.autoCompact = "0"
    #expect(draftProblems(draft, harness: "codex", bundle: b, locale: l)["autoCompact"] == "Autocompactar después de, para Codex, es un número de tokens mayor que cero.")
}
