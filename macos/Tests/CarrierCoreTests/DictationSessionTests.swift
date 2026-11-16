import Foundation
import Testing
@testable import CarrierCore

/// A clock that moves only when a test says so: `sleep` waits for `advance`.
@MainActor private final class FakeClock {
    private var waiting: [UUID: CheckedContinuation<Void, Error>] = [:]
    /// How long each sleep asked for.
    private(set) var requested: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        requested.append(duration)
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
private final class Said: @unchecked Sendable { var lines: [String] = []; var logged: [String] = [] }

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
        session = DictationSession(capture: capture, sleep: { try await clock.sleep($0) }, announce: { said.lines.append($0) }, log: { said.logged.append($0.cause) })
    }

    func dictate(with recognizer: ScriptedRecognizer, owner: String = "box", cleanup: DictationCleanup? = nil) {
        session.start(
            recognizer: recognizer, model: recognizer.models[0],
            into: DictationField(owner: owner, text: { self.text }, caret: { self.caret }, put: { self.text = $0; self.caret = $1; self.tentative = $2 }),
            cleanup: cleanup
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

@MainActor @Test(arguments: [PartialText.native, .atTheEnd])
private func cancellingKeepsTheTextThatIsThereAndIgnoresWhatTheRecognizerSaysAfterwards(partial: PartialText) async {
    let rig = Rig(text: "uno dos", caret: 4)
    let recognizer = ScriptedRecognizer(partial: partial)
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola"))
    if partial == .native { await rig.until { rig.text == "uno holados" } }
    let shown = rig.text
    #expect(rig.session.cancel())
    // it is idle at once, the partial text is final and the audio is gone
    #expect(rig.session.state == .idle)
    #expect(rig.tentative == nil)
    #expect(rig.text == shown)
    #expect(rig.capture.isRunning == false)
    // what the recognizer says after the cancel changes nothing, and a second cancel has nothing to cancel
    recognizer.say(.final("hola mundo"))
    recognizer.finish()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.text == shown)
    #expect(rig.session.cancel() == false)
}

@MainActor @Test func cancellingWhileTranscribingGivesUpTheTextThatWasToCome() async {
    let rig = Rig(text: "uno", caret: 3)
    let recognizer = ScriptedRecognizer(partial: .atTheEnd)
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    rig.session.stop()
    #expect(rig.session.state == .transcribing)
    #expect(rig.session.cancel())
    recognizer.say(.final("hola"))
    recognizer.finish()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.session.state == .idle && rig.text == "uno")
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
    await rig.until { rig.text == "hola mundo" }
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
    #expect(rig.said.lines == ["Getting the model ready", "Listening"])
    rig.session.stop()
    await rig.reaches(.idle)
    #expect(rig.said.lines == ["Getting the model ready", "Listening", "Dictation stopped, 2 words added"])
}

@MainActor @Test func aFailureIsToldWithItsCauseAndNotAsAStop() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.failed(DictationFailure("No input device")))
    await rig.reaches(.idle)
    #expect(rig.said.lines == ["Getting the model ready", "Listening", "Dictation failed: No input device"])
}

@Test(arguments: [
    (DictationNotice.gettingReady, "Getting the model ready"),
    (.listening, "Listening"),
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

@MainActor @Test func aDictationThatTheRecognizerNeverBeginsIsToldAsGettingReady() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    recognizer.holdPrepare()
    rig.dictate(with: recognizer)
    #expect(rig.said.lines == ["Getting the model ready"])
    rig.session.cancel()
    #expect(rig.said.lines == ["Getting the model ready"])
}

@MainActor @Test func theWordsOfAPartialTextThatStaysAreCountedWhenTheDictationIsCancelled() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola mundo"))
    await rig.until { rig.text == "hola mundo" }
    rig.session.cancel()
    #expect(rig.said.lines.last == "Dictation stopped, 2 words added")
}

@MainActor @Test func aFinalAfterAPartialCountsItsWordsOnceAndAPartialThatIsReplacedByNothingCountsNone() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola"))
    recognizer.say(.final("hola mundo"))
    recognizer.say(.partial("ruido"))
    recognizer.say(.final(""))
    await rig.until { rig.text == "hola mundo" && rig.tentative == nil }
    rig.session.cancel()
    #expect(rig.said.lines.last == "Dictation stopped, 2 words added")
}

