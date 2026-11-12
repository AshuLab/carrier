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
