import Foundation
import Testing
@testable import CarrierCore

/// The widget's machine over the real session, a scripted recognizer and capture, and what it asked the outside to do.
@MainActor private final class Widget {
    let capture: ScriptedCapture
    let recognizer: ScriptedRecognizer
    let logged = Logged()
    private(set) var effects: [GlobalDictationEffect] = []
    private(set) var moments: [GlobalDictationMoment] = []
    private(set) var recorded: [DictationEntry] = []
    var frontApp: String? = "Notes"
    var machine: GlobalDictation!
    var microphone = MicrophonePermission.allowed
    var decision = PasteDecision.paste
    var hasModel = true
    var activation = DictationActivation.toggle

    init(recognizer: ScriptedRecognizer = ScriptedRecognizer(atAudioEnd: [.final("")]), capture: ScriptedCapture = ScriptedCapture()) {
        self.capture = capture
        self.recognizer = recognizer
        let logged = logged
        let session = DictationSession(capture: capture, log: { logged.causes.append($0.cause) })
        machine = GlobalDictation(
            session: session, speechModel: { [unowned self] in hasModel ? (recognizer, recognizer.models[0]) : nil }, microphone: { [unowned self] in microphone },
            decision: { [unowned self] in decision }, activation: { [unowned self] in activation },
            moment: { [unowned self] in moments.append($0) }, record: { [unowned self] in recorded.append($0) }, frontApp: { [unowned self] in frontApp },
            perform: { [unowned self] in effects.append($0) })
    }

    var session: DictationSession { machine.session }

    func until(_ what: String = #function, _ condition: () -> Bool) async {
        for _ in 0..<3000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("never happened: \(what)")
    }

    /// Presses the shortcut and waits until it listens.
    func listen() async {
        machine.handle(.down)
        await until { session.state == .listening }
    }
}

private final class Logged: @unchecked Sendable { var causes: [String] = [] }

@MainActor @Test func theShortcutOpensTheWidgetAndTheNextPressPastesTheTextOnceAndClosesIt() async {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola mundo")]))
    await widget.listen()
    #expect(widget.machine.state == .running && widget.effects == [.show])
    widget.recognizer.say(.partial("hola"))
    await widget.until { widget.machine.text == "hola" }
    widget.machine.handle(.down)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .paste("hola mundo"), .close])
    #expect(widget.capture.isRunning == false && widget.session.state == .idle)
    #expect(widget.logged.causes.isEmpty)
}

@MainActor @Test func theKeyComingUpDoesNothingInAToggle() async {
    let widget = Widget()
    await widget.listen()
    widget.machine.handle(.up)
    #expect(widget.machine.state == .running && widget.session.state == .listening && widget.effects == [.show])
    widget.machine.handle(.up)
    widget.machine.handle(.escape)
    widget.machine.handle(.up)
    #expect(widget.effects == [.show, .close])
}

@MainActor @Test func escapeWhileListeningPastesNothingAndClosesTheWidget() async {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola")]))
    await widget.listen()
    widget.recognizer.say(.partial("hola"))
    await widget.until { widget.machine.text == "hola" }
    widget.machine.handle(.escape)
    #expect(widget.machine.state == .idle && widget.session.state == .idle && widget.capture.isRunning == false)
    #expect(widget.effects == [.show, .close])
}

@MainActor @Test func escapeWhileGettingReadyCancelsTheStartAndClosesTheWidget() async {
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    let widget = Widget(recognizer: recognizer)
    widget.machine.handle(.down)
    #expect(widget.session.state == .gettingReady)
    widget.machine.handle(.escape)
    recognizer.releasePrepare()
    #expect(widget.machine.state == .idle && widget.session.state == .idle && widget.effects == [.show, .close])
    #expect(widget.capture.startCount == 0)
}