@MainActor @Test func aTextTypedBeforeWhereAModelThatAnswersAtTheEndWritesMovesItsPlace() async {
    let rig = Rig(text: "uno dos", caret: 4)
    let recognizer = ScriptedRecognizer(partial: .atTheEnd)
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    rig.session.stop()
    #expect(rig.session.state == .transcribing)
    // the person types at the start while it transcribes, and their caret goes with it
    rig.text = "X" + rig.text
    rig.caret = 1
    recognizer.say(.final("hola "))
    recognizer.finish()
    await rig.reaches(.idle)
    #expect(rig.text == "Xuno hola dos" && rig.caret == 1)
}

@MainActor @Test func aTextTypedInsideThePartialTextIsNotOverwrittenByTheFinalOne() async {
    let rig = Rig(text: "uno dos", caret: 4)
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola"))
    await rig.until { rig.text == "uno holados" }
    rig.text = "uno hoXlados"
    rig.session.stop()
    recognizer.say(.final("hola mundo"))
    recognizer.finish()
    await rig.reaches(.idle)
    #expect(rig.text == "uno hoXlados" && rig.tentative == nil)
}

@MainActor @Test func stoppingABoxDropsItsOwnWaitingDictationAndNoOneElses() async {
    let rig = Rig()
    let first = ScriptedRecognizer()
    rig.dictate(with: first)
    await rig.reaches(.listening)
    rig.dictate(with: ScriptedRecognizer(), owner: "another")
    // the box that listens stopping does not drop what another box waits to start
    rig.session.stop(ownedBy: "someone else")
    #expect(rig.session.state == .listening)
    // the box that waits leaving does
    rig.session.stop(ownedBy: "another")
    first.finish()
    await rig.reaches(.idle)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.session.state == .idle && rig.capture.startCount == 1)
}

@MainActor @Test func aDictationThatWaitsForTheFirstStartsWhenTheFirstIsStoppedByItsOwnBox() async {
    let rig = Rig()
    let first = ScriptedRecognizer()
    rig.dictate(with: first)
    await rig.reaches(.listening)
    rig.dictate(with: ScriptedRecognizer(), owner: "another")
    rig.session.stop(ownedBy: "box")
    first.finish()
    await rig.until { rig.session.owner == "another" && rig.session.state == .listening }
}

@MainActor @Test func theTimeToAnswerGrowsWithTheAudioThatWasCaptured() async {
    let rig = Rig()
    let recognizer = ScriptedRecognizer(partial: .atTheEnd)
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    // two minutes of speech
    rig.capture.feed(AudioBuffer(samples: Array(repeating: 0, count: 16000 * 120), sampleRate: 16000))
    try? await Task.sleep(for: .milliseconds(100))
    rig.session.stop()
    await rig.until { rig.clock.requested.isEmpty == false }
    #expect(rig.clock.requested == [DictationSession.answerFloor + .seconds(120)])
}

@MainActor @Test func aDictationWithNoAudioGivesTheRecognizerTheFloorOnly() async {
    let rig = Rig()
    rig.dictate(with: ScriptedRecognizer())
    await rig.reaches(.listening)
    rig.session.stop()
    await rig.until { rig.clock.requested.isEmpty == false }
    #expect(rig.clock.requested == [DictationSession.answerFloor])
}

@MainActor @Test func aFailureToStartIsTold() {
    let rig = Rig()
    rig.session.refuse(DictationFailure("No speech model is available"), for: "box")
    #expect(rig.session.failure(for: "box")?.cause == "No speech model is available")
    #expect(rig.said.lines == ["Dictation failed: No speech model is available"])
}

private final class Seen: @unchecked Sendable {
    var takes: [DictationTake] = []
    var now = Date(timeIntervalSince1970: 1_000)
}

