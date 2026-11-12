import Foundation
import Testing
@testable import CarrierCore

private func model(_ name: String, languages: Set<String>, detects: Bool) -> SpeechModel {
    SpeechModel(
        id: name, recognizer: .apple, name: name, bytes: nil, languages: languages, detectsLanguage: detects, partial: .native,
        licence: "None", card: URL(string: "https://github.com/AshuLab/carrier")!
    )
}

private let parakeet = model("Parakeet", languages: ["de", "en", "es"], detects: true)
private let nemotronEnglish = model("Nemotron EN", languages: ["en"], detects: false)
private let apple = model("Apple", languages: ["en", "es", "fr"], detects: false)

private struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let model: SpeechModel
    let macOS: [String]
    let saved: String?
    let offered: [String]
    let selected: String

    var testDescription: String { name }
}

@Test(arguments: [
    Case(name: "a model that detects the language offers Automatic first and starts on it", model: parakeet, macOS: ["es-AR", "en-US"], saved: nil,
         offered: [automaticLanguage, "es", "en", "de"], selected: automaticLanguage),
    Case(name: "a model that detects keeps a saved language it offers", model: parakeet, macOS: ["es-AR"], saved: "de",
         offered: [automaticLanguage, "es", "de", "en"], selected: "de"),
    Case(name: "a model that detects goes back to Automatic when the saved language is not on offer", model: parakeet, macOS: ["es-AR"], saved: "ja",
         offered: [automaticLanguage, "es", "de", "en"], selected: automaticLanguage),
    Case(name: "an English-only model offers English alone, whatever macOS speaks", model: nemotronEnglish, macOS: ["es-AR"], saved: nil,
         offered: ["en"], selected: "en"),
    Case(name: "an English-only model drops a saved language it does not understand", model: nemotronEnglish, macOS: ["es-AR"], saved: "es",
         offered: ["en"], selected: "en"),
    Case(name: "Apple's has no Automatic and starts on the first language of macOS that it supports", model: apple, macOS: ["ja-JP", "es-AR", "en-US"], saved: nil,
         offered: ["es", "en", "fr"], selected: "es"),
    Case(name: "Apple's with no supported language of macOS starts on the first it offers", model: apple, macOS: ["ja-JP"], saved: nil,
         offered: ["en", "es", "fr"], selected: "en"),
    Case(name: "Apple's keeps a saved language it offers", model: apple, macOS: ["es-AR"], saved: "fr",
         offered: ["es", "en", "fr"], selected: "fr"),
    Case(name: "Apple's falls back to the first it offers when the saved language is not on offer", model: apple, macOS: ["es-AR"], saved: automaticLanguage,
         offered: ["es", "en", "fr"], selected: "es"),
])
private func theLanguagePageOffersAFunctionOfTheModelMacOSAndTheSavedChoice(c: Case) {
    let choices = languageChoices(for: c.model, macOSLanguages: c.macOS, saved: c.saved)
    #expect(choices.offered == c.offered)
    #expect(choices.selected == c.selected)
}

@Test func theLineUnderLanguageSaysWhyAutomaticIsNotThereOnlyWhereItIsMissingAndALanguageIsPickable() {
    #expect(languageChoices(for: apple, macOSLanguages: [], saved: nil).hint.contains("one language"))
    #expect(languageChoices(for: nemotronEnglish, macOSLanguages: [], saved: nil).hint == "This model only understands English")
    #expect(languageChoices(for: parakeet, macOSLanguages: [], saved: nil).hint.contains("mix Spanish and English"))
}

@Test func theSwitchDimsEveryRowButItselfAndReset() {
    let rows: [DictationRow] = [.enabledSwitch, .speechModel, .language, .microphone, .reset]
    #expect(rows.filter { dictationRowIsLive($0, enabled: false) } == [.enabledSwitch, .reset])
    #expect(rows.allSatisfy { dictationRowIsLive($0, enabled: true) })
}
