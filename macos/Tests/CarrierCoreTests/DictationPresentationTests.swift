import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    (DictationSession.State.idle, DictationIcon.mic, false, true, String?.none, true, "Dictate"),
    (.gettingReady, .spinner, false, false, "Getting the model ready…", true, "Dictation is getting ready"),
    (.listening, .mic, true, true, nil, false, "Stop dictation"),
    (.transcribing, .spinner, false, false, "Transcribing…", false, "Transcribing"),
])
func theBoxDrawsAndSaysWhatEachStateNeeds(state: DictationSession.State, icon: DictationIcon, accent: Bool, pressable: Bool, caption: String?, send: Bool, label: String) throws {
    let box = try #require(dictationPresentation(state, registered: true))
    #expect(box.icon == icon)
    #expect(box.inAccent == accent)
    #expect(box.pressable == pressable)
    #expect(box.caption == caption)
    #expect(box.sendEnabled == send)
    #expect(box.label == label)
}

@Test(arguments: [DictationSession.State.idle, .gettingReady, .listening, .transcribing])
func aBuildWithNoRecognizerDrawsNoIconInAnyState(state: DictationSession.State) {
    #expect(dictationPresentation(state, registered: false) == nil)
}

@MainActor @Test func theRegistryHoldsOneRecognizerPerIdAndStartsEmpty() {
    let registry = RecognizerRegistry()
    #expect(registry.recognizers.isEmpty)
    let first = ScriptedRecognizer(id: .apple), second = ScriptedRecognizer(id: .apple)
    registry.register(first)
    registry.register(ScriptedRecognizer(id: .whisper))
    registry.register(second)
    #expect(registry.recognizers.map(\.id) == [.whisper, .apple])
    #expect(registry.recognizers.last as? ScriptedRecognizer === second)
}