@MainActor @Test func escapeWhileTranscribingDropsTheTextAndClosesTheWidget() async {
    // a model that gives its text only at the end: after the second press it is transcribing
    let widget = Widget(recognizer: ScriptedRecognizer(partial: .atTheEnd))
    await widget.listen()
    widget.machine.handle(.down)
    #expect(widget.session.state == .transcribing)
    widget.machine.handle(.down)
    widget.machine.handle(.escape)
    #expect(widget.machine.state == .idle && widget.session.state == .idle && widget.effects == [.show, .close])
}

@MainActor @Test func escapeWithNoDictationDoesNothing() {
    let widget = Widget()
    widget.machine.handle(.escape)
    #expect(widget.machine.state == .idle && widget.effects.isEmpty)
}

@MainActor @Test func pressingTheShortcutAgainWhileGettingReadyEndsItWithNothingPasted() async {
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    let widget = Widget(recognizer: recognizer)
    widget.machine.handle(.down)
    widget.machine.handle(.down)
    recognizer.releasePrepare()
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .close] && widget.capture.startCount == 0)
}

@MainActor @Test(arguments: ["", "  \n "]) func aDictationWithNoWordsPastesNothingAndClosesQuietly(heard: String) async {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final(heard)]))
    await widget.listen()
    widget.machine.handle(.down)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .close])
    #expect(widget.logged.causes.isEmpty)
}

@MainActor @Test func aFailureToRecognizeShowsItsCauseInTheWidgetAndIsLoggedUntilEscapeClosesIt() async {
    let widget = Widget()
    await widget.listen()
    widget.recognizer.say(.partial("hola"))
    widget.recognizer.say(.failed(DictationFailure("The model broke")))
    await widget.until { widget.machine.state == .failed("The model broke") }
    #expect(widget.effects == [.show] && widget.logged.causes == ["The model broke"])
    widget.machine.handle(.escape)
    #expect(widget.machine.state == .idle && widget.effects == [.show, .close])
}

@MainActor @Test func aFailureToStartTheMicrophoneIsShownLoggedAndTheShortcutClosesIt() async {
    let widget = Widget(capture: ScriptedCapture(startError: DictationFailure("The microphone could not start")))
    widget.machine.handle(.down)
    await widget.until { widget.machine.state == .failed("The microphone could not start") }
    #expect(widget.effects == [.show] && widget.logged.causes == ["The microphone could not start"])
    widget.machine.handle(.down)
    #expect(widget.machine.state == .idle && widget.effects == [.show, .close])
}

@MainActor @Test func aBlockedMicrophoneAndNoSpeechModelAreFailuresToStartToo() {
    let blocked = Widget()
    blocked.microphone = .denied
    blocked.machine.handle(.down)
    guard case .failed(let cause) = blocked.machine.state else {
        Issue.record("not failed")
        return
    }
    #expect(cause.contains("microphone") && blocked.logged.causes == [cause] && blocked.session.state == .idle)

    let none = Widget()
    none.hasModel = false
    none.machine.handle(.down)
    #expect(none.machine.state == .failed("No speech model is available") && none.logged.causes == ["No speech model is available"])
}

@MainActor @Test(arguments: [PasteReason.noField, .noPermission, .secureField])
func aTextThatCannotBePastedIsCopiedAndStaysInTheWidgetWithItsReason(reason: PasteReason) async {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final(" hola mundo ")]))
    widget.decision = .copyOnly(reason)
    await widget.listen()
    widget.machine.handle(.down)
    await widget.until { widget.machine.state != .running }
    #expect(widget.effects == [.show, .copy("hola mundo")])
    #expect(widget.machine.state == .copied(reason) && widget.machine.text == "hola mundo")
    #expect(widget.logged.causes.isEmpty)
}

@MainActor @Test func aTextThatCanBePastedIsPastedOnceAndTheWidgetCloses() async {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola")]))
    widget.decision = .paste
    await widget.listen()
    widget.machine.handle(.down)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .paste("hola"), .close])
}

