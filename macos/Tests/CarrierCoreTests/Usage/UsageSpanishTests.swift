import Foundation
import Testing

@testable import CarrierCore

// The Usage area in Spanish (design/copy/es.json): the quota list, the cards, the chart's tooltip, the tables, the price form's checks and what the ring beside
// the microphone says each say their Spanish words, and every plural and select has a Spanish case asserted, `one` included. The English words are asserted in
// the other files of this folder, with `english`. Numbers are said in Argentina's locale, whose thousands take a dot and whose decimals a comma.

private let b = spanish.bundle
private let l = spanish.locale

private let goldenFile = testPaths().fixtures.appendingPathComponent("chat-usage.json")
private func golden() throws -> UsageSnapshot { try JSONDecoder().decode(UsageSnapshot.self, from: Data(contentsOf: goldenFile)) }
private func decode(_ json: String) throws -> UsageSnapshot { try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8)) }

/// Inside the fixture's day: the Claude 5h resets 10 800 s later.
private let now = 1_794_700_800_000

private func providers(_ quotas: [UsageQuota]) -> [UsageProviderRow] { usageProviders(quotas, now: now, bundle: b, locale: l) }

private func quota(_ json: String) throws -> UsageQuota { try JSONDecoder().decode(UsageQuota.self, from: Data(json.utf8)) }

// MARK: the quota list

@Test func theListNamesItsProvidersAndSaysEachStatusInSpanish() throws {
    let rows = providers(try golden().quotas)
    #expect(rows.map(\.title) == ["Claude", "Codex", "Antigravity", "Servidores locales"])
    #expect(rows[0].earliestReset == "Se restablece en 3h 00m" && rows[0].subtitle == "2 cuentas · sin sesión")
    #expect(rows[1].subtitle == "Con límite de uso" && rows[2].subtitle == "Listo" && rows[3].subtitle == "1 de 2 en marcha")
    #expect(rows[0].accounts.map(\.status) == ["Plan Max", "Sin sesión"] && rows[1].accounts[0].status == "Con límite de uso")
}

@Test func everyStatusAQuotaCanHaveIsSaidInSpanish() throws {
    func status(_ json: String) throws -> String {
        try #require(providers([try quota(#"{"account":"x","provider":"claude",\#(json)}"#)]).first).accounts[0].status
    }
    #expect(try status(#""status":"ok""#) == "Listo" && status(#""status":"ok","stale":true"#) == "Últimos números conocidos")
    #expect(try status(#""status":"ok","planType":"pro""#) == "Plan Pro")
    #expect(try status(#""status":"signed_out""#) == "Sin sesión" && status(#""status":"missing""#) == "Sin configurar")
    #expect(try status(#""status":"unavailable""#) == "No disponible" && status(#""status":"rate_limited""#) == "Con límite de uso")
    #expect(try status(#""status":"error""#) == "Falló la comprobación")
}

@Test func severalAccountsAreCountedAndTheOneThatNeedsALookIsNamedInSpanish() throws {
    let ok = #"{"account":"a","provider":"codex","status":"ok"}"#
    let out = #"{"account":"b","provider":"codex","status":"signed_out"}"#
    #expect(providers([try quota(ok), try quota(ok.replacingOccurrences(of: #""a""#, with: #""c""#))])[0].subtitle == "2 cuentas")
    #expect(providers([try quota(ok), try quota(out)])[0].subtitle == "2 cuentas · sin sesión")
    // the one of the plural that a list of accounts never reaches, said all the same
    #expect(Copy.usageAccounts(count: 1, bundle: b, locale: l) == "1 cuenta" && Copy.usageAccounts(count: 3, bundle: b, locale: l) == "3 cuentas")
    #expect(Copy.usageAccountsProblem(count: 1, status: "sin sesión", bundle: b, locale: l) == "1 cuenta · sin sesión")
}

