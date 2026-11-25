import Foundation
import Testing
@testable import CarrierCore

@Test(arguments: [
    (DictationSession.State.idle, DictationIcon.mic, false, true, String?.none, true, "Dictate"),
    (.gettingReady, .spinner, false, false, "Getting the model ready…", false, "Dictation is getting ready"),
    (.listening, .mic, true, true, nil, false, "Stop dictation"),
    (.transcribing, .spinner, false, false, nil, false, "Transcribing"),
    (.cleaning, .spinner, false, true, "Cleaning…", false, "Cleaning, press to skip"),
])
func theBoxDrawsAndSaysWhatEachStateNeeds(state: DictationSession.State, icon: DictationIcon, accent: Bool, pressable: Bool, caption: String?, send: Bool, label: String) throws {
    let box = try #require(dictationPresentation(state, registered: true, bundle: english.bundle, locale: english.locale))
    #expect(box.icon == icon)
    #expect(box.inAccent == accent)
    #expect(box.pressable == pressable)
    #expect(box.caption == caption)
    #expect(box.sendEnabled == send)
    #expect(box.label == label)
}

@Test func transcribingIsSaidOnlyOnceTheAnswerIsSlow() throws {
    let waiting = try #require(dictationPresentation(.transcribing, registered: true, answerIsSlow: true, bundle: english.bundle, locale: english.locale))
    #expect(waiting.caption == "Transcribing…" && waiting.icon == .spinner && waiting.pressable == false)
    #expect(try #require(dictationPresentation(.transcribing, registered: true, bundle: english.bundle, locale: english.locale)).caption == nil)
}

/// A dictation of a model that gives its text at the end, stopped, on a clock that moves when the test says so.
@MainActor private func stopped(_ clock: FakeClock, _ recognizer: ScriptedRecognizer) async -> DictationSession {
    let session = DictationSession(capture: ScriptedCapture(), sleep: { try await clock.sleep($0) })
    session.start(
        recognizer: recognizer, model: recognizer.models[0], into: DictationField(owner: "box", text: { "" }, caret: { 0 }, put: { _, _, _ in })
    )
    for _ in 0..<3000 where session.state != .listening || session.modelReady == false { try? await Task.sleep(for: .milliseconds(1)) }
    session.stop()
    return session
}

@MainActor private func caption(of session: DictationSession) -> String? {
    dictationPresentation(session.state, registered: true, answerIsSlow: session.answerIsSlow, bundle: english.bundle, locale: english.locale)?.caption
}

