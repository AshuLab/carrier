import Foundation
import Testing
@testable import CarrierCore

// Story 6 (docs/specs/dictation-in-the-app.md): the chunking layer with a scripted batch recognizer. The audio's own timeline is the clock: the
// tests decide how much audio has arrived when they ask for a pass, which is all a clock gives the policy. The numbers are those of the spike,
// docs/research/dictation-chunked-partials.md: a pass every 1 s of audio, a pause of 150 ms after 300 ms of speech closes the segment, a segment
// of 12 s settles by agreement minus the last two words, and the model is never given less than 300 ms.

private let rate = 16_000.0

private func speech(_ seconds: Double) -> AudioBuffer { AudioBuffer(samples: Array(repeating: 0.1, count: Int(seconds * rate)), sampleRate: rate) }
private func silence(_ seconds: Double) -> AudioBuffer { AudioBuffer(samples: Array(repeating: 0, count: Int(seconds * rate)), sampleRate: rate) }

/// Words `w0`, `w1`... one a second, each lasting 0.8 s.
private func words(_ count: Int, from first: Int = 0) -> [TimedWord] {
    (0..<count).map { TimedWord("w\(first + $0)", start: Double($0), end: Double($0) + 0.8) }
}

@Test func aPassIsDueAtEverySecondOfAudioAndNotBefore() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(0.9))
    #expect(policy.nextPass() == nil)
    policy.add(speech(0.1))
    let first = policy.nextPass()
    #expect(first?.kind == .tentative && first?.samples.count == 16_000)
    // the second begins when the first is asked for: 0.9 s later there is nothing, a tenth more and there is, over everything since the start
    policy.add(speech(0.9))
    #expect(policy.nextPass() == nil)
    policy.add(speech(0.1))
    #expect(policy.nextPass()?.samples.count == 32_000)
}

@Test func aLatePassGetsTheNextOneAsItEndsAndNothingQueuesUp() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(1))
    let slow = policy.nextPass()!
    // five seconds go by while it runs, and the driver does not ask again until it is back
    for _ in 0..<5 { policy.add(speech(1)) }
    policy.finish(slow, words: words(1))
    let next = policy.nextPass()
    #expect(next?.samples.count == 96_000)
    #expect(policy.nextPass() == nil)
}

@Test func noPassIsAskedWhileTheSegmentHasLessThan300msOfSpeech() {
    var policy = ChunkPolicy(partials: true)
    policy.add(silence(2))
    #expect(policy.nextPass() == nil)
    policy.add(speech(0.29))
    #expect(policy.nextPass() == nil)
    policy.add(speech(0.02))
    let pass = policy.nextPass()
    #expect(pass != nil)
    #expect((pass?.samples.count ?? 0) >= 4_800)
}

@Test func aPauseOf150msAfter300msOfSpeechClosesTheSegmentAndTheNextPassSeesOnlyWhatFollows() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(1.5))
    policy.finish(policy.nextPass()!, words: words(2))
    policy.add(silence(0.14))
    #expect(policy.nextPass() == nil)
    policy.add(silence(0.01))
    let closing = policy.nextPass()
    #expect(closing?.kind == .closing && closing?.samples.count == Int(1.65 * rate))
    policy.finish(closing!, words: words(3))
    #expect(policy.settled == ["w0", "w1", "w2"] && policy.text == "w0 w1 w2")
    policy.add(speech(1.2))
    let next = policy.nextPass()
    #expect(next?.kind == .tentative && next?.samples.count == Int(1.2 * rate))
    // what the next passes say is shown after what was settled, and replaces itself whole
    policy.finish(next!, words: words(1, from: 7))
    #expect(policy.text == "w0 w1 w2 w7")
    policy.add(speech(1))
    policy.finish(policy.nextPass()!, words: words(2, from: 9))
    #expect(policy.text == "w0 w1 w2 w9 w10")
    #expect(policy.settled == ["w0", "w1", "w2"])
}

@Test func aPauseAfterLessThan300msOfSpeechDoesNotCloseAnything() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(0.2))
    policy.add(silence(0.5))
    #expect(policy.nextPass() == nil)
    policy.add(speech(0.2))
    policy.add(silence(0.2))  // now it has 400 ms of speech and a pause
    #expect(policy.nextPass()?.kind == .closing)
}

