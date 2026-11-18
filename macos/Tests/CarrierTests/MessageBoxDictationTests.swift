import AppKit
import CarrierCore
import SwiftUI
import Testing
@testable import Carrier

/// A controller whose session is in `state`, driven with the scripted ports; nil `state` is a build with no recognizer, and `failing` one
/// whose dictation failed to start.
@MainActor private func controller(in state: DictationSession.State?, failing: Bool = false) async -> DictationController {
    let registry = RecognizerRegistry()
    let controller = DictationController(registry: registry, capture: ScriptedCapture())
    guard let state else { return controller }
    let recognizer = ScriptedRecognizer(partial: state == .transcribing ? .atTheEnd : .native, prepareError: failing ? DictationFailure("No input device") : nil)
    registry.register(recognizer)
    let field = DictationField(owner: "box", text: { "" }, caret: { 0 }, put: { _, _, _ in })
    func reach(_ wanted: DictationSession.State) async {
        for _ in 0..<2000 where controller.session.state != wanted || (wanted == .listening && controller.session.modelReady == false) { try? await Task.sleep(for: .milliseconds(1)) }
    }
    if state == .idle && failing == false { return controller }
    if state == .gettingReady { recognizer.holdPrepare() }
    controller.toggle(into: field)
    await reach(failing ? .idle : state == .transcribing ? .listening : state)
    if state == .transcribing {
        controller.toggle(into: field)
        await reach(.transcribing)
    }
    return controller
}

@MainActor @Test(arguments: [
    DictationSession.State.idle, .gettingReady, .listening, .transcribing,
])
func theMessageBoxBuildsInEveryStateOfADictationAtWideAndNarrowWidths(state: DictationSession.State) async throws {
    let dictation = await controller(in: state)
    #expect(dictation.session.state == state)
    for width in [320.0, 700.0] {
        let box = MessageBox(
            text: .constant("uno dos"), placeholder: "Message the agent", canSend: true, canSendWithText: true, focus: .constant(false),
            dictationOwner: "box", dictation: dictation, send: {}
        ) { Text("Claude Code · Sonnet") }
        let renderer = ImageRenderer(content: box.frame(width: width))
        #expect(renderer.cgImage != nil, "\(state) at \(width)")
    }
}

@MainActor @Test func aFailureToStartShowsItsCauseUnderTheBoxAndAnotherBoxShowsNothing() async throws {
    let dictation = await controller(in: .idle, failing: true)
    #expect(dictation.session.failure(for: "box")?.cause == "No input device")
    #expect(dictation.session.failure(for: "another")?.cause == nil)
    let box = MessageBox(
        text: .constant(""), placeholder: "Message the agent", canSend: false, canSendWithText: true, focus: .constant(false),
        dictationOwner: "box", dictation: dictation, send: {}
    ) { Text("Claude Code") }
    #expect(ImageRenderer(content: box.frame(width: 320)).cgImage != nil)
}

/// What the box is told to draw as partial text is the tentative tail only (`CommandTextViewTests` checks how it draws it).
@MainActor @Test func theBoxIsToldToDrawOnlyTheTentativeWordsAsPartialText() async {
    let registry = RecognizerRegistry()
    let dictation = DictationController(registry: registry, capture: ScriptedCapture())
    let recognizer = ScriptedRecognizer()
    registry.register(recognizer)
    var text = "", tentative: Range<Int>?
    let field = DictationField(owner: "box", text: { text }, caret: { text.utf16.count }, put: { text = $0; tentative = $2 })
    func until(_ condition: () -> Bool) async { for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) } }
    dictation.toggle(into: field)
    await until { dictation.session.state == .listening && dictation.session.modelReady }
    recognizer.say(.partial(firm: "hola ", tentative: "mun"))
    await until { text == "hola mun" }
    #expect(tentative == 5..<8)
    recognizer.say(.partial(firm: "hola mundo", tentative: ""))
    await until { text == "hola mundo" && tentative == nil }
    #expect(text == "hola mundo" && tentative == nil)
    recognizer.finish()
    await until { dictation.session.state == .idle }
}

