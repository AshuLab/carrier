import Foundation
import Testing

@testable import CarrierCore

// The Roles page in Spanish (design/copy/es.json): the roles and what they do, a role's summary and identity, the readiness lines with their plural, the
// stages, the notes about the registry and the signature, and what the engine would refuse in a role's fields. The English words are asserted in the other
// files of this folder, with `english`.

private let b = spanish.bundle
private let l = spanish.locale

private func config(author: String = #"{"profile": "acme-author", "provider": "claude", "model": "sonnet", "effort": "high"}"#,
                    reviewer: String = #"{"profile": "acme-reviewer", "provider": "codex", "model": "gpt-5"}"#,
                    lead: String? = #"{"profile": "acme-lead", "provider": "claude", "model": "opus"}"#) -> String {
    """
    {"profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}, "acme-reviewer": {"kind": "forge", "agent": "acme-reviewer"},
                  "acme-lead": {"kind": "forge", "agent": "acme-lead"}, "me": {"kind": "gh"}},
     "agents": {"author": \(author), "reviewer": \(reviewer)\(lead.map { ", \"leadReviewer\": \($0)" } ?? "")}}
    """
}

private let bots = ForgeBots(names: ["acme-author", "acme-reviewer", "acme-lead"], note: nil)

private func page(_ json: String, bots: ForgeBots = bots) throws -> RolesPage {
    try #require(rolesPage(config: Data(json.utf8), providers: nil, bots: bots, bundle: b, locale: l))
}

private func readiness(_ json: String) throws -> RolesReadiness { rolesReadiness(try page(json), bundle: b, locale: l) }

@Test func theRolesAndWhatEachOneDoesAreNamedInSpanish() {
    #expect(AgentRole.allCases.map { $0.title(bundle: b, locale: l) } == ["Autor", "Revisor", "Revisor líder"])
    #expect(AgentRole.author.purpose(bundle: b, locale: l) == "Escribe el código del epic y responde al revisor")
    #expect(AgentRole.reviewer.purpose(bundle: b, locale: l) == "Revisa el pull request final")
    #expect(AgentRole.leadReviewer.purpose(bundle: b, locale: l).hasPrefix("Opcional."))
}

