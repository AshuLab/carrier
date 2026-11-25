import CarrierCore
import Foundation
import Testing
@testable import Carrier

private let english = (bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
private let spanish = (bundle: Copy.bundle("es"), locale: Locale(identifier: "es_AR"))

private func words(_ phase: CheckButton.Phase, title: String?, _ language: (bundle: Bundle, locale: Locale)) -> String {
    CheckButton.words(for: phase, title: title, bundle: language.bundle, locale: language.locale)
}

// The button takes its built-in words from copy keys and lets a screen pass its own at rest.

@Test func theCheckButtonSaysItsBuiltInWordsInEnglishAsBefore() {
    #expect(words(.idle, title: nil, english) == "Check again")
    #expect(words(.checking, title: nil, english) == "Checking…")
    #expect(words(.done, title: nil, english) == "Up to date")
    #expect(words(.failed, title: nil, english) == "Check failed")
}

@Test func theCheckButtonSaysItsBuiltInWordsInSpanish() {
    #expect(words(.idle, title: nil, spanish) == "Comprobar de nuevo")
    #expect(words(.checking, title: nil, spanish) == "Comprobando…")
    #expect(words(.done, title: nil, spanish) == "Al día")
    #expect(words(.failed, title: nil, spanish) == "Falló la comprobación")
}

@Test func aScreenThatPassesItsOwnWordShowsItAtRestAndTheOtherFacesStayTheButtons() {
    #expect(words(.idle, title: "Check now", english) == "Check now")
    #expect(words(.idle, title: "Comprobar ahora", spanish) == "Comprobar ahora")
    #expect(words(.checking, title: "Check now", english) == "Checking…")
    #expect(words(.done, title: "Comprobar ahora", spanish) == "Al día")
}