@MainActor @Test func aBuildWithNoRecognizerRegisteredDrawsNoMicrophone() async {
    let dictation = await controller(in: nil)
    #expect(dictation.presentation(for: "box") == nil)
}

@MainActor @Test func onlyTheBoxThatDictatesDrawsTheStateOfTheDictation() async {
    let dictation = await controller(in: .listening)
    #expect(dictation.presentation(for: "box")?.label == "Stop dictation")
    #expect(dictation.presentation(for: "another")?.label == "Dictate")
}

@MainActor @Test func aTypedKeyOrLeavingStopsOnlyTheDictationOfThatBoxAndAClickInAnotherBoxStopsItToo() async {
    let registry = RecognizerRegistry()
    let dictation = DictationController(registry: registry, capture: ScriptedCapture())
    registry.register(ScriptedRecognizer(atAudioEnd: [.final("")]))
    func field(_ owner: String) -> DictationField { DictationField(owner: owner, text: { "" }, caret: { 0 }, put: { _, _, _ in }) }
    func until(_ condition: () -> Bool) async { for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) } }
    dictation.toggle(into: field("box"))
    await until { dictation.session.state == .listening }
    dictation.stop(ownedBy: "another")
    #expect(dictation.session.state == .listening)
    dictation.toggle(into: field("another"))
    await until { dictation.session.owner == "another" && dictation.session.state == .listening }
    #expect(dictation.session.owner == "another" && dictation.session.state == .listening)
    dictation.stop(ownedBy: "another")
    await until { dictation.session.state == .idle }
    #expect(dictation.session.state == .idle)
}

@MainActor private func microphone(_ status: MicrophonePermission, answer: Bool = true, asked: @escaping () -> Void = {}) -> DictationController {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer())
    var current = status
    let access = MicrophoneAccess(
        status: { current },
        request: {
            asked()
            current = answer ? .allowed : .denied
            return answer
        }
    )
    return DictationController(registry: registry, capture: ScriptedCapture(), microphone: access)
}

private let boxField = DictationField(owner: "box", text: { "" }, caret: { 0 }, put: { _, _, _ in })

@MainActor @Test func aBlockedMicrophoneDrawsTheSlashAndAClickExplainsInsteadOfListening() async {
    let dictation = microphone(.denied)
    #expect(dictation.presentation(for: "box")?.icon == .micSlash)
    #expect(dictation.toggle(into: boxField) == .explainBlock)
    try? await Task.sleep(for: .milliseconds(50))
    #expect(dictation.session.state == .idle)
}

