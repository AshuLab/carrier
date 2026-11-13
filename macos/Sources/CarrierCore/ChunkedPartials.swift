import Foundation

// Partial text for a model that transcribes a whole piece of audio and does not stream (docs/research/dictation-chunked-partials.md, the design
// of this file; docs/specs/dictation-in-the-app.md, story 6). `ChunkPolicy` is the policy as a value with no clock and no model: audio goes in,
// passes come out, and a pass's words go back in. `ChunkedRecognizer` runs it over a capture and a `BatchTranscriber`. The audio's own timeline
// is the clock: a pass is due after a second of audio, so a late pass is followed by the next one as it ends and nothing queues up.

/// A word of a pass and where it sits, in seconds from the start of the audio that pass was given.
public struct TimedWord: Sendable, Equatable {
    public let text: String
    public let start: Double
    public let end: Double

    public init(_ text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// A model that turns a whole piece of audio into words with their times. The core never gives it less than 300 ms.
public protocol BatchTranscriber: Sendable {
    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> [TimedWord]
}

/// What the spike measured on Parakeet TDT v3 (six clips, interval 1 s): the policy `hyb150-12-2`.
public struct ChunkPolicy: Sendable {
    /// A pass over the segment so far every second of audio.
    static let interval = 1.0
    /// A pause this long, after `minimumSpeech`, closes the segment: its last pass is settled and its audio dropped.
    static let pause = 0.15
    static let minimumSpeech = 0.3
    /// The capture's level under which a frame of 10 ms is silence.
    static let silence = pow(10.0, -45.0 / 20)
    /// A segment this long with no pause settles by agreement.
    static let longestSegment = 12.0
    /// The words of the agreement the last of which stay tentative.
    static let heldBack = 2
    /// A segment never grows past this, the window Parakeet takes in one go: it is closed as a pause would, even in the middle of a word, so
    /// that noise, an unstable model or an empty agreement cannot make every pass longer than the one before.
    // ponytail: the cut can split a word and the model hears the tail without its context; a cut at the quietest frame near the end would not
    static let hardLimit = 15.0
    /// A model that gives its text at the end keeps the whole audio, so the audio is ended here: two minutes is what a model of the at-the-end
    /// side (Whisper, RTF about 0.1) transcribes inside the session's 30 s wait for the answer, and about 23 MB of samples at 48 kHz.
    // ponytail: the rest is not heard; resampling to 16 kHz as it comes would lift the ceiling to the wait for the answer, not to memory
    static let longestAtTheEnd = 120.0

    public struct Pass: Sendable, Equatable {
        public enum Kind: Sendable { case tentative, closing, final }
        public let kind: Kind
        let segment: Int
        public let samples: [Float]
        public let sampleRate: Double
    }

    private let partials: Bool
    private var sampleRate = 0.0
    private var samples: [Float] = []
    /// Which segment the audio belongs to: it goes up when a pause closes one.
    private var segment = 0
    private var speechFrames = 0
    private var quietFrames = 0
    private var frameEnergy = 0.0
    private var frameLength = 0
    private var frameFill = 0
    private var sinceRequest = 0
    /// The words of the last pass over this segment, to find what two passes in a row agree on.
    private var previous: [TimedWord]?
    private var waiting: [Pass] = []
    private var ended = false
    private var finalAsked = false

    /// The words that will not change.
    public private(set) var settled: [String] = []
    /// The words of the last pass over the open segment; a new pass replaces them whole.
    public private(set) var tentative: [String] = []
    public private(set) var isComplete = false

    /// With `partials` false the audio is kept whole and the only pass is the one the stop asks for: the model gives its text at the end.
    public init(partials: Bool) { self.partials = partials }

    /// What the box shows: the settled words followed by the tentative ones.
    public var text: String { (settled + tentative).joined(separator: " ") }

    private var minimumSamples: Int { Int(Self.minimumSpeech * sampleRate) }

    public mutating func add(_ buffer: AudioBuffer) {
        guard ended == false else { return }
        if sampleRate != buffer.sampleRate {
            sampleRate = buffer.sampleRate
            frameLength = max(1, Int(buffer.sampleRate / 100))
        }
        guard partials else {
            samples += buffer.samples
            if Double(samples.count) >= Self.longestAtTheEnd * sampleRate { ended = true }
            return
        }
        for sample in buffer.samples {
            samples.append(sample)
            sinceRequest += 1
            frameEnergy += Double(sample * sample)
            frameFill += 1
            if frameFill == frameLength {
                frameFill = 0
                endFrame()
                if Double(samples.count) >= Self.hardLimit * sampleRate { closeSegment() }
            }
        }
    }

    private mutating func endFrame() {
        let rms = (frameEnergy / Double(frameLength)).squareRoot()
        frameEnergy = 0
        guard rms < Self.silence else {
            speechFrames += 1
            quietFrames = 0
            return
        }
        quietFrames += 1
        if quietFrames == Int((Self.pause * 100).rounded()), Double(speechFrames) >= Self.minimumSpeech * 100 { closeSegment() }
    }

    /// The segment ends here: with enough speech its last pass is asked for, without it the audio is only dropped.
    private mutating func closeSegment() {
        if Double(speechFrames) >= Self.minimumSpeech * 100 { waiting.append(Pass(kind: .closing, segment: segment, samples: samples, sampleRate: sampleRate)) }
        segment += 1
        samples = []
        speechFrames = 0
        quietFrames = 0
        sinceRequest = 0
        previous = nil
    }

    /// The audio ended: what is left is asked for once, and the dictation is complete when it comes back.
    public mutating func end() { ended = true }

    /// The pass to run now, if any; call it when no other is running.
    public mutating func nextPass() -> Pass? {
        if waiting.isEmpty == false { return waiting.removeFirst() }
        if ended {
            guard finalAsked == false else { return nil }
            finalAsked = true
            // no speech, or less than the model takes, is no pass: nothing was said
            guard partials ? speechFrames > 0 : samples.count >= max(1, minimumSamples) else {
                isComplete = true
                return nil
            }
            let padded = samples.count < minimumSamples ? samples + Array(repeating: 0, count: minimumSamples - samples.count) : samples
            return Pass(kind: .final, segment: segment, samples: padded, sampleRate: sampleRate)
        }
        guard partials, Double(speechFrames) >= Self.minimumSpeech * 100, Double(sinceRequest) >= Self.interval * sampleRate else { return nil }
        sinceRequest = 0
        return Pass(kind: .tentative, segment: segment, samples: samples, sampleRate: sampleRate)
    }

    /// The words a pass came back with.
    public mutating func finish(_ pass: Pass, words: [TimedWord]) {
        switch pass.kind {
        case .closing:
            settled += words.map(\.text)
            tentative = []
        case .final:
            settled += words.map(\.text)
            tentative = []
            isComplete = true
        case .tentative:
            // a pause closed this segment while the pass ran: its closing pass has the last word
            guard pass.segment == segment else { return }
            tentative = words.map(\.text)
            settleByAgreement(pass, words)
        }
    }

    // ponytail: the pause threshold is fixed at -45 dBFS, as measured on clean clips; a noisy room needs it relative to the noise floor
    private mutating func settleByAgreement(_ pass: Pass, _ words: [TimedWord]) {
        guard let before = previous, Double(pass.samples.count) >= Self.longestSegment * sampleRate else {
            previous = words
            return
        }
        let agreed = zip(before, words).prefix { Self.same($0.text, $1.text) }.count
        let keep = agreed - Self.heldBack
        guard keep > 0 else {
            previous = words
            return
        }
        // the cut is in the middle of the gap after the last settled word, so the next pass starts between words
        let cut = (words[keep - 1].end + words[keep].start) / 2
        settled += words[..<keep].map(\.text)
        tentative = words[keep...].map(\.text)
        samples.removeFirst(min(samples.count, max(0, Int(cut * sampleRate))))
        previous = nil
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        func key(_ word: String) -> String { String(word.lowercased().filter { $0.isLetter || $0.isNumber }) }
        return key(a) == key(b)
    }
}

/// A `BatchTranscriber` made into a recognizer's events: the policy over a capture's audio.
public struct ChunkedRecognizer: Sendable {
    private enum Input: Sendable {
        case audio(AudioBuffer)
        case ended
        case done(ChunkPolicy.Pass, Result<[TimedWord], DictationFailure>)
    }

    private let transcriber: any BatchTranscriber
    private let partials: Bool

    /// `partials` false is a model the rule puts at the end: it gets no pass until the audio ends.
    public init(_ transcriber: any BatchTranscriber, partials: Bool) {
        self.transcriber = transcriber
        self.partials = partials
    }

    public func recognize(_ audio: AsyncStream<AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let (inputs, feed) = AsyncStream<Input>.makeStream()
        let (transcriber, partials) = (transcriber, partials)
        let reader = Task {
            for await buffer in audio { feed.yield(.audio(buffer)) }
            feed.yield(.ended)
        }
        let loop = Task {
            // the passes are children of the loop: cancelling it cancels the pass in flight, which would else go on over the whole audio
            await withTaskGroup(of: Void.self) { passes in
                var policy = ChunkPolicy(partials: partials)
                var running = false
                var shown = ""
                for await input in inputs {
                    switch input {
                    case .audio(let buffer): policy.add(buffer)
                    case .ended: policy.end()
                    case .done(let pass, .success(let words)):
                        running = false
                        policy.finish(pass, words: words)
                    case .done(_, .failure(let failure)):
                        out.yield(.failed(failure))
                        out.finish()
                        return
                    }
                    if running == false, let pass = policy.nextPass() {
                        running = true
                        passes.addTask {
                            do {
                                feed.yield(.done(pass, .success(try await transcriber.transcribe(pass.samples, sampleRate: pass.sampleRate))))
                            } catch {
                                feed.yield(.done(pass, .failure(DictationFailure("The speech model stopped: \((error as? DictationFailure)?.cause ?? error.localizedDescription)"))))
                            }
                        }
                    }
                    if policy.isComplete {
                        out.yield(.final(policy.text))
                        break
                    }
                    if policy.text != shown, policy.text.isEmpty == false {
                        shown = policy.text
                        out.yield(.partial(shown))
                    }
                }
                out.finish()
            }
        }
        out.onTermination = { _ in
            reader.cancel()
            loop.cancel()
        }
        return events
    }
}