@MainActor private func keptWidget(_ reason: PasteReason = .noField) async -> Widget {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola")]))
    widget.decision = .copyOnly(reason)
    await widget.listen()
    widget.machine.handle(.down)
    await widget.until { widget.machine.state != .running }
    return widget
}

@MainActor @Test func copyPutsTheTextOnTheClipboardAgainAndDismissAndEscapeCloseTheWidget() async {
    let widget = await keptWidget()
    widget.machine.copyAgain()
    #expect(widget.effects == [.show, .copy("hola"), .copy("hola")] && widget.machine.state == .copied(.noField))
    widget.machine.dismissCopied()
    #expect(widget.machine.state == .idle && widget.effects.last == .close)

    let escaped = await keptWidget()
    escaped.machine.handle(.escape)
    #expect(escaped.machine.state == .idle && escaped.effects == [.show, .copy("hola"), .close])
}

@MainActor @Test func copyAndDismissDoNothingWhenNothingWasKept() {
    let widget = Widget()
    widget.machine.copyAgain()
    widget.machine.dismissCopied()
    #expect(widget.effects.isEmpty && widget.machine.state == .idle)
}

@MainActor @Test func aNewDictationClosesTheWidgetThatWasLeftOpenAndStarts() async {
    let widget = await keptWidget(.secureField)
    widget.decision = .paste
    widget.machine.handle(.down)
    await widget.until { widget.session.state == .listening }
    #expect(widget.effects == [.show, .copy("hola"), .close, .show])
    #expect(widget.machine.state == .running && widget.machine.text.isEmpty)
}

@MainActor @Test func theEndOfAMessageBoxDictationIsNotTheWidgetsOwn() async {
    let widget = Widget()
    var box = ""
    widget.session.start(
        recognizer: widget.recognizer, model: widget.recognizer.models[0],
        into: DictationField(owner: "box", text: { box }, caret: { box.utf16.count }, put: { text, _, _ in box = text })
    )
    await widget.until { widget.session.state == .listening }
    // the shortcut stops the box's dictation, and the widget's starts when it is idle
    widget.machine.handle(.down)
    await widget.until { widget.session.owner == GlobalDictation.owner && widget.session.state == .listening }
    #expect(widget.machine.state == .running && widget.effects == [.show])
}

@Test func theTimeIsWrittenAsMinutesAndSeconds() {
    #expect(dictationClock(0) == "0:00" && dictationClock(7.9) == "0:07" && dictationClock(75) == "1:15" && dictationClock(-3) == "0:00")
}

@Test func aWindowBelongsToTheDisplayItOverlapsTheMost() {
    let left = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let right = CGRect(x: 1000, y: 0, width: 1000, height: 800)
    #expect(displayIndex(of: CGRect(x: 100, y: 100, width: 300, height: 300), in: [left, right]) == 0)
    #expect(displayIndex(of: CGRect(x: 900, y: 100, width: 400, height: 300), in: [left, right]) == 1)
    #expect(displayIndex(of: CGRect(x: 5000, y: 0, width: 10, height: 10), in: [left, right]) == nil)
    #expect(displayIndex(of: left, in: []) == nil)
}

@MainActor @Test func theMachineTellsWhenItBeginsToListenAndWhenThePersonStopsIt() async {
    let widget = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola")]))
    widget.machine.handle(.down)
    #expect(widget.moments.isEmpty)
    await widget.until { widget.session.state == .listening }
    #expect(widget.moments == [.listening])
    widget.machine.handle(.down)
    widget.machine.handle(.down)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.moments == [.listening, .stopped])
}

@MainActor @Test func aCancelIsTold() async {
    let widget = Widget()
    await widget.listen()
    widget.machine.handle(.escape)
    #expect(widget.moments == [.listening, .cancelled])
}

@MainActor @Test func aDictationThatNeverListenedTellsNothing() async {
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    let widget = Widget(recognizer: recognizer)
    widget.machine.handle(.down)
    widget.machine.handle(.escape)
    recognizer.releasePrepare()
    widget.microphone = .denied
    widget.machine.handle(.down)
    #expect(widget.moments.isEmpty)
}