@Test func aRolesSummaryHeadlineAndIdentitySaySpanishWordsAroundTheConfigsOwn() throws {
    let found = try page(config(lead: nil))
    let author = try #require(found.rows.first { $0.role == .author })
    #expect(author.title(bundle: b, locale: l) == "Autor" && author.summary(bundle: b, locale: l) == "acme-author · claude · sonnet · high")
    #expect(author.identityDetail(bundle: b, locale: l) == "Un bot de Agent Forge")
    let lead = try #require(found.rows.first { $0.role == .leadReviewer })
    #expect(lead.summary(bundle: b, locale: l) == "Desactivado" && lead.headline(bundle: b, locale: l) == "Desactivado")
    #expect(lead.identityDetail(bundle: b, locale: l) == "Sin definir")
    let own = try page(#"{"profiles": {"me": {"kind": "gh"}}, "agents": {"author": {"profile": "me", "provider": "claude", "model": "m"}}}"#, bots: forgeBots(registry: nil))
    #expect(try #require(own.rows.first { $0.role == .author }).identityDetail(bundle: b, locale: l) == "Tu sesión de gh")
    let gone = try page(config(), bots: ForgeBots(names: ["acme-author"], note: nil))
    #expect(try #require(gone.rows.first { $0.role == .reviewer }).identityDetail(bundle: b, locale: l) == "“acme-reviewer” no está en la lista de Agent Forge ni en profiles; se conserva")
}

@Test func theRegistryMissingOrUnreadableSaysSoInSpanish() {
    #expect(forgeBots(registry: nil, bundle: b, locale: l).note == "No se encontró ningún registro de Agent Forge, así que solo se ofrece tu sesión de gh. Crea un bot para añadir uno.")
    #expect(forgeBots(registry: Data("no".utf8), bundle: b, locale: l).note == "No se pudo leer el registro de Agent Forge, así que solo se ofrece tu sesión de gh.")
}

@Test func twoRolesOfOneAccountSaySoInSpanish() throws {
    let same = #"{"profiles": {"a": {"kind": "forge", "agent": "bot"}, "b": {"kind": "forge", "agent": "bot"}}, "agents": {"author": {"profile": "a"}, "reviewer": {"profile": "b"}}}"#
    #expect(try page(same).sharedNote == "El autor y el revisor son una sola cuenta (a y b): la firma lo mostrará.")
    let twice = #"{"profiles": {"a": {"kind": "forge", "agent": "bot"}}, "agents": {"author": {"profile": "a"}, "reviewer": {"profile": "a"}}}"#
    #expect(try page(twice).sharedNote == "El autor y el revisor trabajan los dos como a: la firma lo mostrará.")
}

@Test func theReadinessSaysItsLinesInSpanish() throws {
    let whole = try readiness(config())
    #expect(whole.title == "Los tres roles están configurados" && whole.notes == ["Cada uno tiene una identidad, una cuenta y un modelo."])
    let two = try readiness(config(lead: nil))
    #expect(two.title == "El autor y el revisor están configurados" && two.notes == ["El revisor líder está desactivado."])
}

@Test func theReadinessCountsTheRolesThatNeedAttentionWithTheOneOfThePlural() throws {
    #expect(try readiness(config(author: "{}")).title == "Un rol necesita atención")
    #expect(try readiness(config(author: "{}", reviewer: "{}")).title == "2 roles necesitan atención")
    #expect(Copy.rolesNeedAttention(count: 1, bundle: b, locale: l) == "Un rol necesita atención")
    #expect(Copy.rolesNeedAttention(count: 3, bundle: b, locale: l) == "3 roles necesitan atención")
}

@Test func whatIsWrongWithARoleIsSaidInSpanishAndNamesItsRole() throws {
    let nothing = try readiness(config(author: "{}"))
    #expect(nothing.problems.filter { $0.role == .author }.map(\.text) == ["todavía no tiene identidad.", "todavía no tiene cuenta.", "todavía no tiene modelo."])
    #expect(nothing.notes.first == "Autor: todavía no tiene identidad.")
    let gone = try readiness(config(reviewer: #"{"profile": "gone", "provider": "codex", "model": "gpt-5"}"#))
    #expect(gone.notes.first == "Revisor: la identidad “gone” no está en Agent Forge ni en profiles. Elige otra.")
    let unknown = try #require(rolesPage(config: Data(config().utf8), providers: Data(#"{"providers": {"claude": {"harness": "claude"}}}"#.utf8), bots: bots, bundle: b, locale: l))
    #expect(rolesReadiness(unknown, bundle: b, locale: l).problems.map(\.text).contains("la cuenta “codex” no está en providers.json."))
}

@Test func theStagesOfARoleAreSaidInSpanishWithTheSkillTheEngineRuns() {
    let author = AgentRole.author.stages(bundle: b, locale: l)
    #expect(author.map(\.title) == ["Primera pasada", "Respuesta a una revisión"] && author.map(\.skill) == ["ship", "code-resolve"])
    #expect(author[0].detail == "Drena el epic en su propio worktree y deja abierto el pull request final")
    let reviewer = AgentRole.reviewer.stages(bundle: b, locale: l)
    #expect(reviewer.map(\.title) == ["Revisión", "Publicar los hallazgos"] && reviewer[1].detail == "Publica los hallazgos en el pull request")
    #expect(AgentRole.leadReviewer.stages(bundle: b, locale: l).map(\.title) == ["Revisión del líder", "Publicar y aprobar"])
    #expect(Copy.rolesRailPasses(rounds: 3, bundle: b, locale: l) == "Cuando todos los revisores coinciden · hasta 3 rondas con el autor")
}

@Test func whatTheEngineWouldRefuseInARolesFieldsIsSaidInSpanish() {
    let fields = RoleFields(profile: "ghost", provider: "nope", effort: "huge", persona: RolePersona(name: String(repeating: "a", count: 41), prompt: String(repeating: "p", count: 4001)))
    let problems = fields.problems(profiles: ["me"], accounts: ["claude"], bundle: b, locale: l)
    #expect(problems == [
        "La identidad “ghost” no está declarada en profiles. Elige otra.",
        "El proveedor “nope” no es una cuenta de providers.json. Elige otro.",
        "El esfuerzo debe ser uno de \(roleEfforts.joined(separator: ", ")).",
        "El nombre de la persona es una línea de hasta 40 caracteres.",
        "El prompt de la persona tiene hasta 4000 caracteres.",
    ])
}

@Test func theFailoverNoteCountsTheStepsTheFileKeepsWithTheOneOfThePlural() {
    #expect(Copy.rolesMoreSteps(count: 1, bundle: b, locale: l) == "El archivo tiene 1 paso más, conservados y probados en orden.")
    #expect(Copy.rolesMoreSteps(count: 3, bundle: b, locale: l) == "El archivo tiene 3 pasos más, conservados y probados en orden.")
}

@Test func theRepoRolesSaySpanishWordsAndTheSignatureNoteToo() throws {
    let json = Data(#"{"profiles": {"x": {"kind": "gh"}}, "agents": {"author": {"profile": "x", "provider": "claude", "model": "sonnet"}, "reviewer": {"profile": "x", "provider": "codex"}}, "repos": [{"name": "a/b"}]}"#.utf8)
    let roles = try #require(repoRoles(json: json, repo: "a/b"))
    #expect(roles.rows[0].value.text(bundle: b, locale: l) == "x · claude · sonnet" && RoleFields().text(bundle: b, locale: l) == "Sin definir")
    #expect(signatureNote(roles.rows, bundle: b, locale: l) == "El autor y el revisor trabajan los dos como x: la firma lo mostrará.")
    let page = try #require(repoRolesPage(config: json, providers: nil, bots: bots, repo: "a/b", bundle: b, locale: l))
    #expect(page.rows.map { $0.title(bundle: b, locale: l) } == ["Autor", "Revisor", "Revisor líder"])
}