@Test func aPassThatWasRunningWhenAPauseClosedItsSegmentIsLeftOutAndItsClosingPassHasTheLastWord() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(1))
    let running = policy.nextPass()!
    policy.add(silence(0.15))
    policy.finish(running, words: words(2))  // late: the pause already closed the segment
    #expect(policy.text.isEmpty)
    let closing = policy.nextPass()!
    #expect(closing.kind == .closing)
    policy.finish(closing, words: words(3))
    #expect(policy.text == "w0 w1 w2")
}

@Test func aSegmentOf12sWithNoPauseSettlesTheWordsTwoPassesAgreeOnMinusTheLastTwoAndCutsInTheMiddleOfTheGap() {
    var policy = ChunkPolicy(partials: true)
    for second in 1...11 {
        policy.add(speech(1))
        let pass = policy.nextPass()!
        policy.finish(pass, words: words(second - 1))  // under 12 s nothing is settled, whatever the passes agree on
        #expect(policy.settled.isEmpty)
    }
    policy.add(speech(1))
    let pass = policy.nextPass()!
    #expect(pass.samples.count == 192_000)
    policy.finish(pass, words: words(11))  // agrees with the pass before on ten words: eight are settled
    #expect(policy.settled == (0..<8).map { "w\($0)" })
    #expect(policy.text == (0..<11).map { "w\($0)" }.joined(separator: " "))
    // word 7 ends at 7.8 s and word 8 starts at 8.0: the audio is cut at 7.9 s, and what follows is what the next pass gets
    policy.add(speech(1))
    #expect(policy.nextPass()?.samples.count == 192_000 + 16_000 - Int(7.9 * rate))
}

@Test(arguments: [
    (words(2), words(2)),  // two words agree and none is left to settle
    (words(1), words(1)),
    (words(5), words(5, from: 1)),  // two passes that do not agree
    ([], words(3)),
])
func withFewerThanTwoAgreedWordsAfterTheLastTwoNothingIsSettledAt12s(before: [TimedWord], now: [TimedWord]) {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(11))
    policy.finish(policy.nextPass()!, words: before)
    policy.add(speech(1))
    policy.finish(policy.nextPass()!, words: now)
    #expect(policy.settled.isEmpty)
    #expect(policy.text == now.map(\.text).joined(separator: " "))
}

@Test func aSegmentIsClosedAt15sWhateverThePassesSayEvenWithNoPauseAndNothingAgreed() {
    var policy = ChunkPolicy(partials: true)
    for second in 1...14 {
        policy.add(speech(1))
        policy.finish(policy.nextPass()!, words: words(second % 2))  // passes that never agree: the 12 s rule settles nothing
    }
    #expect(policy.settled.isEmpty)
    policy.add(speech(1))
    let closing = policy.nextPass()
    #expect(closing?.kind == .closing && closing?.samples.count == Int(15 * rate))
    policy.finish(closing!, words: words(3))
    #expect(policy.settled == ["w0", "w1", "w2"])
    policy.add(speech(1))
    #expect(policy.nextPass()?.samples.count == Int(rate), "the next segment starts from nothing")
}

@Test func aNoisyRoomOrAnEmptyResultNeverMakesASegmentLongerThan15s() {
    var policy = ChunkPolicy(partials: true)
    for _ in 0..<60 {
        policy.add(speech(1))
        while let pass = policy.nextPass() {
            #expect(pass.samples.count <= Int(15 * rate))
            policy.finish(pass, words: [])
        }
    }
    // a silence with nothing said is dropped too, with no pass
    var quiet = ChunkPolicy(partials: true)
    quiet.add(silence(20))
    #expect(quiet.nextPass() == nil)
    quiet.add(speech(0.5))
    #expect(quiet.nextPass()?.samples.count == Int(5.5 * rate))
}

@Test func aModelAtTheEndStopsListeningAfterTwoMinutesAndGetsThoseTwoMinutes() {
    var policy = ChunkPolicy(partials: false)
    for _ in 0..<150 { policy.add(speech(1)) }
    let pass = policy.nextPass()
    #expect(pass?.kind == .final && pass?.samples.count == Int(120 * rate))
}

