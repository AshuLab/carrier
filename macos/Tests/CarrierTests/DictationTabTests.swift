import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

private final class Asked: @unchecked Sendable { var times = 0 }

/// A controller over a scripted recognizer, a capture and a defaults of its own, and the box it writes into.
@MainActor private final class Rig {
    let recognizer = ScriptedRecognizer()
    let asked = Asked()
    let preferences = AppPreferences(defaults: UserDefaults(suiteName: "dictation-tab-\(UUID().uuidString)")!)
    let dictation: DictationController
    var text = ""

    init() {
        let registry = RecognizerRegistry()
        registry.register(recognizer)
        let asked = asked
        let access = MicrophoneAccess(status: { .allowed }, request: { asked.times += 1; return true })
        dictation = DictationController(registry: registry, capture: ScriptedCapture(), microphone: access, preferences: preferences)
    }

    var field: DictationField {
        DictationField(owner: "box", text: { self.text }, caret: { self.text.count }, put: { text, _, _ in self.text = text })
    }

    func until(_ condition: () -> Bool) async { for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) } }
}

@MainActor @Test func turningDictationOffWhileItListensStopsItKeepsItsTextAndTakesTheMicrophoneOutOfTheBox() async {
    let rig = Rig()
    rig.dictation.toggle(into: rig.field)
    await rig.until { rig.dictation.session.state == .listening }
    rig.recognizer.say(.partial("hola"))
    await rig.until { rig.text == "hola" }
    rig.dictation.setEnabled(false)
    rig.recognizer.finish()
    await rig.until { rig.dictation.session.state == .idle }
    #expect(rig.dictation.session.state == .idle && rig.text == "hola")
    #expect(rig.preferences.dictationEnabled == false)
    // in every box at once: the new-session one and the open conversation's draw nothing
    #expect(rig.dictation.presentation(for: "new-session") == nil && rig.dictation.presentation(for: "session:1") == nil)
}

@MainActor @Test func withDictationOffAClickAsksMacOSForNothingAndNeverListens() async {
    let rig = Rig()
    rig.dictation.setEnabled(false)
    rig.dictation.toggle(into: rig.field)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(rig.asked.times == 0 && rig.dictation.session.state == .idle)
    rig.dictation.setEnabled(true)
    #expect(rig.dictation.presentation(for: "box")?.label == "Dictate")
}

@MainActor @Test func resetPutsThePageBackToOnApplesModelAndTheLanguageOfMacOS() {
    let rig = Rig()
    rig.dictation.setEnabled(false)
    rig.dictation.choose(model: rig.recognizer.models[0])
    rig.dictation.choose(language: "fr")
    rig.dictation.reset()
    #expect(rig.dictation.enabled && rig.preferences.dictationEnabled)
    #expect(rig.preferences.dictationModelID == nil && rig.preferences.dictationLanguage == nil)
}

@MainActor @Test(arguments: [true, false])
func theDictationPageBuildsWithTheSwitchOnAndOff(enabled: Bool) {
    let rig = Rig()
    rig.dictation.setEnabled(enabled)
    for width in [420.0, 640.0] {
        let renderer = ImageRenderer(content: DictationTabView(dictation: rig.dictation).frame(width: width))
        #expect(renderer.cgImage != nil, "\(enabled) at \(width)")
    }
}

@MainActor @Test func theModelsTableBuildsWithRowsInEveryState() {
    let models = FixtureRecognizer().models
    let states: [ModelState] = [.downloaded, .notDownloaded, .downloading(0.4), .failed("No space on the disk"), .downloaded, .notDownloaded]
    var byID: [String: ModelState] = [:]
    for (model, state) in zip(models, states) { byID[model.id] = state }
    let rows = speechModelRows(models: models, filter: nil, state: { byID[$0.id] ?? .notDownloaded }, inUse: models[0].id)
    // the five actions of a row are among them: Download, the progress, Retry, the trash and none
    #expect(Set(rows.map(\.action)).count == 5)
    for width in [760.0, 1000.0] {
        let table = SpeechModelsTable(rows: rows, choose: { _ in }, download: { _ in }, cancel: { _ in }, delete: { _ in })
        let renderer = ImageRenderer(content: table.frame(width: width))
        #expect(renderer.cgImage != nil, "at \(width)")
    }
}

@MainActor @Test func thePageBuildsOverTheFixtureListWithTheSwitchOff() {
    let registry = RecognizerRegistry()
    registry.register(FixtureRecognizer())
    let preferences = AppPreferences(defaults: UserDefaults(suiteName: "dictation-tab-\(UUID().uuidString)")!)
    let dictation = DictationController(registry: registry, preferences: preferences)
    for enabled in [true, false] {
        dictation.setEnabled(enabled)
        #expect(ImageRenderer(content: DictationTabView(dictation: dictation).frame(width: 900)).cgImage != nil)
    }
    // the popup lists what is downloaded: the canned phrase, which stands in for Apple's, and none of the entries to download
    #expect(dictation.rows(filter: nil).filter { $0.radio != nil }.map(\.name) == ["Fixture phrase"])
}

@Test func appleRecognizersModelPassesTheCatalogCheck() {
    #expect(SpeechModelCatalog.problems(in: AppleRecognizer(languages: ["en", "es"], preferredLanguages: ["es"]).models).isEmpty)
}