@MainActor @Test func theFirstClickAsksForTheMicrophoneAndListensWhenItIsAllowed() async {
    var asked = 0
    let dictation = microphone(.notAsked) { asked += 1 }
    #expect(dictation.presentation(for: "box")?.icon == .mic)
    #expect(dictation.toggle(into: boxField) == .start)
    for _ in 0..<2000 where dictation.session.state != .listening || dictation.session.modelReady == false { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(asked == 1 && dictation.session.state == .listening && dictation.microphone == .allowed)
}

@MainActor @Test func aMicrophoneThatTheFirstClickDeniesTurnsTheIconToTheSlashAndNeverListens() async {
    let dictation = microphone(.notAsked, answer: false)
    dictation.toggle(into: boxField)
    for _ in 0..<2000 where dictation.microphone != .denied { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(dictation.presentation(for: "box")?.icon == .micSlash && dictation.session.state == .idle)
}

@MainActor @Test func aClickWithNoSpeechModelShowsWhyInsteadOfDoingNothing() {
    let dictation = DictationController(registry: RecognizerRegistry(), capture: ScriptedCapture())
    #expect(dictation.model == nil)
    dictation.toggle(into: boxField)
    #expect(dictation.session.failure(for: "box")?.cause == "No speech model is available")
    #expect(dictation.session.state == .idle)
}

/// A microphone whose prompt stays open until `open` is called, and how many times it was asked.
@MainActor private final class Prompt {
    var asked = 0
    let (gate, open) = AsyncStream<Void>.makeStream()
}

@MainActor @Test func aSecondClickWhileMacOSAsksForTheMicrophoneDoesNotAskAgain() async {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer())
    let prompt = Prompt()
    var current = MicrophonePermission.notAsked
    let capture = ScriptedCapture()
    let access = MicrophoneAccess(
        status: { current },
        request: {
            prompt.asked += 1
            for await _ in prompt.gate {}
            current = .allowed
            return true
        }
    )
    let dictation = DictationController(registry: registry, capture: capture, microphone: access)
    dictation.toggle(into: boxField)
    dictation.toggle(into: boxField)
    try? await Task.sleep(for: .milliseconds(20))
    prompt.open.finish()
    for _ in 0..<2000 where dictation.session.state != .listening || dictation.session.modelReady == false { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(prompt.asked == 1 && dictation.session.state == .listening && capture.startCount == 1)
}

@MainActor @Test func aBoxThatLeavesWhileMacOSAsksForTheMicrophoneNeverStartsItsDictation() async {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer())
    let prompt = Prompt()
    var current = MicrophonePermission.notAsked
    let capture = ScriptedCapture()
    let access = MicrophoneAccess(
        status: { current },
        request: {
            for await _ in prompt.gate {}
            current = .allowed
            return true
        }
    )
    let dictation = DictationController(registry: registry, capture: capture, microphone: access)
    dictation.toggle(into: boxField)
    dictation.stop(ownedBy: "box")
    prompt.open.finish()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(dictation.session.state == .idle && capture.startCount == 0)
}

@MainActor @Test func aBoxThatLeavesDropsItsDictationThatWaitsForAnotherBoxToEnd() async {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer(atAudioEnd: [.final("")]))
    let capture = ScriptedCapture()
    let dictation = DictationController(registry: registry, capture: capture)
    func field(_ owner: String) -> DictationField { DictationField(owner: owner, text: { "" }, caret: { 0 }, put: { _, _, _ in }) }
    dictation.toggle(into: field("a"))
    for _ in 0..<2000 where dictation.session.state != .listening || dictation.session.modelReady == false { try? await Task.sleep(for: .milliseconds(1)) }
    dictation.toggle(into: field("b"))
    dictation.stop(ownedBy: "b")
    dictation.stop(ownedBy: "a")
    for _ in 0..<2000 where dictation.session.state != .idle { try? await Task.sleep(for: .milliseconds(1)) }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(dictation.session.state == .idle && capture.startCount == 1)
}

/// The box in a window, so the shortcut's request (`dictateRequest`) reaches it as the conversation passes it on.
@MainActor private final class ShortcutBox {
    let dictation: DictationController
    /// Whether the box was asked to take the caret; the text view may give it back at once, since this window is not the key one.
    private(set) var focused = false
    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private let window: NSWindow

    init(dictation: DictationController) {
        _ = NSApplication.shared
        self.dictation = dictation
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        show(request: 0)
    }

    func show(request: Int) {
        host.rootView = AnyView(
            MessageBox(
                text: .constant(""), placeholder: "", canSend: false, canSendWithText: true,
                focus: Binding(get: { false }, set: { if $0 { self.focused = true } }),
                dictationOwner: "box", dictation: dictation, dictateRequest: request, send: {}
            ) { Text("Claude Code") }.frame(width: 600))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        host.layoutSubtreeIfNeeded()
    }
}