@Test func theStopAsksForOnePassOverWhatIsNotSettledAndTheTextIsFinal() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(1.5))
    policy.finish(policy.nextPass()!, words: words(2))
    policy.add(silence(0.15))
    policy.finish(policy.nextPass()!, words: words(3))
    policy.add(speech(0.6))
    policy.end()
    let last = policy.nextPass()
    #expect(last?.kind == .final && last?.samples.count == Int(0.6 * rate))
    #expect(policy.isComplete == false)
    policy.finish(last!, words: words(2, from: 3))
    #expect(policy.isComplete && policy.text == "w0 w1 w2 w3 w4")
    #expect(policy.nextPass() == nil)
}

@Test func withNoSpeechAtAllTheStopIsAnEmptyFinalAndNoPass() {
    var policy = ChunkPolicy(partials: true)
    policy.add(silence(3))
    policy.end()
    #expect(policy.nextPass() == nil)
    #expect(policy.isComplete && policy.text.isEmpty)
    var nothing = ChunkPolicy(partials: true)
    nothing.end()
    #expect(nothing.nextPass() == nil && nothing.isComplete)
}

@Test func aSegmentOfLessThan300msIsPaddedWithSilenceSoTheModelNeverGetsLess() {
    var policy = ChunkPolicy(partials: true)
    policy.add(speech(0.1))
    policy.end()
    #expect(policy.nextPass()?.samples.count == 4_800)
}

@Test func aModelThatGivesItsTextAtTheEndGetsNoPassUntilTheStop() {
    var policy = ChunkPolicy(partials: false)
    for _ in 0..<30 {
        policy.add(speech(1))
        policy.add(silence(0.5))  // pauses do not cut it either
        #expect(policy.nextPass() == nil)
    }
    policy.end()
    let pass = policy.nextPass()
    #expect(pass?.kind == .final && pass?.samples.count == 30 * 24_000)
    policy.finish(pass!, words: words(2))
    #expect(policy.isComplete && policy.text == "w0 w1")
    var short = ChunkPolicy(partials: false)
    short.add(speech(0.2))
    short.end()
    #expect(short.nextPass() == nil && short.isComplete && short.text.isEmpty)
}