@MainActor @Test func aPastedDictationIsRecordedWithTheAppItWentToAndACopiedOneAsWidgetOnly() async {
    let pasted = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola mundo")]))
    await pasted.listen()
    pasted.machine.handle(.down)
    await pasted.until { pasted.machine.state == .idle }
    #expect(pasted.recorded.map(\.text) == ["hola mundo"] && pasted.recorded.map(\.outcome) == [.pasted] && pasted.recorded.map(\.destination) == ["Notes"])
    #expect(pasted.recorded.first?.model == "Scripted" && pasted.recorded.first?.words == 2)
    let copied = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola")]))
    copied.decision = .copyOnly(.noField)
    await copied.listen()
    copied.machine.handle(.down)
    await copied.until { copied.machine.state == .copied(.noField) }
    #expect(copied.recorded.map(\.outcome) == [.copied] && copied.recorded.map(\.destination) == [DictationEntry.widgetOnly])
}

@MainActor @Test func aCancelledAndAFailedDictationAreRecordedWithWhatWasHeardAndAnEmptyOneIsNot() async {
    let cancelled = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("hola")]))
    await cancelled.listen()
    cancelled.recognizer.say(.partial("hola"))
    await cancelled.until { cancelled.machine.text == "hola" }
    cancelled.machine.handle(.escape)
    #expect(cancelled.recorded.map(\.outcome) == [.cancelled] && cancelled.recorded.map(\.text) == ["hola"] && cancelled.recorded.map(\.destination) == [DictationEntry.widgetOnly])
    let failed = Widget()
    await failed.listen()
    failed.recognizer.say(.final("uno dos"))
    await failed.until { failed.machine.text == "uno dos" }
    failed.recognizer.say(.failed(DictationFailure("The model broke")))
    await failed.until { failed.machine.state == .failed("The model broke") }
    #expect(failed.recorded.map(\.outcome) == [.failed] && failed.recorded.map(\.text) == ["uno dos"])
    let empty = Widget()
    await empty.listen()
    empty.machine.handle(.escape)
    let silent = Widget(recognizer: ScriptedRecognizer(atAudioEnd: [.final("")]))
    await silent.listen()
    silent.machine.handle(.down)
    await silent.until { silent.machine.state == .idle }
    let noMicrophone = Widget(capture: ScriptedCapture(startError: DictationFailure("The microphone could not start")))
    noMicrophone.machine.handle(.down)
    await noMicrophone.until { noMicrophone.machine.state == .failed("The microphone could not start") }
    // a cancel with nothing heard is told with no words, and so is a failure to start, which the history leaves out (`DictationRecords`); an empty stop never tells
    #expect(empty.recorded.map(\.words) == [0])
    #expect(silent.recorded.isEmpty)
    #expect(noMicrophone.recorded.map(\.words) == [0])
}

/// A hold: the widget over a recognizer that gives `heard` when the audio ends, with the key already down and listening.
@MainActor private func holdWidget(_ recognizer: ScriptedRecognizer = ScriptedRecognizer(atAudioEnd: [.final("hola mundo")])) -> Widget {
    let widget = Widget(recognizer: recognizer)
    widget.activation = .hold
    return widget
}

@MainActor @Test func inAHoldThePressStartsAndTheReleaseEndsAndPastesOnce() async {
    let widget = holdWidget()
    await widget.listen()
    widget.recognizer.say(.partial("hola"))
    await widget.until { widget.machine.text == "hola" }
    widget.machine.handle(.up)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .paste("hola mundo"), .close] && widget.moments == [.listening, .stopped])
    #expect(widget.capture.isRunning == false && widget.logged.causes.isEmpty)
}

@MainActor @Test func aHoldShorterThanTheFirstTextStillPastesWhatTheRecognizerGivesAtTheEnd() async {
    let widget = holdWidget()
    await widget.listen()
    // released before any partial text arrived
    #expect(widget.machine.text.isEmpty)
    widget.machine.handle(.up)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .paste("hola mundo"), .close])
}