@MainActor @Test func aDictationThatEndsTellsWhatItHeardWhenItStartedAndHowLongTheRecognizerTookAfterTheStop() async {
    let seen = Seen()
    let capture = ScriptedCapture()
    let session = DictationSession(capture: capture, now: { seen.now })
    session.onTake = { seen.takes.append($0) }
    var text = ""
    let recognizer = ScriptedRecognizer(atAudioEnd: [.final("mundo")])
    session.start(recognizer: recognizer, model: recognizer.models[0], into: DictationField(owner: "box", text: { text }, caret: { text.count }, put: { text = $0; _ = ($1, $2) }))
    for _ in 0..<3000 where session.state != .listening { try? await Task.sleep(for: .milliseconds(1)) }
    recognizer.say(.final("hola"))
    for _ in 0..<3000 where text.isEmpty { try? await Task.sleep(for: .milliseconds(1)) }
    seen.now += 10
    session.stop()
    seen.now += 0.5
    for _ in 0..<3000 where session.state != .idle { try? await Task.sleep(for: .milliseconds(1)) }
    #expect(seen.takes == [DictationTake(owner: "box", started: Date(timeIntervalSince1970: 1_000), text: "hola mundo", model: "Scripted", audio: 0, transcription: 0.5, ending: .stopped, cleaned: nil, cleanupSeconds: nil)])
    #expect(session.take == seen.takes.first)
}

@MainActor @Test func aCancelledDictationKeepsThePartialTextOnTheScreenAndAFailedOneEndsAsFailed() async {
    let seen = Seen()
    let rig = Rig()
    rig.session.onTake = { seen.takes.append($0) }
    let recognizer = ScriptedRecognizer()
    rig.dictate(with: recognizer)
    await rig.reaches(.listening)
    recognizer.say(.partial("hola que"))
    await rig.until { rig.text == "hola que" }
    #expect(rig.session.cancel())
    #expect(seen.takes.map(\.text) == ["hola que"] && seen.takes.map(\.ending) == [.cancelled])
    let broken = ScriptedRecognizer()
    rig.dictate(with: broken)
    await rig.reaches(.listening)
    broken.say(.final("uno"))
    await rig.until { rig.text.hasSuffix("uno") }
    broken.say(.failed(DictationFailure("The model broke")))
    await rig.reaches(.idle)
    #expect(seen.takes.map(\.text) == ["hola que", "uno"] && seen.takes.map(\.ending) == [.cancelled, .failed])
}

// The cleanup of a dictation in a box (docs/adr/0030): the model client is scripted and the clock is the rig's, which stands still.

/// A model server that answers when a test says so, through the real `CleanupRun`.
private final class ScriptedServer: TextModelClient, @unchecked Sendable {
    private let lock = NSLock()
    private var answer: Result<String, any Error>?
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var asked: [String] = []

    func models(of server: CleanupServer) async throws -> [String] { [] }

    func complete(server: CleanupServer, model: String, system: String, text: String, timeout: Duration) async throws -> String {
        lock.withLock { asked.append(text) }
        await withCheckedContinuation { continuation in
            lock.withLock {
                if answer == nil { waiting = continuation } else { continuation.resume() }
            }
        }
        return try lock.withLock { answer }!.get()
    }

    func reply(_ result: Result<String, any Error>) {
        let resumed = lock.withLock {
            answer = result
            defer { waiting = nil }
            return waiting
        }
        resumed?.resume()
    }

    var cleanup: DictationCleanup {
        { try await CleanupRun(client: self).run(server: .ollama, model: "m", prompt: "Clean it", text: $0).text }
    }
}

/// A box with "uno dos" and the caret after "uno ", which dictated "um hola" and was stopped: the session cleans.
@MainActor private func cleaning(_ server: ScriptedServer, partial: PartialText = .native) async -> (Rig, ScriptedRecognizer) {
    let rig = Rig(text: "uno dos", caret: 4)
    let recognizer = ScriptedRecognizer(partial: partial, atAudioEnd: [.final("um hola")])
    rig.dictate(with: recognizer, cleanup: server.cleanup)
    await rig.reaches(.listening)
    rig.session.stop()
    await rig.reaches(.cleaning)
    return (rig, recognizer)
}