@MainActor @Test func aFinalTextThatTakesMoreThan250msAfterTheStopShowsTranscribing() async {
    let clock = FakeClock(), recognizer = ScriptedRecognizer(partial: .atTheEnd)
    let session = await stopped(clock, recognizer)
    #expect(session.state == .transcribing && caption(of: session) == nil)
    // the time to wait is the one the dictation names, and the 30 s the recognizer has to answer is a clock of its own
    clock.advance(past: DictationSession.quickAnswer - .milliseconds(1))
    try? await Task.sleep(for: .milliseconds(20))
    #expect(caption(of: session) == nil)
    clock.advance(past: DictationSession.quickAnswer)
    for _ in 0..<3000 where session.answerIsSlow == false { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(DictationSession.quickAnswer == .milliseconds(250))
    #expect(session.state == .transcribing && caption(of: session) == "Transcribing…")
    // the text comes at last: nothing of it is left for the next dictation
    recognizer.say(.final("hola"))
    recognizer.finish()
    for _ in 0..<3000 where session.state != .idle { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(session.state == .idle && session.answerIsSlow == false)
}

@MainActor @Test func aFinalTextWithin250msOfTheStopNeverShowsTranscribing() async {
    let clock = FakeClock(), recognizer = ScriptedRecognizer(partial: .atTheEnd)
    let session = await stopped(clock, recognizer)
    #expect(caption(of: session) == nil)
    recognizer.say(.final("hola"))
    recognizer.finish()
    for _ in 0..<3000 where session.state != .idle { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(session.state == .idle && session.answerIsSlow == false)
    // the clock reaching 250 ms after the end changes nothing
    clock.advance(past: .seconds(1))
    try? await Task.sleep(for: .milliseconds(20))
    #expect(session.answerIsSlow == false)
}

@Test func whileTheModelGetsReadyWithTheCaptureRunningTheBoxListensAndSaysSoWhereTheTextWillBe() throws {
    let waiting = try #require(dictationPresentation(.listening, registered: true, modelReady: false, bundle: english.bundle, locale: english.locale))
    let listening = try #require(dictationPresentation(.listening, registered: true, bundle: english.bundle, locale: english.locale))
    // what listens is drawn as listening (the line, the filled microphone) and can be stopped
    #expect(waiting.icon == listening.icon && waiting.inAccent && waiting.pressable && waiting.sendEnabled == false)
    #expect(waiting.label == "Stop dictation" && waiting.help == "Stop dictation")
    #expect(waiting.caption == "Getting the model ready…" && listening.caption == nil)
    #expect(dictationEdgeShown(waiting, dropping: false))
    // a stop while it loads leaves the spinner, which cannot be pressed
    let stopped = try #require(dictationPresentation(.gettingReady, registered: true, modelReady: false, bundle: english.bundle, locale: english.locale))
    #expect(stopped.icon == .spinner && stopped.pressable == false && stopped.caption == "Getting the model ready…")
}

@Test(arguments: [DictationSession.State.idle, .gettingReady, .listening, .transcribing, .cleaning])
func aBuildWithNoRecognizerDrawsNoIconInAnyState(state: DictationSession.State) {
    #expect(dictationPresentation(state, registered: false, bundle: english.bundle, locale: english.locale) == nil)
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
    let blocked = try #require(dictationPresentation(.idle, registered: true, microphone: .denied, bundle: english.bundle, locale: english.locale))
    #expect(blocked.icon == .micSlash && blocked.pressable && blocked.sendEnabled && blocked.caption == nil)
    #expect(blocked.label == "Dictation is blocked")
    #expect(dictationClick(.denied) == .explainBlock)
    #expect(MicrophoneBlockedPopover.button(bundle: english.bundle, locale: english.locale) == "Open System Settings")
    #expect(MicrophoneBlockedPopover.settingsURL.hasSuffix("Privacy_Microphone"))
}

@Test(arguments: [(MicrophonePermission.allowed, DictationClick.start), (.notAsked, .start), (.denied, .explainBlock)])
func theMicrophonePermissionDecidesWhatTheIconDoesAndWhatAClickOffers(permission: MicrophonePermission, click: DictationClick) throws {
    let icon = try #require(dictationPresentation(.idle, registered: true, microphone: permission, bundle: english.bundle, locale: english.locale)).icon
    #expect(icon == (permission == .denied ? .micSlash : .mic))
    #expect(dictationClick(permission) == click)
}

@Test func theMicrophoneOnlyBlocksWhileTheBoxIsIdle() throws {
    // a dictation that is already running keeps its own states
    #expect(try #require(dictationPresentation(.listening, registered: true, microphone: .denied, bundle: english.bundle, locale: english.locale)).icon == .mic)
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

@Test func aCopiedTextSaysWhyItWasNotPastedAndWhyItWasNotCleaned() {
    let reason = PasteReason.noPermission
    #expect(dictationKeptNotices(reason: reason, notCleaned: nil, bundle: english.bundle, locale: english.locale) == ["\(reason.explanation(bundle: english.bundle, locale: english.locale)) It is on the clipboard."])
    #expect(dictationKeptNotices(reason: reason, notCleaned: "the model did not answer in time", bundle: english.bundle, locale: english.locale).last == "It was not cleaned: the model did not answer in time")
}

@Test(arguments: [DictationWidgetState.working, .listening, .cleaning, .pasted, .pastedRaw, .cancelled])
func withTheLiveTextOffTheBoxIsTheSameWidthWithTheTimeAndTheKeysAndNoLinesOfText(state: DictationWidgetState) {
    for style in [DictationWidgetStyle.small, .medium, .large] {
        let on = dictationWidgetLook(state, style: style).box!
        let off = dictationWidgetLook(state, style: style, livePreview: false).box!
        #expect(on.showsText && off.showsText == false)
        #expect(off.width == on.width && off.text == on.text)
        // the foot row alone: the box's padding and the row, as high as the box with its lines minus them
        #expect(off.height(textSize: off.text) == 52)
    }
    #expect(dictationWidgetLook(state, style: .pill, livePreview: false).box == nil)
}

@Test(arguments: [DictationWidgetState.failed, .copied])
func aFailureAndACopiedTextKeepTheirTextWithTheLiveTextOff(state: DictationWidgetState) {
    #expect(dictationWidgetLook(state, style: .medium, livePreview: false) == dictationWidgetLook(state, style: .medium))
    let pill = dictationWidgetLook(state, style: .pill, livePreview: false)
    #expect(pill.box?.showsText == true && pill.opensAsSmall)
}

@Test func aDarkThemeDrawsItsTextInTheDarkAppearanceAndTheDefaultAndTheClearGlassFollowTheSystem() {
    #expect(DictationWidgetTheme.accent.appearance == nil && DictationWidgetTheme.clear.appearance == nil)
    for theme in [DictationWidgetTheme.black, .glassDark, .glow] { #expect(theme.appearance == .dark) }
    #expect(Set(DictationWidgetTheme.allCases.map { $0.title(bundle: english.bundle, locale: english.locale) }).count == DictationWidgetTheme.allCases.count)
}

@Test func aSpotIsKeptAsTextAndOnlyAReadableOneIsKept() {
    let spot = DictationWidgetSpot(x: 0.25, fromTop: true, gap: 80)
    #expect(spot?.text == "0.25,top,80.0")
    #expect(spot.flatMap { DictationWidgetSpot(text: $0.text) } == spot)
    for bad in ["", "0.5", "0.5,left,10", "1.5,top,10", "-0.1,top,10", "0.5,top,-1", "nan,top,1", "0.5,top,inf", "a,top,1", "0.5,top,10,1"] { #expect(DictationWidgetSpot(text: bad) == nil) }
}

@Test func aWidgetLeftNearTheBottomHangsFromTheBottomAndOneNearTheTopFromTheTop() {
    let area = CGRect(x: 100, y: 50, width: 1000, height: 800)
    let low = DictationWidgetSpot(frame: CGRect(x: 300, y: 120, width: 400, height: 90), in: area)
    #expect(low.fromTop == false && low.gap == 70 && low.x == 0.4)
    let high = DictationWidgetSpot(frame: CGRect(x: 300, y: 700, width: 400, height: 90), in: area)
    #expect(high.fromTop && high.gap == 60)
}

@Test func theBoxOpensWhereItWasLeftWhateverItsSizeAndGrowsAwayFromItsEdge() {
    let area = CGRect(x: 100, y: 50, width: 1000, height: 800)
    let low = DictationWidgetSpot(x: 0.5, fromTop: false, gap: 70)!
    let high = DictationWidgetSpot(x: 0.5, fromTop: true, gap: 60)!
    // the Pill, then a taller box in the same place: the bottom stays for the first and the top for the second
    let pill = CGSize(width: 76, height: 38), box = CGSize(width: 420, height: 120)
    #expect(dictationWidgetOrigin(size: pill, in: area, position: .bottom, spot: low) == CGPoint(x: 600 - 38, y: 120))
    #expect(dictationWidgetOrigin(size: box, in: area, position: .bottom, spot: low) == CGPoint(x: 600 - 210, y: 120))
    #expect(dictationWidgetOrigin(size: pill, in: area, position: .bottom, spot: high).y == CGFloat(752))
    #expect(dictationWidgetOrigin(size: box, in: area, position: .bottom, spot: high).y == CGFloat(670))
}

@Test func aSpotFromAnotherDisplayIsPutBackInsideTheOneThatLeavesLess() {
    let small = CGRect(x: 0, y: 0, width: 800, height: 500)
    let size = CGSize(width: 420, height: 120)
    let edge = DictationWidgetSpot(x: 1, fromTop: true, gap: 900)!
    let origin = dictationWidgetOrigin(size: size, in: small, position: .top, spot: edge)
    #expect(origin == CGPoint(x: 380, y: 0))
    // no spot is the place chosen, as before
    #expect(dictationWidgetOrigin(size: size, in: small, position: .top) == CGPoint(x: 190, y: 500 - 120 - 24))
}
