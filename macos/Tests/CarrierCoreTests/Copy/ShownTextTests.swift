import Foundation
import Testing

@testable import CarrierCore

// What a person reads for a text that carries a code (docs/adr/0055): the copy of a known code in the language of the bundle and locale, and the words
// Node sent for an unknown code, no code, or a text stored before the codes. The words are English, so these tests render with `Copy.bundle`.

private let en = (bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
private let es = (bundle: Copy.bundle("es"), locale: Locale(identifier: "es_AR"))

// MARK: Copy.text

@Test func aRefusalADoctorDetailAndANoticeAreSaidInBothLanguages() {
    #expect(Copy.text("session.switching", bundle: en.bundle, locale: en.locale) == "This session is switching to another agent; try again in a moment")
    #expect(Copy.text("session.switching", bundle: es.bundle, locale: es.locale) == "Esta sesión está cambiando a otro agente; inténtalo de nuevo en un momento")
    let server: [String: TextParam] = ["server": "LM Studio", "url": "http://localhost:1234"]
    #expect(Copy.text("doctor.serverNotAnswering", server, bundle: en.bundle, locale: en.locale) == "LM Studio is not answering at http://localhost:1234; start its server")
    #expect(Copy.text("doctor.serverNotAnswering", server, bundle: es.bundle, locale: es.locale) == "LM Studio no responde en http://localhost:1234; arranca su servidor")
    #expect(Copy.text("session.notice.conversationLost", bundle: es.bundle, locale: es.locale)?.hasPrefix("El agente no encontró esta conversación") == true)
    #expect(Copy.text("session.notice.conversationLost", bundle: en.bundle, locale: en.locale)?.hasPrefix("The agent could not find this conversation") == true)
}

@Test func aCodeWithACountSaysItsPluralAndTheArgumentsGoInTheOrderOfTheKey() {
    func dirty(_ count: TextParam, _ language: (bundle: Bundle, locale: Locale)) -> String? {
        Copy.text("workspace.dirty", ["branch": "main", "count": count], bundle: language.bundle, locale: language.locale)
    }
    #expect(dirty(1, en) == "The folder has 1 uncommitted file, so its branch was not changed to main. Save the work and try again.")
    #expect(dirty(2, en) == "The folder has 2 uncommitted files, so its branch was not changed to main. Save the work and try again.")
    #expect(dirty(1, es) == "La carpeta tiene 1 archivo sin confirmar, así que su rama no se cambió a main. Guarda el trabajo e inténtalo de nuevo.")
    #expect(dirty(2, es) == "La carpeta tiene 2 archivos sin confirmar, así que su rama no se cambió a main. Guarda el trabajo e inténtalo de nuevo.")
    // a key whose arguments are a string, a number and a string, in the order the English sentence first names them
    #expect(Copy.text("epic.stop.retriesExhausted", ["stage": "review", "attempts": 3, "failure": "no verdict", "idle": 0], bundle: en.bundle, locale: en.locale) == "ran out of review retries (3 attempts): no verdict")
}

@Test func aSelectPicksItsBranchAndFallsBackToOther() {
    #expect(Copy.text("agent.notInstalled", ["agent": "Codex"], bundle: es.bundle, locale: es.locale) == "Codex no está instalado: no hay ningún \"codex\" en el path")
    #expect(Copy.text("agent.notInstalled", ["agent": "Gemini"], bundle: en.bundle, locale: en.locale) == "The agent is not installed")
    #expect(Copy.text("agent.notInstalled", [:], bundle: en.bundle, locale: en.locale) == nil)
}

@Test func aCodeTheCatalogLacksGivesNothing() {
    #expect(Copy.text("session.noSuchCode", bundle: en.bundle, locale: en.locale) == nil)
    #expect(Copy.text("", bundle: en.bundle, locale: en.locale) == nil)
}

@Test func paramsThatDoNotFitTheKeyGiveNothingAndDoNotCrash() {
    // lacks one the key takes
    #expect(Copy.text("account.taken", [:], bundle: en.bundle, locale: en.locale) == nil)
    #expect(Copy.text("account.inUse", ["name": "work"], bundle: en.bundle, locale: en.locale) == nil)
    // a number where the key takes a string, and a string or a fraction where it takes a number
    #expect(Copy.text("account.taken", ["name": 7], bundle: en.bundle, locale: en.locale) == nil)
    #expect(Copy.text("workspace.dirty", ["branch": "main", "count": "two"], bundle: en.bundle, locale: en.locale) == nil)
    #expect(Copy.text("workspace.dirty", ["branch": "main", "count": .number(1.5)], bundle: en.bundle, locale: en.locale) == nil)
    // a param the key does not take is not a reason to hide the copy (a golden code lists params that its sentence already says)
    #expect(Copy.text("account.taken", ["name": "work", "extra": "x"], bundle: en.bundle, locale: en.locale) == "There is already an account named work.")
}

// MARK: each place

@Test func aRefusalShowsTheCopyOfItsKnownCodeAndTheWordsOtherwise() {
    let known = Refusal(code: "account.taken", params: ["name": "work"], text: "words of Node")
    #expect(known.shown(bundle: es.bundle, locale: es.locale) == "Ya hay una cuenta llamada work.")
    #expect(known.shown(bundle: en.bundle, locale: en.locale) == "There is already an account named work.")
    #expect(Refusal(code: "session.noSuchCode", text: "an unknown one").shown(bundle: es.bundle, locale: es.locale) == "an unknown one")
    #expect(Refusal.words("a reply with no code").shown(bundle: es.bundle, locale: es.locale) == "a reply with no code")
    // a code whose key takes a param the refusal lacks, and a param of the wrong kind
    #expect(Refusal(code: "account.taken", text: "no params").shown(bundle: es.bundle, locale: es.locale) == "no params")
    #expect(Refusal(code: "account.taken", params: ["name": 7], text: "wrong kind").shown(bundle: es.bundle, locale: es.locale) == "wrong kind")
}

@Test func theRefusalsTheAppMakesItselfAreInTheCatalogToo() {
    for refusal in appRefusals {
        #expect(Copy.text(refusal.code ?? "", refusal.params, bundle: en.bundle, locale: en.locale) != nil, "\(refusal.code ?? "no code")")
    }
}

@Test func aDoctorDetailAndFixShowTheCopyOfTheirCodeAndTheWordsOtherwise() {
    let known = DoctorCheck(
        name: "server", status: .fail, detail: "words", fix: "more words",
        detailCode: "doctor.serverNotAnswering", detailParams: ["server": "Ollama", "url": "http://localhost:11434"], fixCode: "doctor.fix.ghLogin", fixParams: [:]
    )
    #expect(known.shownDetail(bundle: es.bundle, locale: es.locale) == "Ollama no responde en http://localhost:11434; arranca su servidor")
    #expect(known.shownFix(bundle: es.bundle, locale: es.locale) == "ejecuta: gh auth login")
    let unknown = DoctorCheck(name: "x", status: .fail, detail: "words", fix: "more words", detailCode: "doctor.noSuchCode", fixCode: "doctor.fix.noSuchCode")
    #expect(unknown.shownDetail(bundle: es.bundle, locale: es.locale) == "words" && unknown.shownFix(bundle: es.bundle, locale: es.locale) == "more words")
    let none = DoctorCheck(name: "x", status: .ok, detail: "stored words")
    #expect(none.shownDetail(bundle: es.bundle, locale: es.locale) == "stored words" && none.shownFix(bundle: es.bundle, locale: es.locale) == nil)
}

@Test func theHealthRowsShowTheDetailAndFixOfACheckThroughItsCode() {
    let check = DoctorCheck(name: "gh", status: .fail, detail: "words", fix: "more words", detailCode: "doctor.noSuchCode", fixCode: "doctor.fix.ghLogin", fixParams: [:])
    let fix = Copy.text("doctor.fix.ghLogin")
    let facts = CarrierFacts(carrierFound: true, installedVersion: "1.4.0", hostRunning: true, hostVersion: "1.4.0", hostReportsHealth: true, configExists: true, engineRunning: true)
    let rows = healthSections(host: nil, facts: facts, doctor: .checks([check])).flatMap(\.rows)
    #expect(rows.contains { $0.detail == "words" && $0.fix == fix })
}

@Test func aChatNoticeAndAPreparationStepShowTheCopyOfTheirCodeAndTheWordsOtherwise() {
    let notice = ChatEvent(id: 1, at: 1, kind: "notice", text: "words", code: "session.notice.conversationLost", params: [:])
    #expect(notice.shown(notice.text, bundle: es.bundle, locale: es.locale)?.hasPrefix("El agente no encontró esta conversación") == true)
    #expect(ChatEvent(id: 2, at: 2, kind: "notice", text: "words", code: "session.notice.noSuchCode").shown("words", bundle: es.bundle, locale: es.locale) == "words")
    #expect(ChatEvent(id: 3, at: 3, kind: "notice", text: "stored words").shown("stored words", bundle: es.bundle, locale: es.locale) == "stored words")
    // the feed and the steps go through it
    func line(_ event: ChatEvent) -> String? {
        chatFeed([event], working: false, bundle: english.bundle, locale: english.locale).compactMap { if case .line(_, let text) = $0 { text } else { nil } }.first
    }
    #expect(line(notice) == Copy.text("session.notice.conversationLost"))
    #expect(line(ChatEvent(id: 2, at: 2, kind: "notice", text: "words", code: "session.notice.noSuchCode")) == "words")
    #expect(line(ChatEvent(id: 3, at: 3, kind: "notice", text: "stored words")) == "stored words")
    func reason(_ code: String?) -> String? {
        let failed = ChatEvent(id: 1, at: 1, kind: "step", status: "failed", step: "worktree", detail: "words", code: code, params: [:])
        return preparationSteps([failed], preparation: .failed).first?.reason
    }
    #expect(reason("session.notice.conversationLost") == Copy.text("session.notice.conversationLost"))
    #expect(reason("session.noSuchCode") == "words" && reason(nil) == "words")
}

@Test func theReasonAnEpicNeedsAHumanShowsTheCopyOfItsCodeAndTheWordsOtherwise() {
    func epic(code: String?, params: [String: TextParam]? = nil) -> PanelEpic {
        var epic = PanelEpic(
            repo: "a/b", issue: 1, status: .needsHuman, stage: .ship, round: nil, maxReviews: 3, blockers: 0, stageSince: 0, lastActivityAt: nil,
            issueUrl: "u", prUrl: nil, lastError: nil, needsHumanReason: "words", slices: nil, executionId: nil
        )
        (epic.needsHumanCode, epic.needsHumanParams) = (code, params)
        return epic
    }
    #expect(epic(code: "epic.stop.timeout", params: ["stage": "ship", "limit": "4h"]).shownNeedsHumanReason(bundle: es.bundle, locale: es.locale)?.hasPrefix("la ejecución de ship superó el límite de tiempo de 4h") == true)
    #expect(epic(code: "epic.stop.noSuchCode").shownNeedsHumanReason(bundle: es.bundle, locale: es.locale) == "words")
    #expect(epic(code: nil).shownNeedsHumanReason(bundle: es.bundle, locale: es.locale) == "words")
    #expect(epic(code: "epic.stop.timeout", params: ["stage": "ship"]).shownNeedsHumanReason(bundle: es.bundle, locale: es.locale) == "words")
}

@Test func aProvidersProblemShowsTheCopyOfItsCodeAndTheWordsOtherwise() throws {
    func problem(_ extra: String) throws -> HostProviders.Problem {
        try JSONDecoder().decode(HostProviders.Problem.self, from: Data(#"{"path":"/x/providers.json","message":"words"\#(extra)}"#.utf8))
    }
    let known = try problem(#","code":"providers.invalid","params":{"path":"/x/providers.json"}"#)
    #expect(known.shown(bundle: es.bundle, locale: es.locale) == "El archivo de proveedores /x/providers.json no es válido")
    #expect(try problem(#","code":"providers.noSuchCode","params":{}"#).shown(bundle: es.bundle, locale: es.locale) == "/x/providers.json: words")
    #expect(try problem("").shown(bundle: es.bundle, locale: es.locale) == "/x/providers.json: words")
}

@Test func aUsageMessageShowsTheCopyOfItsCodeAndTheWordsOtherwise() throws {
    func quota(_ extra: String) throws -> UsageQuota {
        try JSONDecoder().decode(UsageQuota.self, from: Data(#"{"account":"claude","provider":"claude","status":"unavailable","message":"words"\#(extra)}"#.utf8))
    }
    #expect(try quota(#","messageCode":"usage.probe.claudeCredentialsEmpty","messageParams":{}"#).shownMessage(bundle: es.bundle, locale: es.locale) == "las credenciales de Claude no contienen ningún inicio de sesión")
    #expect(try quota(#","messageCode":"usage.noSuchCode""#).shownMessage(bundle: es.bundle, locale: es.locale) == "words")
    #expect(try quota("").shownMessage(bundle: es.bundle, locale: es.locale) == "words")
}

@Test func aClonesErrorAndACleanupsSkippedReasonShowTheCopyOfTheirCodeAndTheWordsOtherwise() {
    let clone = ProjectClone(repo: "a/b", folder: "/x", state: .failed, error: "words", code: "account.taken", params: ["name": "work"])
    #expect(clone.shownError(bundle: es.bundle, locale: es.locale) == "Ya hay una cuenta llamada work.")
    #expect(ProjectClone(repo: "a/b", folder: "/x", state: .failed, error: "words", code: "x.noSuchCode").shownError(bundle: es.bundle, locale: es.locale) == "words")
    #expect(ProjectClone(repo: "a/b", folder: "/x", state: .cloning).shownError(bundle: es.bundle, locale: es.locale) == nil)
    let skipped = ProjectCleanup.Skipped(path: "/x/w", reason: "words", code: "account.taken", params: ["name": "work"])
    #expect(skipped.shownReason(bundle: es.bundle, locale: es.locale) == "Ya hay una cuenta llamada work.")
    #expect(ProjectCleanup.Skipped(path: "/x/w", reason: "words").shownReason(bundle: es.bundle, locale: es.locale) == "words")
}