@MainActor @Test func theShortcutFocusesTheBoxAndStartsItsDictationAndTheShortcutAgainEndsIt() async {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer(atAudioEnd: [.final("")]))
    let dictation = DictationController(registry: registry, capture: ScriptedCapture())
    let box = ShortcutBox(dictation: dictation)
    func until(_ condition: () -> Bool) async { for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) } }
    #expect(dictation.session.state == .idle && box.focused == false)
    box.show(request: 1)
    await until { dictation.session.state == .listening }
    #expect(dictation.session.owner == "box" && dictation.session.state == .listening && box.focused)
    box.show(request: 2)
    await until { dictation.session.state == .idle }
    #expect(dictation.session.state == .idle)
}

@MainActor @Test func theShortcutDoesNothingInABoxWhileDictationIsOff() async {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer(atAudioEnd: [.final("")]))
    let defaults = UserDefaults(suiteName: "route-\(UUID().uuidString)")!
    let dictation = DictationController(registry: registry, capture: ScriptedCapture(), preferences: AppPreferences(defaults: defaults))
    dictation.setEnabled(false)
    let box = ShortcutBox(dictation: dictation)
    box.show(request: 1)
    try? await Task.sleep(for: .milliseconds(100))
    #expect(dictation.session.state == .idle)
}

/// A model server that answers at once, so no test reaches a real one.
private struct CleaningClient: TextModelClient {
    func models(of server: CleanupServer) async throws -> [String] { ["m"] }
    func complete(server: CleanupServer, model: String, system: String, text: String, timeout: Duration) async throws -> String { "Hola." }
}

/// A box that dictates "um hola" with Cleanup `on` or off, over a defaults of its own, and the text it ends with.
@MainActor private func dictated(cleanup on: Bool) async -> String {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer(atAudioEnd: [.final("um hola")]))
    let preferences = AppPreferences(defaults: UserDefaults(suiteName: "cleanup-\(UUID().uuidString)")!)
    preferences.dictationCleanupServer = .ollama
    preferences.dictationCleanupModel = "m"
    preferences.dictationCleanupEnabled = on
    let dictation = DictationController(registry: registry, capture: ScriptedCapture(), preferences: preferences, cleanupClient: CleaningClient())
    var text = ""
    let field = DictationField(owner: "box", text: { text }, caret: { text.utf16.count }, put: { written, _, _ in text = written })
    func until(_ condition: () -> Bool) async { for _ in 0..<2000 where condition() == false { try? await Task.sleep(for: .milliseconds(1)) } }
    dictation.toggle(into: field)
    await until { dictation.session.state == .listening && dictation.session.modelReady }
    dictation.toggle(into: field)
    await until { dictation.session.state == .idle }
    return text
}

@MainActor @Test func aBoxDictationIsCleanedWithCleanupOnAndEndsAsBeforeWithItOff() async {
    #expect(await dictated(cleanup: true) == "Hola.")
    #expect(await dictated(cleanup: false) == "um hola")
}

@MainActor @Test func theReleaseOfAHoldEndsADictationStillGettingReady() async {
    let registry = RecognizerRegistry()
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    registry.register(recognizer)
    let dictation = DictationController(registry: registry, capture: ScriptedCapture())
    dictation.toggle(into: boxField)
    #expect(dictation.session.state == .gettingReady)
    dictation.endHold()
    #expect(dictation.session.state == .idle)
}

@MainActor @Test func theReleaseOfAHoldWhileMacOSAsksForTheMicrophoneNeverStartsTheDictation() async {
    let registry = RecognizerRegistry()
    registry.register(ScriptedRecognizer())
    let prompt = Prompt()
    var current = MicrophonePermission.notAsked
    let capture = ScriptedCapture()
    let access = MicrophoneAccess(
        status: { current },
        request: {
            for await _ in prompt.gate {}
            current = .allowed
            return true
        }
    )
    let dictation = DictationController(registry: registry, capture: capture, microphone: access)
    dictation.toggle(into: boxField)
    dictation.endHold()
    prompt.open.finish()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(dictation.session.state == .idle && capture.startCount == 0)
}
