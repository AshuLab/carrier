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
        for _ in 0..<2000 where controller.session.state != wanted { try? await Task.sleep(for: .milliseconds(1)) }
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
    for _ in 0..<2000 where dictation.session.state != .listening { try? await Task.sleep(for: .milliseconds(1)) }
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
    for _ in 0..<2000 where dictation.session.state != .listening { try? await Task.sleep(for: .milliseconds(1)) }
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
    for _ in 0..<2000 where dictation.session.state != .listening { try? await Task.sleep(for: .milliseconds(1)) }
    dictation.toggle(into: field("b"))
    dictation.stop(ownedBy: "b")
    dictation.stop(ownedBy: "a")
    for _ in 0..<2000 where dictation.session.state != .idle { try? await Task.sleep(for: .milliseconds(1)) }
    try? await Task.sleep(for: .milliseconds(30))
    #expect(dictation.session.state == .idle && capture.startCount == 1)
}