@MainActor @Test(arguments: [PartialText.native, .atTheEnd])
private func theCleanedTextReplacesOnlyWhatTheDictationAddedAndTheRestOfTheBoxStays(partial: PartialText) async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server, partial: partial)
    // the raw text is in the box while the model works, and the model is asked for what the dictation added and nothing around it
    #expect(rig.text == "uno um holados" && server.asked == ["um hola"])
    server.reply(.success("Hola."))
    await rig.reaches(.idle)
    #expect(rig.text == "uno Hola.dos" && rig.tentative == nil && rig.session.failure(for: "box") == nil)
    // the caret that was after the dictated text is after the cleaned one
    #expect(rig.caret == 9)
    #expect(rig.said.lines.last == "Dictation stopped, 1 word added")
}

@MainActor @Test func theTakeOfACleanedDictationHasTheRawAndTheCleanedTextAndASkippedOneOnlyTheRaw() async {
    let seen = Seen()
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server)
    rig.session.onTake = { seen.takes.append($0) }
    server.reply(.success("Hola."))
    await rig.reaches(.idle)
    #expect(seen.takes.map(\.text) == ["um hola"] && seen.takes.map(\.cleaned) == ["Hola."] && seen.takes.first?.cleanupSeconds != nil)
    let skipped = ScriptedServer()
    let (other, _) = await cleaning(skipped)
    other.session.onTake = { seen.takes.append($0) }
    #expect(other.session.cancel())
    #expect(seen.takes.last?.text == "um hola" && seen.takes.last?.cleaned == nil && seen.takes.last?.ending == .stopped)
}

@MainActor @Test func aDictationWithNoWordsIsNotCleaned() async {
    let server = ScriptedServer()
    let rig = Rig(text: "uno", caret: 3)
    rig.dictate(with: ScriptedRecognizer(atAudioEnd: [.final("")]), cleanup: server.cleanup)
    await rig.reaches(.listening)
    rig.session.stop()
    await rig.reaches(.idle)
    #expect(server.asked.isEmpty && rig.text == "uno")
}

@MainActor @Test func theTimeTheRecognizerWasGivenDoesNotRunOutWhileTheModelCleans() async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server, partial: .atTheEnd)
    rig.clock.advance()
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.session.state == .cleaning && rig.session.failure(for: "box") == nil)
    server.reply(.success("Hola."))
    await rig.reaches(.idle)
    #expect(rig.text == "uno Hola.dos")
}

@MainActor @Test(arguments: [
    CleanupFailure.serverDown(.ollama), .noModel, .timeout,
])
private func aCleanupThatFailsLeavesTheRawTextTellsTheCauseAndLogsItAlone(failure: CleanupFailure) async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server)
    server.reply(.failure(failure))
    await rig.reaches(.idle)
    #expect(rig.text == "uno um holados" && rig.caret == 11)
    #expect(rig.session.failure(for: "box") == DictationFailure(failure.message))
    #expect(rig.said.logged == [failure.message])
    #expect(rig.said.lines.last == "Dictation failed: \(failure.message)")
}

@MainActor @Test func cancellingWhileItCleansKeepsTheRawTextAndIgnoresTheLateAnswer() async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server)
    #expect(rig.session.cancel())
    #expect(rig.session.state == .idle && rig.text == "uno um holados" && rig.session.failure(for: "box") == nil)
    server.reply(.success("Hola."))
    try? await Task.sleep(for: .milliseconds(20))
    #expect(rig.text == "uno um holados" && rig.said.logged.isEmpty)
}

@MainActor @Test func aKeyTypedInTheBoxOrLeavingItSkipsTheCleanup() async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server)
    rig.session.stop(ownedBy: "box")
    #expect(rig.session.state == .idle && rig.text == "uno um holados")
}

@MainActor @Test func aTextThatChangedWhileItCleanedIsNeverOverwritten() async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server)
    rig.text = "otro uno um holados"
    server.reply(.success("Hola."))
    await rig.reaches(.idle)
    #expect(rig.text == "otro uno um holados" && rig.session.failure(for: "box") == nil)
}

@MainActor @Test func anotherBoxStartingWhileItCleansSkipsTheCleanupAndStartsAtOnce() async {
    let server = ScriptedServer()
    let (rig, _) = await cleaning(server)
    let next = ScriptedRecognizer()
    rig.dictate(with: next, owner: "other")
    #expect(rig.session.state != .cleaning && rig.text == "uno um holados")
    await rig.reaches(.listening)
    #expect(rig.session.owner == "other")
}