@MainActor @Test func aHoldReleasedRightAfterThePressWithNoWordsPastesNothingAndClosesQuietly() async {
    let widget = holdWidget(ScriptedRecognizer(atAudioEnd: [.final("")]))
    await widget.listen()
    widget.machine.handle(.up)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .close] && widget.logged.causes.isEmpty)
}

@MainActor @Test func aHoldReleasedWhileTheModelIsGettingReadyEndsWithNothingPasted() async {
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    let widget = holdWidget(recognizer)
    widget.machine.handle(.down)
    #expect(widget.session.state == .gettingReady)
    widget.machine.handle(.up)
    recognizer.releasePrepare()
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .close] && widget.capture.startCount == 0 && widget.moments.isEmpty)
}

@MainActor @Test func escapeWhileTheKeysAreHeldCancelsAndTheReleaseAfterItDoesNothing() async {
    let widget = holdWidget()
    await widget.listen()
    widget.machine.handle(.escape)
    widget.machine.handle(.up)
    #expect(widget.machine.state == .idle && widget.session.state == .idle && widget.capture.isRunning == false)
    #expect(widget.effects == [.show, .close] && widget.moments == [.listening, .cancelled])
}

@MainActor @Test func aSecondReleaseIsNoSecondEnd() async {
    let recognizer = ScriptedRecognizer(partial: .atTheEnd, atAudioEnd: [.final("hola")])
    let widget = holdWidget(recognizer)
    await widget.listen()
    widget.machine.handle(.up)
    widget.machine.handle(.up)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.moments == [.listening, .stopped] && widget.effects == [.show, .paste("hola"), .close])
}

@MainActor @Test func aHoldWhoseTextCannotBePastedStaysOpenAndTheReleaseThatFollowsChangesNothing() async {
    let widget = holdWidget()
    widget.decision = .copyOnly(.noField)
    await widget.listen()
    widget.machine.handle(.up)
    await widget.until { widget.machine.state != .running }
    widget.machine.handle(.up)
    #expect(widget.machine.state == .copied(.noField) && widget.effects == [.show, .copy("hola mundo")])
}

@MainActor @Test func aFailureInAHoldLeavesTheWidgetUpUntilTheNextPress() async {
    let widget = holdWidget()
    widget.microphone = .denied
    widget.machine.handle(.down)
    widget.machine.handle(.up)
    guard case .failed = widget.machine.state else {
        Issue.record("not failed")
        return
    }
    widget.machine.handle(.down)
    widget.machine.handle(.up)
    #expect(widget.machine.state == .idle && widget.effects == [.show, .close])
}

@MainActor @Test func theActivationIsReadWhenTheDictationStartsSoChangingItUnderWayChangesNothing() async {
    let widget = holdWidget()
    await widget.listen()
    widget.activation = .toggle
    widget.machine.handle(.up)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .paste("hola mundo"), .close])

    // and a toggle that is switched to hold under way is still ended by the second press
    let toggle = Widget()
    await toggle.listen()
    toggle.activation = .hold
    toggle.machine.handle(.up)
    #expect(toggle.machine.state == .running)
    toggle.machine.handle(.down)
    await toggle.until { toggle.machine.state == .idle }
}

@MainActor @Test func aPressInAHoldOnAWidgetLeftOpenStartsANewDictationThatTheReleaseEnds() async {
    let widget = holdWidget()
    widget.decision = .copyOnly(.noField)
    await widget.listen()
    widget.machine.handle(.up)
    await widget.until { widget.machine.state != .running }
    widget.decision = .paste
    await widget.listen()
    widget.machine.handle(.up)
    await widget.until { widget.machine.state == .idle }
    #expect(widget.effects == [.show, .copy("hola mundo"), .close, .show, .paste("hola mundo"), .close])
}
