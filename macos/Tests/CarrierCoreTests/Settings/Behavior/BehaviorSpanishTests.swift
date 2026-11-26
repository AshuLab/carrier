import Foundation
import Testing

@testable import CarrierCore

// The Behavior page in Spanish (design/copy/es.json): its three groups with the title, description and unit of each row, and what the engine would refuse in
// each value. The English words are asserted in BehaviorPageTests and EngineConfigTests, with `english`.

private let b = spanish.bundle
private let l = spanish.locale

@Test func theBehaviorPageSaysItsGroupsRowsAndUnitsInSpanish() {
    let groups = behaviorGroups(bundle: b, locale: l)
    #expect(groups.map(\.title) == ["Ritmo", "Cuando algo sale mal", "Mantenimiento"])
    let rows = groups.flatMap(\.rows)
    #expect(rows.map(\.title) == [
        "Buscar epics listos cada", "Epics a la vez", "Rondas de revisión antes de consultarte", "Rondas del revisor líder antes de consultarte", "Reintentos tras un fallo técnico",
        "Tiempo por ejecución del agente", "Mostrar los epics terminados durante", "Tiempo límite de las llamadas a GitHub", "Nivel de registro",
    ])
    #expect(rows[0].detail == "En minutos" && rows[2].detail == "Una ronda cuenta una vez, tenga los revisores que tenga. Después el epic espera a una persona (needs-human)" && rows[6].detail == "De 1 a 30 días")
    #expect(rows[3].detail == "El revisor líder y el autor, un intercambio cada vez. Después el epic espera a una persona (needs-human)")
    #expect(rows.map(\.unit) == ["min", nil, nil, nil, nil, "h", "días", "s", nil])
}

@Test func theKeysOfTheRowsAndTheAnchorsOfTheGroupsDoNotChangeWithTheLanguage() {
    #expect(behaviorGroups(bundle: b, locale: l).map(\.id) == behaviorGroups(bundle: english.bundle, locale: english.locale).map(\.id))
    #expect(behaviorGroups(bundle: b, locale: l).flatMap(\.rows).map(\.key) == behaviorGroups(bundle: english.bundle, locale: english.locale).flatMap(\.rows).map(\.key))
}

@Test func whatTheEngineWouldRefuseInEachValueIsSaidInSpanish() {
    var config = EngineConfig()
    config.pollIntervalMinutes = 0
    config.logLevel = "loud"
    config.maxConcurrentEpics = 0
    config.maxLeadRounds = 0
    config.maxExecutionRetries = -1
    config.maxExecutionHours = 0
    config.githubCallTimeoutSeconds = 0
    config.finishedWindowDays = 31
    let problems = config.problems(bundle: b, locale: l)
    #expect(problems["pollIntervalMinutes"] == "Debe ser mayor que 0")
    #expect(problems["logLevel"] == "Debe ser uno de debug, info, warn, error")
    #expect(problems["maxConcurrentEpics"] == "Debe ser 1 o más")
    #expect(problems["maxLeadRounds"] == "Debe ser 1 o más")
    #expect(problems["maxExecutionRetries"] == "Debe ser 0 o más")
    #expect(problems["maxExecutionHours"] == "Debe ser 1 o más, o sin límite")
    #expect(problems["githubCallTimeoutSeconds"] == "Debe ser 1 o más")
    #expect(problems["finishedWindowDays"] == "Debe ser un número entero de 1 a 30")
}

@Test func theLimitWordsOfTheRunTimeAreSpanish() {
    #expect(Copy.behaviorLimit(bundle: b, locale: l) == "Con límite" && Copy.behaviorUnlimited(bundle: b, locale: l) == "Sin límite")
    #expect(Copy.behaviorMustBeNumber(bundle: b, locale: l) == "Debe ser un número")
}
