import Foundation
import Testing
@testable import CarrierCore

/// A clock that moves only when a test says so: `sleep` waits for `advance`.
@MainActor private final class FakeClock {
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]

    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { waiting[id] = $0 }
        } onCancel: {
            Task { @MainActor in self.waiting.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }

    func advance() {
        let all = waiting.values
        waiting = [:]
        all.forEach { $0.resume() }
    }
}

/// What the session told VoiceOver, in order.
private final class Said: @unchecked Sendable { var lines: [String] = [] }

/// A box with a text and a caret, a scripted capture and recognizer, and a clock that stands still.
@MainActor private final class Rig {
    let capture: ScriptedCapture
    let clock = FakeClock()
    let session: DictationSession
    let said = Said()
    var text: String
    var caret: Int
    var tentative: Range<Int>?

    init(text: String = "", caret: Int = 0, capture: ScriptedCapture = ScriptedCapture()) {
        self.capture = capture
        self.text = text
        self.caret = caret
        let clock = clock, said = said
        session = DictationSession(capture: capture, sleep: { try await clock.sleep($0) }, announce: { said.lines.append($0) })
    }

    func dictate(with recognizer: ScriptedRecognizer, owner: String = "box") {
        session.start(
            recognizer: recognizer, model: recognizer.models[0],
            into: DictationField(owner: owner, text: { self.text }, caret: { self.caret }, put: { self.text = $0; self.caret = $1; self.tentative = $2 })
        )
    }

    func until(_ what: String = #function, _ condition: () -> Bool) async {
        for _ in 0..<3000 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("never happened: \(what)")
    }

    func reaches(_ state: DictationSession.State) async { await until("\(state)") { session.state == state } }
}

@MainActor @Test func aWholeDictationGoesFromIdleThroughGettingReadyAndListeningBackToIdle() async {
    let rig = Rig(text: "uno dos", caret: 4)
    let recognizer = ScriptedRecognizer(atAudioEnd: [.final("hola mundo")])
    recognizer.holdPrepare()
    #expect(rig.session.state == .idle)
    rig.dictate(with: recognizer)
    #expect(rig.session.state == .gettingReady)
    #expect(rig.capture.startCount == 0)
    recognizer.releasePrepare()
    await rig.reaches(.listening)
    #expect(rig.capture.isRunning)
    recognizer.say(.partial("hola"))
    await rig.until { rig.text == "uno holados" }
    #expect(rig.tentative == 4..<8 && rig.caret == 8)
    recognizer.say(.partial("hola mun"))
    await rig.until { rig.text == "uno hola mundos" }
    rig.session.stop()
    await rig.reaches(.idle)
    #expect(rig.text == "uno hola mundodos" && rig.tentative == nil && rig.caret == 14)
    #expect(rig.capture.isRunning == false && rig.capture.stopCount >= 1)
    #expect(rig.session.failure(for: "box") == nil && rig.session.owner == nil)
}

@MainActor @Test func aModelThatGivesItsTextAtTheEndTranscribesAfterTheStop() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer(partial: .atTheEnd)
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    rig.session.stop()
    #expect(rig.session.state == .transcribing)
    recognizer.say(.final("hola"))
    recognizer.finish()
    await rig.reaches(.idle)
    #expect(rig.text == "hola")
}

@MainActor @Test func audioWithNoSpeechEndsInAnEmptyFinalAndNotInAFailure() async {
    let rig = Rig(text: "uno", caret: 3)
    rig.dictate(with: ScriptedRecognizer(atAudioEnd: [.final("")]))
    await rig.reaches(.listening)
    rig.session.stop()
    await rig.reaches(.idle)
    #expect(rig.text == "uno" && rig.session.failure(for: "box") == nil)
}

@MainActor private enum Point: CaseIterable { case gettingReady, startingTheCapture, listening, transcribing }

@MainActor @Test(arguments: Point.allCases)
private func aFailureAtAnyPointReturnsToIdleWithItsCauseAndKeepsWhatWasHeard(point: Point) async {
    let cause = DictationFailure("No input device")
    let rig = Rig(text: "uno dos", caret: 4, capture: ScriptedCapture(startError: point == .startingTheCapture ? cause : nil))
    let recognizer = ScriptedRecognizer(partial: point == .transcribing ? .atTheEnd : .native, prepareError: point == .gettingReady ? cause : nil)
    rig.dictate(with: recognizer)
    switch point {
    case .gettingReady, .startingTheCapture: break
    case .listening, .transcribing:
        await rig.reaches(.listening)
        recognizer.say(.partial("hola"))
        await rig.until { rig.text == "uno holados" }
        if point == .transcribing { rig.session.stop() }
        recognizer.say(.failed(cause))
    }
    await rig.reaches(.idle)
    #expect(rig.session.failure(for: "box") == cause)
    #expect(rig.session.failure(for: "another box") == nil)
    #expect(rig.tentative == nil)
    #expect(rig.text == (point == .listening || point == .transcribing ? "uno holados" : "uno dos"))
    #expect(rig.capture.isRunning == false)
}

@MainActor @Test func aFailureThatIsNotOursIsToldWithItsOwnWords() async {
    struct Odd: LocalizedError { var errorDescription: String? { "the disk is full" } }
    let rig = Rig(capture: ScriptedCapture(startError: Odd()))
    rig.dictate(with: ScriptedRecognizer())
    await rig.reaches(.idle)
    #expect(rig.session.failure(for: "box") == DictationFailure("the disk is full"))
}

