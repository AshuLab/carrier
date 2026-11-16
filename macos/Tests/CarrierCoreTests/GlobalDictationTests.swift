import Foundation
import Testing
@testable import CarrierCore

/// The widget's machine over the real session, a scripted recognizer and capture, and what it asked the outside to do.
@MainActor private final class Widget {
    let capture: ScriptedCapture
    let recognizer: ScriptedRecognizer
    let logged = Logged()
    private(set) var effects: [GlobalDictationEffect] = []
    var machine: GlobalDictation!
    var microphone = MicrophonePermission.allowed
    var decision = PasteDecision.paste
    var hasModel = true

    init(recognizer: ScriptedRecognizer = ScriptedRecognizer(atAudioEnd: [.final("")]), capture: ScriptedCapture = ScriptedCapture()) {
        self.capture = capture
        self.recognizer = recognizer
        let logged = logged
        let session = DictationSession(capture: capture, log: { logged.causes.append($0.cause) })
        machine = GlobalDictation(
            session: session, speechModel: { [unowned self] in hasModel ? (recognizer, recognizer.models[0]) : nil }, microphone: { [unowned self] in microphone },
            decision: { [unowned self] in decision }, perform: { [unowned self] in effects.append($0) })
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
