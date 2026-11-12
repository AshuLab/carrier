import Foundation

// What the Dictation page of Settings decides, apart from its views (docs/specs/dictation-in-the-app.md): the languages it offers and the
// rows its switch dims.

/// The saved language that means "detect it as the person speaks"; every other saved language is a base code ("es").
public let automaticLanguage = "automatic"

/// "es-AR" and "es_AR" are "es".
public func baseLanguage(_ identifier: String) -> String { String(identifier.prefix { $0 != "-" && $0 != "_" }) }

/// What the Language popup offers for a model, which of it is chosen and the line that says why.
public struct LanguageChoices: Equatable, Sendable {
    public let offered: [String]
    public let selected: String
    public let hint: String
}

/// The languages a model offers: Automatic first where it detects the language, then the languages of macOS that it understands, in the
/// order of macOS, then the others by code. The chosen one is the saved one when the model offers it, and the first on offer otherwise, so
/// Apple's, which takes one language and has no Automatic, starts on the first language of macOS that it supports.
public func languageChoices(for model: SpeechModel, macOSLanguages: [String], saved: String?) -> LanguageChoices {
    var codes: [String] = []
    for code in macOSLanguages.map(baseLanguage) + model.languages.sorted() where model.languages.contains(code) && codes.contains(code) == false {
        codes.append(code)
    }
    let offered = model.detectsLanguage ? [automaticLanguage] + codes : codes
    let selected = saved.flatMap { offered.contains($0) ? $0 : nil } ?? offered.first ?? ""
    let hint: String
    if selected == automaticLanguage {
        hint = "Picks the language as you speak, so you can mix Spanish and English"
    } else if model.detectsLanguage {
        hint = "Choose Automatic to mix languages"
    } else if codes == ["en"] {
        hint = "This model only understands English"
    } else {
        hint = "\(model.name) listens in one language; pick a model that detects it to mix them"
    }
    return LanguageChoices(offered: offered, selected: selected, hint: hint)
}

/// The rows of the Dictation page that the switch affects.
public enum DictationRow: Equatable, Sendable { case enabledSwitch, speechModel, language, microphone, reset }

/// Whether a row takes clicks and is drawn in full: with Dictation off only the switch and Reset do (the models table is dimmed and Storage
/// stays live too, when those rows come).
public func dictationRowIsLive(_ row: DictationRow, enabled: Bool) -> Bool {
    enabled || row == .enabledSwitch || row == .reset
}