/// Whatever the audio and whatever the passes say, a word that was settled stays where it was and the text always starts with the settled words.
@Test(arguments: [1, 2, 3, 4, 5, 6, 7, 8])
func aWordAlreadySettledIsNeverLostWhateverThePassesSay(seed: UInt64) {
    var random = SeededGenerator(seed: seed)
    var policy = ChunkPolicy(partials: true)
    var settled: [String] = []
    var pending: [ChunkPolicy.Pass] = []
    var counter = 0
    func check() {
        #expect(policy.settled.starts(with: settled), "settled words changed: \(settled) -> \(policy.settled)")
        settled = policy.settled
        #expect(policy.text.hasPrefix(settled.joined(separator: " ")))
    }
    for _ in 0..<300 {
        let seconds = Double.random(in: 0.02...1.4, using: &random)
        policy.add(Bool.random(using: &random) ? speech(seconds) : silence(seconds * 0.4))
        check()
        if let pass = policy.nextPass() { pending.append(pass) }
        // passes come back late and in any number, saying anything, including nothing and a different text from before
        if pending.isEmpty == false, Int.random(in: 0..<3, using: &random) == 0 {
            let pass = pending.removeFirst()
            let count = Int.random(in: 0...Int(max(1, Double(pass.samples.count) / rate)), using: &random)
            let flip = Bool.random(using: &random)
            policy.finish(pass, words: (0..<count).map {
                counter += flip ? 1 : 0
                return TimedWord(flip ? "x\(counter)" : "w\($0)", start: Double($0), end: Double($0) + 0.8)
            })
            check()
        }
    }
    policy.end()
    for pass in pending + [policy.nextPass()].compactMap({ $0 }) { policy.finish(pass, words: words(2)) }
    check()
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

// MARK: the recognizer over a capture

/// A batch recognizer that says what the test scripts, and how many passes ran at once.
private actor ScriptedBatch: BatchTranscriber {
    private(set) var passes: [Int] = []
    private(set) var mostAtOnce = 0
    private var running = 0
    private let words: [TimedWord]
    private let delay: Duration
    private let fails: Bool

    init(words: [TimedWord] = [TimedWord("hola", start: 0, end: 0.4), TimedWord("mundo", start: 0.5, end: 0.9)], delay: Duration = .zero, fails: Bool = false) {
        self.words = words
        self.delay = delay
        self.fails = fails
    }

    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> [TimedWord] {
        passes.append(samples.count)
        running += 1
        mostAtOnce = max(mostAtOnce, running)
        defer { running -= 1 }
        if delay > .zero { try await Task.sleep(for: delay) }
        if fails { throw DictationFailure("the model broke") }
        return words
    }
}

private func capture() -> (AsyncStream<AudioBuffer>, AsyncStream<AudioBuffer>.Continuation) { AsyncStream.makeStream() }

@Test func aDictationShowsPartialTextWhileItListensAndEndsInTheFinal() async {
    let batch = ScriptedBatch()
    let (audio, input) = capture()
    var events = ChunkedRecognizer(batch, partials: true).recognize(audio).makeAsyncIterator()
    for _ in 0..<10 { input.yield(speech(0.1)) }
    #expect(await events.next() == .partial("hola mundo"))
    input.yield(speech(0.3))
    input.finish()
    var rest: [DictationEvent] = []
    while let event = await events.next() { rest.append(event) }
    #expect(rest == [.final("hola mundo")], "the same text is not shown twice")
    #expect(await batch.passes.allSatisfy { $0 >= 4_800 })
}

@Test func aModelThatGivesItsTextAtTheEndShowsNoPartialTextAndIsAskedOnce() async {
    let batch = ScriptedBatch()
    let (audio, input) = capture()
    let events = ChunkedRecognizer(batch, partials: false).recognize(audio)
    for _ in 0..<40 { input.yield(speech(0.1)) }
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    #expect(seen == [.final("hola mundo")])
    #expect(await batch.passes == [64_000])
}

@Test func noAudioEndsInAnEmptyFinalAndTheModelIsNeverAsked() async {
    for partials in [true, false] {
        let batch = ScriptedBatch()
        let (audio, input) = capture()
        let events = ChunkedRecognizer(batch, partials: partials).recognize(audio)
        input.finish()
        var seen: [DictationEvent] = []
        for await event in events { seen.append(event) }
        #expect(seen == [.final("")])
        #expect(await batch.passes.isEmpty)
    }
}

@Test func twoPassesNeverRunAtOnceWhenTheModelIsSlow() async {
    let batch = ScriptedBatch(delay: .milliseconds(30))
    let (audio, input) = capture()
    let events = ChunkedRecognizer(batch, partials: true).recognize(audio)
    for _ in 0..<50 { input.yield(speech(0.1)) }  // five seconds arrive at once
    input.finish()
    for await _ in events {}
    #expect(await batch.mostAtOnce == 1)
    #expect(await batch.passes.count < 5, "the late passes did not queue up")
}

/// A model that never answers, and sees whether it was cancelled.
private actor Hanging: BatchTranscriber {
    private(set) var calls = 0
    private(set) var cancelled = false

    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> [TimedWord] {
        calls += 1
        do { try await Task.sleep(for: .seconds(60)) } catch {
            cancelled = true
            throw error
        }
        return []
    }
}

@Test func endingTheEventsCancelsThePassInFlight() async throws {
    let batch = Hanging()
    let (audio, input) = capture()
    let events = ChunkedRecognizer(batch, partials: true).recognize(audio)
    let listening = Task { for await _ in events {} }
    input.yield(speech(1.2))
    for _ in 0..<200 where await batch.calls == 0 { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await batch.calls == 1)
    listening.cancel()
    for _ in 0..<200 where await batch.cancelled == false { try await Task.sleep(for: .milliseconds(10)) }
    #expect(await batch.cancelled, "the pass kept running over the whole audio")
    #expect(await batch.calls == 1)
}

@Test func aFailureOfTheModelIsAFailureWithItsCause() async {
    let (audio, input) = capture()
    let events = ChunkedRecognizer(ScriptedBatch(fails: true), partials: false).recognize(audio)
    input.yield(speech(1))
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    #expect(seen == [.failed(DictationFailure("The speech model stopped: the model broke"))])
}
