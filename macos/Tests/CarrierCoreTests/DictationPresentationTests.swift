import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    (DictationSession.State.idle, DictationIcon.mic, false, true, String?.none, true, "Dictate"),
    (.gettingReady, .spinner, false, false, "Getting the model ready…", false, "Dictation is getting ready"),
    (.listening, .mic, true, true, nil, false, "Stop dictation"),
    (.transcribing, .spinner, false, false, "Transcribing…", false, "Transcribing"),
    (.cleaning, .spinner, false, true, "Cleaning…", false, "Cleaning, press to skip"),
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

@Test func whileTheModelGetsReadyWithTheCaptureRunningTheBoxListensAndSaysSoWhereTheTextWillBe() throws {
    let waiting = try #require(dictationPresentation(.listening, registered: true, modelReady: false))
    let listening = try #require(dictationPresentation(.listening, registered: true))
    // what listens is drawn as listening (the line, the filled microphone) and can be stopped
    #expect(waiting.icon == listening.icon && waiting.inAccent && waiting.pressable && waiting.sendEnabled == false)
    #expect(waiting.label == "Stop dictation" && waiting.help == "Stop dictation")
    #expect(waiting.caption == "Getting the model ready…" && listening.caption == nil)
    #expect(dictationEdgeShown(waiting, dropping: false))
    // a stop while it loads leaves the spinner, which cannot be pressed
    let stopped = try #require(dictationPresentation(.gettingReady, registered: true, modelReady: false))
    #expect(stopped.icon == .spinner && stopped.pressable == false && stopped.caption == "Getting the model ready…")
}

@Test(arguments: [DictationSession.State.idle, .gettingReady, .listening, .transcribing, .cleaning])
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

@Test(arguments: [(DictationWidgetStyle.small, 2, 340.0, 12.0), (.medium, 3, 420, 14), (.large, 4, 540, 17)])
func theBoxStylesAreTwoThreeAndFourLinesAtTheirWidthsAndTextSizes(style: DictationWidgetStyle, lines: Int, width: Double, text: Double) throws {
    let box = try #require(dictationWidgetLook(.listening, style: style).box)
    #expect(box == DictationWidgetBox(lines: lines, width: width, text: text))
    #expect(box.height(textSize: text) > CGFloat(lines) * text)
}

@Test func theBoxIsTallerTheMoreLinesItHoldsAndThePillHasNoBoxAndNoText() {
    let heights = [DictationWidgetStyle.small, .medium, .large].compactMap { $0.box.map { $0.height(textSize: $0.text) } }
    #expect(heights == heights.sorted() && Set(heights).count == 3)
    #expect(DictationWidgetStyle.pill.box == nil && dictationWidgetLook(.listening, style: .pill).box == nil)
}

@Test(arguments: [
    (DictationWidgetState.working, DictationWidgetIcon.spinner), (.listening, .mic), (.cleaning, .sparkle), (.pasted, .check), (.pastedRaw, .warning),
    (.cancelled, .xmark),
])
func thePillsIconFollowsTheState(state: DictationWidgetState, icon: DictationWidgetIcon) {
    let look = dictationWidgetLook(state, style: .pill)
    #expect(look.icon == icon && look.box == nil && look.opensAsSmall == false)
}

@Test(arguments: [DictationWidgetStyle.small, .medium, .large])
func aTextStartsAtTheTopAndOnlyFadesOnceItIsLongerThanTheBox(style: DictationWidgetStyle) throws {
    let lines = try #require(style.box).lines
    #expect(dictationTextFit(textLines: 0, boxLines: lines) == DictationTextFit(visibleLines: 0, fadesTop: false))
    #expect(dictationTextFit(textLines: 1, boxLines: lines) == DictationTextFit(visibleLines: 1, fadesTop: false))
    #expect(dictationTextFit(textLines: lines, boxLines: lines) == DictationTextFit(visibleLines: lines, fadesTop: false))
    #expect(dictationTextFit(textLines: lines + 3, boxLines: lines) == DictationTextFit(visibleLines: lines, fadesTop: true))
}

@Test(arguments: [DictationWidgetState.failed, .copied])
func theStatesThatNeedTextOrAButtonOpenThePillAsTheSmallBoxAndKeepTheChosenBox(state: DictationWidgetState) throws {
    // a text that was only copied has room for its reason over the text; a failure keeps the style's own lines
    func lines(_ style: DictationWidgetStyle) throws -> Int { try #require(style.box).lines + (state == .copied ? DictationWidgetBox.reasonLines : 0) }
    let pill = dictationWidgetLook(state, style: .pill)
    #expect(pill.box?.lines == (try lines(.small)) && pill.box?.width == DictationWidgetStyle.small.box?.width && pill.opensAsSmall && pill.icon == nil && pill.fades == false)
    let large = dictationWidgetLook(state, style: .large)
    #expect(large.box?.lines == (try lines(.large)) && large.box?.width == DictationWidgetStyle.large.box?.width && large.opensAsSmall == false)
}

@Test func aCopiedTextHasRoomForItsReasonAndTheTextStillHasItsStyleLines() throws {
    for style in [DictationWidgetStyle.small, .medium, .large] {
        let copied = try #require(dictationWidgetLook(.copied, style: style).box)
        let box = try #require(style.box)
        let extra = copied.height(textSize: copied.text) - box.height(textSize: box.text)
        #expect(abs(extra - CGFloat(DictationWidgetBox.reasonLines) * box.lineHeight(textSize: box.text)) < 1)
    }
}

@Test func onlyPastedPastedRawAndCancelledFadeAndThePastedRawOneStaysLongerForItsCause() {
    let all: [DictationWidgetState] = [.working, .listening, .cleaning, .failed, .copied, .pasted, .pastedRaw, .cancelled]
    #expect(all.filter { dictationWidgetLook($0, style: .medium).fades } == [.pasted, .pastedRaw, .cancelled])
    #expect(dictationWidgetLook(.pastedRaw, style: .pill).linger > dictationWidgetLook(.pasted, style: .pill).linger)
}

@Test(arguments: [DictationWidgetState.cleaning, .pastedRaw])
func cleaningAndThePastedWithoutCleaningNeedNoTextOrButtonSoThePillStaysAPill(state: DictationWidgetState) {
    let pill = dictationWidgetLook(state, style: .pill)
    #expect(pill.box == nil && pill.opensAsSmall == false)
    #expect(dictationWidgetLook(state, style: .large).box == DictationWidgetStyle.large.box)
}

@Test(arguments: [(DictationWidgetPosition.top, 748.0), (.bottom, 124.0)])
func theWidgetIsCentredUnderTheMenuBarOrAboveTheDockOfTheVisibleFrame(position: DictationWidgetPosition, y: Double) {
    // a second display to the right and above, with the Dock taking 100 points at the bottom and the menu bar 38 at the top
    let area = CGRect(x: 1440, y: 100, width: 1920, height: 762)
    let origin = dictationWidgetOrigin(size: CGSize(width: 420, height: 90), in: area, position: position)
    #expect(origin.x == 1440 + 960 - 210 && origin.y == y)
}
