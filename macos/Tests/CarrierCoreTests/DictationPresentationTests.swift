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

@Test func aBlockedMicrophoneShowsTheSlashedIconAndAClickExplainsInsteadOfListening() throws {
    let blocked = try #require(dictationPresentation(.idle, registered: true, microphone: .denied))
    #expect(blocked.icon == .micSlash && blocked.pressable && blocked.sendEnabled && blocked.caption == nil)
    #expect(blocked.label == "Dictation is blocked")
    #expect(dictationClick(.denied) == .explainBlock)
    #expect(MicrophoneBlockedPopover.button == "Open System Settings")
    #expect(MicrophoneBlockedPopover.settingsURL.hasSuffix("Privacy_Microphone"))
}

@Test(arguments: [(MicrophonePermission.allowed, DictationClick.start), (.notAsked, .start), (.denied, .explainBlock)])
func theMicrophonePermissionDecidesWhatTheIconDoesAndWhatAClickOffers(permission: MicrophonePermission, click: DictationClick) throws {
    let icon = try #require(dictationPresentation(.idle, registered: true, microphone: permission)).icon
    #expect(icon == (permission == .denied ? .micSlash : .mic))
    #expect(dictationClick(permission) == click)
}

@Test func theMicrophoneOnlyBlocksWhileTheBoxIsIdle() throws {
    // a dictation that is already running keeps its own states
    #expect(try #require(dictationPresentation(.listening, registered: true, microphone: .denied)).icon == .mic)
}