@MainActor @Test func stoppingWhileGettingReadyGoesBackToIdleWithoutListening() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    rig.dictate(with: recognizer)
    rig.session.stop()
    recognizer.releasePrepare()
    await rig.reaches(.idle)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.session.state == .idle && rig.capture.startCount == 0 && rig.text == "")
}

@MainActor @Test func aRecognizerThatNeverAnswersAfterTheStopEndsInAFailureThatKeepsTheText() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola"))
    await rig.until { rig.text == "hola" }
    rig.session.stop()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.session.state == .listening)
    rig.clock.advance()
    await rig.reaches(.idle)
    #expect(rig.text == "hola" && rig.tentative == nil)
    #expect(rig.session.failure(for: "box") == DictationFailure("The recognizer did not answer."))
}

@MainActor private enum Reason: CaseIterable { case aClickATypedKeyOrLeaving, anotherDictation }

@MainActor @Test(arguments: Reason.allCases, [PartialText.native, .atTheEnd])
private func everyReasonToStopKeepsWhatWasHeard(reason: Reason, partial: PartialText) async {
    let rig = Rig(text: "uno dos", caret: 4)
    let first = ScriptedRecognizer(partial: partial)
    rig.dictate(with: first)
    await rig.reaches(.listening)
    first.say(.partial("hola"))
    if partial == .native { await rig.until { rig.text == "uno holados" } }
    switch reason {
    case .aClickATypedKeyOrLeaving: rig.session.stop()
    case .anotherDictation: rig.dictate(with: ScriptedRecognizer(), owner: "another")
    }
    first.say(.final("hola mundo"))
    first.finish()
    await rig.until { rig.text == "uno hola mundodos" && rig.session.owner != "box" }
    #expect(rig.tentative == nil)
    #expect(rig.session.failure(for: "box") == nil)
}

@MainActor @Test func aSecondDictationStopsTheFirstAndStartsWhenItIsIdle() async {
    let rig = Rig()
    let first = ScriptedRecognizer()
    rig.dictate(with: first)
    await rig.reaches(.listening)
    first.say(.partial("hola"))
    await rig.until { rig.text == "hola" }
    let second = ScriptedRecognizer()
    rig.dictate(with: second, owner: "another")
    #expect(rig.session.owner == "box")
    first.finish()
    await rig.until { rig.session.owner == "another" && rig.session.state == .listening }
    #expect(rig.text == "hola" && rig.tentative == nil)
    #expect(rig.capture.startCount == 2)
    second.say(.partial("mundo"))
    await rig.until { rig.text == "holamundo" }
}

@MainActor @Test func stoppingDropsTheDictationThatWasWaitingForTheFirstToEnd() async {
    let rig = Rig()
    let first = ScriptedRecognizer()
    rig.dictate(with: first)
    await rig.reaches(.listening)
    rig.dictate(with: ScriptedRecognizer(), owner: "another")
    rig.session.stop()
    first.finish()
    await rig.reaches(.idle)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.session.state == .idle && rig.capture.startCount == 1)
}

@MainActor @Test func aDictationTellsVoiceOverTheStartAndTheStopWithItsWordsAndNeverThePartialText() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer(atAudioEnd: [.final("hola mundo")])
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola"))
    await rig.until { rig.text == "hola" }
    #expect(rig.said.lines == ["Listening"])
    rig.session.stop()
    await rig.reaches(.idle)
    #expect(rig.said.lines == ["Listening", "Dictation stopped, 2 words added"])
}

@MainActor @Test func aFailureIsToldWithItsCauseAndNotAsAStop() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.failed(DictationFailure("No input device")))
    await rig.reaches(.idle)
    #expect(rig.said.lines == ["Listening", "Dictation failed: No input device"])
}

@Test(arguments: [
    (DictationNotice.listening, "Listening"),
    (.stopped(words: 0), "Dictation stopped, no words added"),
    (.stopped(words: 1), "Dictation stopped, 1 word added"),
    (.stopped(words: 12), "Dictation stopped, 12 words added"),
    (.failed(DictationFailure("Another app holds the microphone")), "Dictation failed: Another app holds the microphone"),
])
func theAnnouncementsOfADictation(notice: DictationNotice, says: String) {
    #expect(dictationAnnouncement(notice) == says)
}

@MainActor @Test func aDictationWritesNoFileAndReleasesTheCaptureWhenItEnds() async throws {
    // the samples of the test are a pattern no other test writes: a file of the temporary folder or the working one that holds it is the audio on disk
    let pattern: Float = 0.123456
    let bytes = withUnsafeBytes(of: [Float](repeating: pattern, count: 64)) { Data($0) }
    func filesWithTheAudio() -> [String] {
        [NSTemporaryDirectory(), FileManager.default.currentDirectoryPath].flatMap { folder -> [String] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            return names.map { folder + "/" + $0 }.filter { path in
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), data.count < 20_000_000 else { return false }
                return data.range(of: bytes) != nil
            }
        }
    }
    let rig = Rig()
    let recognizer = ScriptedRecognizer(atAudioEnd: [.final("hola")])
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    for _ in 0..<5 { rig.capture.feed(AudioBuffer(samples: Array(repeating: pattern, count: 1600), sampleRate: 16000)) }
    rig.session.stop()
    await rig.reaches(.idle)
    #expect(filesWithTheAudio().isEmpty)
    #expect(rig.capture.isRunning == false && rig.capture.stopCount >= 1)
}