@Test func aProvidersWordsWithACodeAreSaidInSpanishAndTheHostsOwnWordsAreNot() throws {
    let coded = try quota(#"{"account":"codex","provider":"codex","status":"rate_limited","message":"Codex is rate limiting this check","messageCode":"usage.probe.codexRateLimited"}"#)
    #expect(providers([coded])[0].accounts[0].note == "Codex está limitando esta comprobación")
    // a text that came with no code is what the host wrote
    #expect(providers(try golden().quotas)[0].accounts[1].note == "Not signed in. Run claude and sign in.")
}

@Test func aWindowIsNamedInSpanishAndAResetIsCountedDown() {
    #expect(QuotaKind.fiveHour.title(bundle: b, locale: l) == "5 h" && QuotaKind.weekly.title(bundle: b, locale: l) == "Semanal")
    #expect(QuotaKind.monthly.title(bundle: b, locale: l) == "Mensual")
    #expect(resetText(resetsAt: now + 8_040_000, label: nil, now: now, bundle: b, locale: l) == "Se restablece en 2h 14m")
    #expect(resetText(resetsAt: now - 1, label: "in 3 hours", now: now, bundle: b, locale: l) == nil)
    #expect(resetText(resetsAt: nil, label: "in 3 hours", now: now, bundle: b, locale: l) == "in 3 hours")
}

@Test func claudesDrawerSaysItsRowsInSpanishWithTheSpendInDollarsOfTheLocale() throws {
    let personal = providers(try golden().quotas)[0].accounts[0]
    #expect(personal.lines.map(\.title) == ["5 h", "Semanal", "Por modelo", "Opus weekly", "Uso extra"])
    #expect(personal.lines[0].value == "42 %" && personal.lines[1].value == "62 %" && personal.lines[0].reset == "Se restablece en 3h 00m")
    #expect(personal.lines[4].value == "$12,40 de $50,00 al mes")
}

@Test func theExtraUsageOfAnAccountSaysOnOffOrWhatIsSpent() throws {
    func extra(_ json: String) throws -> String? {
        let own = try quota(#"{"account":"x","provider":"claude","status":"ok","extraUsage":\#(json)}"#)
        return providers([own])[0].accounts[0].lines.first { $0.title == "Uso extra" }?.value
    }
    #expect(try extra(#"{"isEnabled":false}"#) == "Desactivado")
    #expect(try extra(#"{"isEnabled":true}"#) == "Activado")
    #expect(try extra(#"{"isEnabled":true,"usedCreditsUsd":3}"#) == "$3,00")
    #expect(try extra(#"{"isEnabled":true,"monthlyLimitUsd":1234.5}"#) == "de $1234,50 al mes")
}

@Test func codexDrawerSaysItsLimitsCreditsAndResetCreditsInSpanish() throws {
    let codex = providers(try golden().quotas)[1].accounts[0]
    #expect(codex.lines.map(\.title) == ["5 h", "Semanal", "Otros límites", "Spark 5h", "Créditos", "Créditos de restablecimiento"])
    // the credits' balance is the provider's own number; the reset credits are a plural
    #expect(codex.lines[4].value == "12.50" && codex.lines[5].value == "1 disponible")
    func credits(_ json: String, reset: Int = 2) throws -> [String?] {
        let own = try quota(#"{"account":"x","provider":"codex","status":"ok","credits":\#(json),"rateLimitResetCredits":{"availableCount":\#(reset)}}"#)
        return providers([own])[0].accounts[0].lines.map(\.value)
    }
    #expect(try credits(#"{"unlimited":true}"#) == ["Ilimitados", "2 disponibles"])
    #expect(try credits(#"{"hasCredits":true}"#) == ["Disponibles", "2 disponibles"])
    #expect(try credits(#"{"hasCredits":false}"#, reset: 1) == ["Ninguno", "1 disponible"])
}

@Test func theDrawerOfAnotherModelSaysItsHeadingInSpanish() throws {
    let own = try quota(#"{"account":"x","provider":"claude","status":"ok","windows":[{"id":"o","label":"Opus","group":"model_scoped","usedPercent":10}]}"#)
    #expect(providers([own])[0].accounts[0].lines.filter(\.heading).map(\.title) == ["Por modelo"])
}

@Test func theLocalServersAndTheirModelsAreToldInSpanish() throws {
    let lines = providers(try golden().quotas)[3].accounts[0].lines
    #expect(lines.map(\.title) == ["LM Studio", "Ollama", "$0 de cómputo local"])
    #expect(lines[0].value == "Detenido" && lines[1].value == "Listo" && lines.map(\.ready) == [false, true, false])
    #expect(lines[1].detail == "localhost:11434 · Cargados: qwen3:8b, llama3.2:3b")
    let idle = try quota(#"{"account":"local","provider":"local","status":"ok","servers":[{"kind":"ollama","running":true}]}"#)
    #expect(providers([idle])[0].accounts[0].lines[0].detail == "localhost:11434 · Ningún modelo cargado")
    // a pool of local servers with no name of its own is named in Spanish
    #expect(providers([idle])[0].accounts[0].title == "Servidores locales")
}

// MARK: the cards

@Test func theFourCardsSayWhatWasSpentAndWhatIsMissingInSpanish() throws {
    let kpis = usageKpis(try golden(), bundle: b, locale: l)
    #expect(kpis.map(\.title) == ["Costo est. de API", "Tokens totales", "Cómputo local", "Epics / chats activos"])
    #expect(kpis[0].value == "$46,82" && kpis[0].footnote == "1 modelo sin precio no se cuenta" && kpis[0].warns)
    #expect(kpis[1].value == "24,9M" && kpis[1].footnote == "318 turnos")
    #expect(kpis[2].value == "$0,00" && kpis[2].footnote == "8 turnos locales")
    #expect(kpis[3].value == "1 / 1" && kpis[3].footnote == "Repos y carpetas con trabajo" && kpis[3].warns == false)
}

@Test func theCardsOfAnEmptyHistoryAndOfASingleTurnUseTheOneOfEachPlural() throws {
    let empty = usageKpis(try decode(#"{"summary":{}}"#), bundle: b, locale: l)
    #expect(empty[0].footnote == nil && empty[0].warns == false && empty[2].footnote == "No se usó ningún modelo local" && empty[3].value == "—")
    let single = usageKpis(try decode(#"{"summary":{"turns":1},"byModel":[{"model":"m","isLocal":true,"turns":1}]}"#), bundle: b, locale: l)
    #expect(single[1].footnote == "1 turno" && single[2].footnote == "1 turno local")
    let unpriced = #"{"summary":{},"byModel":[{"model":"a","costStatus":"unpriced"},{"model":"b","costStatus":"unpriced"}]}"#
    #expect(usageKpis(try decode(unpriced), bundle: b, locale: l)[0].footnote == "2 modelos sin precio no se cuentan")
}

@Test func countsAndMoneyFollowTheLocaleOfTheLanguage() {
    #expect([0, 999, 1_000, 1_840_000, 21_400_000, 3_200_000_000].map { usageCount($0, bundle: b, locale: l) } == ["0", "999", "1K", "1,8M", "21,4M", "3,2B"])
    #expect(usageMoney(0, locale: l) == "$0,00" && usageMoney(0.001, locale: l) == "<$0,01" && usageMoney(1234.5, locale: l) == "$1.234,50")
    #expect(usageGrouped(1_234_567, locale: l) == "1.234.567")
}

// MARK: the chart's tooltip and the tables

@Test func theTooltipOfADaySaysEachProviderAndTheTotalWithTheCommaOfTheLocale() throws {
    let snapshot = try golden()
    let cost = usageTooltip(usageBars(snapshot, metric: .cost, locale: l)[0], metric: .cost, bundle: b, locale: l)
    #expect(cost.lines.map(\.provider) == ["Claude", "Codex", "Antigravity"] && cost.lines.map(\.providerId) == ["claude", "codex", "agy"])
    #expect(cost.total == "$3,10" && cost.lines[1].value == "$0,93")
    #expect(cost.title == "7 nov" && cost.weekday == "sábado")
    #expect(usageBars(snapshot, metric: .cost, locale: l).map(\.label).prefix(2) == ["7 nov", "8 nov"])
    let tokens = usageTooltip(usageBars(snapshot, metric: .tokens, locale: l)[6], metric: .tokens, bundle: b, locale: l)
    #expect(tokens.lines.map(\.provider) == ["Claude", "Codex", "Antigravity", "Local"] && tokens.total == "3,6M")
}

@Test func theModelTableSaysTokensAndCostInSpanish() throws {
    let rows = usageModelRows(try golden(), bundle: b, locale: l)
    #expect(rows[0].detail == "900K ent. · 12,6M caché · 380K sal." && rows[0].cost == "$31,20")
    #expect(rows[2].cost == nil && rows[4].cost == "$0,00 · Local" && rows[4].provider == "Local")
}

@Test func theModelTableTotalsTheRangeAndSaysWhatIsLeftOutWithTheOneOfEachPlural() throws {
    #expect(usageModelTotal(try golden(), bundle: b, locale: l).model == "Total · 5 modelos, 1 sin precio no contado")
    let two = #"{"summary":{},"byModel":[{"model":"a","costStatus":"unpriced"},{"model":"b","costStatus":"unpriced"},{"model":"c"}]}"#
    #expect(usageModelTotal(try decode(two), bundle: b, locale: l).model == "Total · 3 modelos, 2 sin precio no contados")
    let one = usageModelTotal(try decode(#"{"summary":{},"byModel":[{"model":"a"}]}"#), bundle: b, locale: l)
    #expect(one.model == "Total · 1 modelo")
    #expect(usageModelTotal(try golden(), bundle: b, locale: l).cost == "$46,82")
}

@Test func theWorkspaceTableSaysItsSourcesAndTurnsInSpanishAndKeepsTheHostsSourceForTheSymbol() throws {
    let rows = usageWorkspaceRows(try golden(), bundle: b, locale: l)
    #expect(rows.map(\.source) == ["Epic", "Chat", "Externo"] && rows.map(\.sourceKind) == ["epic", "chat", "external"])
    #expect(rows[0].detail == "15M tokens · 190 turnos" && rows[0].cost == "$28,40")
    let odd = try decode(#"{"summary":{},"byWorkspace":[{"workspace":"","source":"newcomer","turns":1}]}"#)
    let row = usageWorkspaceRows(odd, bundle: b, locale: l)[0]
    #expect(row.name == "Desconocido" && row.source == "Newcomer" && row.detail == "0 tokens · 1 turno")
}

@Test func theWorkspaceTableTotalsTheWholeRangeInSpanish() throws {
    let snapshot = try golden()
    #expect(usageWorkspaceTotal(snapshot, bundle: b, locale: l).name == "Total · 3 espacios de trabajo")
    #expect(usageWorkspaceTotal(snapshot, limit: 2, bundle: b, locale: l).name == "Total · 3 espacios de trabajo, los 2 con más tokens")
    let one = try decode(#"{"summary":{"turns":1},"byWorkspace":[{"workspace":"a/b","source":"epic"}]}"#)
    let total = usageWorkspaceTotal(one, bundle: b, locale: l)
    #expect(total.name == "Total · 1 espacio de trabajo" && total.detail == "0 tokens · 1 turno")
}

// MARK: the price form

private let catalog = ["claude-opus-4-5", "gpt-5-codex"]

@Test func theChecksOfThePriceFormSayWhatIsWrongInSpanish() {
    var draft = UsageOverrideDraft(mode: .alias)
    #expect(draft.check(model: "m", catalog: catalog, bundle: b, locale: l).errors == [.alias: "Elige un modelo"])
    draft.alias = "gpt-6"
    #expect(draft.check(model: "m", catalog: catalog, bundle: b, locale: l).errors == [.alias: "No es un modelo de la tabla de precios"])
    draft = UsageOverrideDraft(mode: .custom)
    #expect(draft.check(model: "m", catalog: catalog, bundle: b, locale: l).errors == [.input: "Obligatorio", .output: "Obligatorio"])
    draft.input = "-1"
    draft.output = "abc"
    draft.cacheWrite = "20000"
    let bad = draft.check(model: "m", catalog: catalog, bundle: b, locale: l)
    #expect(bad.errors == [.input: "No puede ser negativo", .output: "Escribe un número, como 1.25", .cacheWrite: "Como máximo 10.000"])
}

@MainActor @Test func aHostWithoutOverridesIsNotAskedAndSaysWhatToDoInSpanish() async throws {
    let host = try host()
    host.capabilitiesAnswer = [.usage]
    let refusal = await UsageStore(host: host).override(UsageOverride(model: "m", action: .local), bundle: b, locale: l)
    #expect(refusal == "El host de chat que se está ejecutando es más antiguo que esta app y no tiene Uso. Reinicia el host de chat (cuando ninguna sesión esté trabajando) para usarlo.")
}

// MARK: the ring beside the microphone

private func usage(five: Double? = nil, weekly: Double? = nil, monthly: Double? = nil, stale: Bool = false) -> AccountUsage {
    AccountUsage(five: five.map { MeterShape(hatched: $0) }, weekly: weekly.map { MeterShape(hatched: $0) }, monthly: monthly.map { MeterShape(hatched: $0) }, reset: nil, stale: stale)
}

@Test func theRingInWordsIsSpanishWithTheNameOfTheWindowItShows() {
    func words(_ context: ContextUse?, _ usage: AccountUsage?) -> String { contextRingWords(context: context, usage: usage, bundle: b, locale: l) }
    let context = ContextUse(tokens: 46_800, window: 200_000)
    #expect(words(context, usage(five: 0.42)) == "Contexto 23 % · 5 h 42 %")
    #expect(words(context, usage(weekly: 0.63)) == "Contexto 23 % · Semanal 63 %")
    #expect(words(nil, usage(monthly: 0.1)) == "Mensual 10 %")
    #expect(words(context, nil) == "Contexto 23 %")
    #expect(words(nil, nil) == "Contexto y límites de uso" && words(ContextUse(tokens: 5), nil) == "Contexto y límites de uso")
}

@Test func whatTheColorAndTheDimmingOfTheRingSayIsSaidInSpanishToo() {
    func words(_ context: ContextUse?, _ usage: AccountUsage?) -> String { contextRingWords(context: context, usage: usage, bundle: b, locale: l) }
    let near = ContextUse(tokens: 186_000, window: 200_000)
    #expect(words(near, usage(five: 0.94)) == "Contexto 93 %, cerca del límite · 5 h 94 %, cerca del límite")
    #expect(words(ContextUse(tokens: 90, window: 100), nil) == "Contexto 90 %, cerca del límite")
    #expect(words(ContextUse(tokens: 89, window: 100), nil) == "Contexto 89 %")
    #expect(words(nil, usage(five: 0.28, stale: true)) == "5 h 28 % · últimos límites conocidos")
}

@Test func theMetersOfThePopoverSayWhyTheyAreMissingInSpanish() throws {
    let quotas = try golden().quotas
    func why(_ account: String, quotas: [UsageQuota] = quotas, failed: Bool = false, checking: Bool = false) -> String {
        contextLimitsWords(account: account, quotas: quotas, failed: failed, checking: checking, bundle: b, locale: l)
    }
    #expect(why("claude-work") == "Work no tiene la sesión iniciada.")
    // a signed-out account with no display name is named by its account
    let bare = try quota(#"{"account":"claude-x","provider":"claude","status":"signed_out"}"#)
    #expect(why("claude-x", quotas: [bare]) == "claude-x no tiene la sesión iniciada.")
    #expect(why("local") == "No hay límites que mostrar para esta cuenta.")
    #expect(why("nobody", failed: true) == "No se pudieron leer los límites. Abre Uso para ver por qué.")
    #expect(why("nobody", checking: true) == "Comprobando los límites…")
    #expect(why("nobody") == "No hay límites que mostrar para esta cuenta.")
}

// MARK: the words the views call straight from Copy

@Test func everyUsageKeyWithNoArgumentIsInTheSpanishCatalogWithItsSpanishWords() throws {
    let file = testPaths().root.appendingPathComponent("design/copy/es.json")
    let words = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: String])
    let plain = words.filter { key, value in key.hasPrefix("usage") && value.contains("{") == false }
    #expect(plain.count > 70)
    for (key, value) in plain {
        #expect(b.localizedString(forKey: key, value: "missing", table: nil) == value, Comment(rawValue: key))
    }
}

@Test func theWordsWithArgumentsTheUsageViewsCallAreSpanish() {
    #expect(Copy.usageMetricName(metric: .cost, bundle: b, locale: l) == "Costo" && Copy.usageMetricName(metric: .tokens, bundle: b, locale: l) == "Tokens")
    #expect(Copy.usageChartTitle(metric: .cost, bundle: b, locale: l) == "Costo diario estimado de API")
    #expect(Copy.usageChartTitle(metric: .tokens, bundle: b, locale: l) == "Tokens por día")
    #expect(Copy.usageChartLabel(metric: .cost, bundle: b, locale: l) == "Costo diario por proveedor")
    #expect(Copy.usageChartLabel(metric: .tokens, bundle: b, locale: l) == "Tokens por día y proveedor")
    #expect(Copy.usageChartSegment(day: "Nov 7", provider: "Codex", bundle: b, locale: l) == "Nov 7, Codex")
    #expect(Copy.usageChartDayNoUse(day: "Nov 10", bundle: b, locale: l) == "Nov 10, sin uso")
    #expect(Copy.usageRangeDays(days: 30, bundle: b, locale: l) == "30 d")
    #expect(Copy.usageNoMatchLine(days: 7, bundle: b, locale: l) == "Quítalos para ver todos los últimos 7 días.")
    #expect(Copy.usageNoUsageTitle(days: 90, bundle: b, locale: l) == "Sin uso en los últimos 90 días")
    #expect(Copy.usageUnpricedLabel(model: "my-model", bundle: b, locale: l) == "Sin precio. Asigna un precio a my-model")
    #expect(Copy.usageCustomLabel(model: "my-model", bundle: b, locale: l) == "Precio personalizado. Edita el precio de my-model")
    #expect(Copy.usageMapTitle(model: "my-model", bundle: b, locale: l) == "Precio de my-model")
    #expect(Copy.usageMapRateLabel(rate: "Entrada", bundle: b, locale: l) == "Entrada, dólares por millón de tokens")
    #expect(Copy.usageSignInFailed(account: "work", bundle: b, locale: l) == "No se pudo abrir Terminal para iniciar sesión con work.")
    #expect(Copy.usageSourceName(which: .external, bundle: b, locale: l) == "Externo" && Copy.usageSourceName(which: .chat, bundle: b, locale: l) == "Chat")
}

@Test func theMarkOfAProviderIsSaidInSpanishForEachOfItsThreeStates() {
    #expect(Copy.usageMark(which: .ok, provider: "Codex", bundle: b, locale: l) == "Codex está listo")
    #expect(Copy.usageMark(which: .warning, provider: "Codex", bundle: b, locale: l) == "Codex necesita atención")
    #expect(Copy.usageMark(which: .failure, provider: "Codex", bundle: b, locale: l) == "Codex falló")
}
