import Foundation
import Observation

/// The field a dictation writes into: the session reads its text and caret and puts back the text, the caret and the range that is
/// still partial. `owner` says which box it is, so only that box draws the state.
public struct DictationField {
    public let owner: String
    public let text: () -> String
    public let caret: () -> Int
    public let put: (_ text: String, _ caret: Int, _ tentative: Range<Int>?) -> Void

    public init(owner: String, text: @escaping () -> String, caret: @escaping () -> Int, put: @escaping (String, Int, Range<Int>?) -> Void) {
        self.owner = owner
        self.text = text
        self.caret = caret
        self.put = put
    }
}

/// What a dictation that ended heard, for the history: when it started, the text it wrote (a partial text on the screen included), the speech model,
/// the seconds of audio and the seconds the recognizer took after the person stopped, and how it ended. `owner` says which box it was. When the
/// box cleaned the text, `cleaned` is what replaced it and `cleanupSeconds` the time the cleanup took.
public struct DictationTake: Equatable, Sendable {
    public enum Ending: Equatable, Sendable { case stopped, cancelled, failed }

    public let owner: String?
    public let started: Date
    public let text: String
    public let model: String
    public let audio: Double
    public let transcription: Double
    public let ending: Ending
    public let cleaned: String?
    public let cleanupSeconds: Double?
    /// The audio it heard, when the history keeps it (`DictationSession.init`'s `keepAudio`).
    public var clip: AudioClip? = nil
}

/// Where the time of one dictation went, in milliseconds and with no text: from the press to the capture running, to the first audio, to the model
/// ready and to the first word shown, and from the stop to the final text. A moment that did not happen is nil.
public struct DictationTimings: Equatable, Sendable {
    public var capture: Int?
    public var firstAudio: Int?
    public var modelReady: Int?
    public var firstWord: Int?
    public var finalText: Int?

    public init(capture: Int? = nil, firstAudio: Int? = nil, modelReady: Int? = nil, firstWord: Int? = nil, finalText: Int? = nil) {
        self.capture = capture
        self.firstAudio = firstAudio
        self.modelReady = modelReady
        self.firstWord = firstWord
        self.finalText = finalText
    }

    var isEmpty: Bool { self == DictationTimings() }
}

/// What a box asks of the Cleanup (docs/adr/0030): the text the dictation added goes in, the cleaned text comes out, or it throws (a `CleanupFailure`
/// says its cause in words).
public typealias DictationCleanup = @Sendable (String) async throws -> String

/// One dictation, from the click that starts it to idle: getting ready (the recognizer loads its model), listening, transcribing
/// when the model gives its text only at the end, and cleaning when the box asked for it. A failure at any point returns to idle with its cause and keeps the text heard so far.
@MainActor @Observable public final class DictationSession {
    public enum State: Equatable, Sendable { case idle, gettingReady, listening, transcribing, cleaning }

    /// How long a recognizer has to answer after the audio ends before the dictation gives up: a floor, and a second more for each second of
    /// audio, because a model that gives its text at the end reads all of it in one pass.
    /// ponytail: a guess at the speed of a model; one slower than the audio itself still loses its text, so measure before raising it.
    public static let answerFloor = Duration.seconds(30)
    public static let answerPerAudioSecond = Duration.seconds(1)

    public private(set) var state = State.idle
    /// The box that dictates, while one does.
    public private(set) var owner: String?
    private var failure: (owner: String, cause: DictationFailure)?

    @ObservationIgnored private let capture: AudioCapture
    @ObservationIgnored private let sleep: (Duration) async throws -> Void
    @ObservationIgnored private let announce: (String) -> Void
    @ObservationIgnored private let log: (DictationFailure) -> Void
    @ObservationIgnored private let timed: (DictationTimings) -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let keepAudio: () -> Bool
    /// Told, with the owner of the box it was, each time a dictation ends: the widget of the global dictation hears its own end here.
    @ObservationIgnored public var onEnd: ((String?) -> Void)?
    /// Told each time a dictation begins to listen (the capture runs); `owner` says whose.
    @ObservationIgnored public var onListening: (() -> Void)?
    /// What the dictation that just ended heard, set before `onEnd` and `onTake` hear of it.
    @ObservationIgnored public private(set) var take: DictationTake?
    /// Told, with what it heard, each time a dictation ends: the history of the message boxes hears it here.
    @ObservationIgnored public var onTake: ((DictationTake) -> Void)?
    @ObservationIgnored private var field: DictationField?
    @ObservationIgnored private var model: SpeechModel?
    @ObservationIgnored private var cleanup: DictationCleanup?
    @ObservationIgnored private var tentative = TentativeText(caret: 0, in: "")
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    @ObservationIgnored private var stopped = false
    /// Counts the dictations, so one that already ended cannot touch the next.
    @ObservationIgnored private var generation = 0
    /// The words the final texts of this dictation added to the box, and those of the partial text on the screen.
    @ObservationIgnored private var words = 0
    @ObservationIgnored private var partialWords = 0
    /// The seconds of audio the capture gave, for the time a recognizer is given to answer after the stop.
    @ObservationIgnored private var captured = Duration.zero
    /// The samples of this dictation and their rate, gathered only when `keepAudio` said so as it started.
    @ObservationIgnored private var recording = false
    @ObservationIgnored private var samples: [Float] = []
    @ObservationIgnored private var sampleRate = 0.0
    /// What this dictation heard: the final texts, the partial one on the screen, and when it began and was stopped.
    @ObservationIgnored private var finals: [String] = []
    @ObservationIgnored private var partial = ""
    @ObservationIgnored private var began = Date.distantPast
    @ObservationIgnored private var stoppedAt: Date?
    @ObservationIgnored private var timings = DictationTimings()
    @ObservationIgnored private var cleaned: String?
    @ObservationIgnored private var cleanupSeconds: Double?
    /// A dictation asked for while another one stops: it starts when that one is idle.
    @ObservationIgnored private var queued: (recognizer: any Recognizer, model: SpeechModel, field: DictationField, cleanup: DictationCleanup?)?

    /// `announce` is told what VoiceOver should say (`dictationAnnouncement`): the start, the stop and a failure, never partial text; `log` hears
    /// every failure, with its cause only; `timed` hears where the time of each dictation went when it ends. `keepAudio` is asked as each dictation
    /// starts: when it says yes the take carries the audio.
    public init(
        capture: AudioCapture, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        announce: @escaping (String) -> Void = { _ in }, log: @escaping (DictationFailure) -> Void = { _ in },
        timed: @escaping (DictationTimings) -> Void = { _ in }, now: @escaping () -> Date = Date.init, keepAudio: @escaping () -> Bool = { false }
    ) {
        self.keepAudio = keepAudio
        self.timed = timed
        self.capture = capture
        self.sleep = sleep
        self.announce = announce
        self.log = log
        self.now = now
    }

    /// Why the last dictation of `owner` could not start or go on, until it starts another.
    public func failure(for owner: String) -> DictationFailure? { failure?.owner == owner ? failure?.cause : nil }

    /// A dictation that could not start for `owner`'s box, told and logged like any other failure.
    public func refuse(_ cause: DictationFailure, for owner: String) {
        failure = (owner, cause)
        announce(dictationAnnouncement(.failed(cause)))
        log(cause)
    }

    /// Starts a dictation at the field's caret. Only one runs at a time: while another does, it stops (keeping its text, and skipping its cleanup)
    /// and this one starts when it is idle. With a `cleanup`, the text this dictation added is replaced by the cleaned one when it ends; a failure
    /// of it, or a skip, leaves the raw text.
    public func start(recognizer: any Recognizer, model: SpeechModel, into field: DictationField, cleanup: DictationCleanup? = nil) {
        guard state == .idle else {
            queued = (recognizer, model, field, cleanup)
            if state == .cleaning { skip() } else { halt() }
            return
        }
        failure = nil
        words = 0
        partialWords = 0
        captured = .zero
        recording = keepAudio()
        samples = []
        finals = []
        partial = ""
        began = now()
        stoppedAt = nil
        timings = DictationTimings()
        cleaned = nil
        cleanupSeconds = nil
        self.field = field
        self.model = model
        self.cleanup = cleanup
        owner = field.owner
        tentative = TentativeText(caret: field.caret(), in: field.text())
        stopped = false
        state = .gettingReady
        announce(dictationAnnouncement(.gettingReady))
        generation += 1
        let mine = generation
        running = Task { await run(recognizer, model, mine) }
    }

    /// Stops listening and keeps what was heard, for whatever reason: a click, a typed key, Enter, leaving. The recognizer gives its last
    /// text and the dictation ends. A dictation waiting for this one to end is dropped.
    public func stop() {
        queued = nil
        halt()
    }

    /// `stop` for a box that leaves or is typed in: it stops its own dictation and drops its own dictation that waits, and no other's.
    /// A box that is typed in or left skips its cleanup too, since the text it would replace is no longer as the dictation left it.
    public func stop(ownedBy owner: String) {
        if queued?.field.owner == owner { queued = nil }
        guard self.owner == owner else { return }
        if state == .cleaning { skip() } else { halt() }
    }

    /// Cancels the dictation at once, in any state: the audio is dropped, nothing the recognizer says afterwards is written, and the text on the
    /// screen, a partial one included, stays as it is, as final. A model that gives its text at the end, which has shown none, adds none, and a
    /// cleanup that has not answered is given up: the raw text stays. Returns whether there was a dictation to cancel.
    @discardableResult
    public func cancel() -> Bool {
        queued = nil
        guard state != .idle else { return false }
        skip(state == .cleaning ? .stopped : .cancelled)
        return true
    }

    /// Ends the dictation at once. Skipping the cleanup keeps the raw text, which is as good as a stop; a `cancel()` before it is a cancel.
    private func skip(_ ending: DictationTake.Ending = .stopped) {
        running?.cancel()
        end(ending)
    }

    private func halt() {
        switch state {
        case .idle, .transcribing, .cleaning: return
        case .gettingReady:
            skip()
        case .listening:
            guard stopped == false else { return }
            stopped = true
            stoppedAt = now()
            capture.stop()
            if model?.partial == .atTheEnd { state = .transcribing }
            let mine = generation
            let timeout = Self.answerFloor + Self.answerPerAudioSecond * captured.components.seconds
            watchdog = Task {
                guard (try? await sleep(timeout)) != nil, Task.isCancelled == false, generation == mine else { return }
                running?.cancel()
                fail(DictationFailure("The recognizer did not answer."))
            }
        }
    }

    private func run(_ recognizer: any Recognizer, _ model: SpeechModel, _ mine: Int) async {
        do {
            try await recognizer.prepare(model)
        } catch {
            if generation == mine { fail(error) }
            return
        }
        guard generation == mine else { return }
        timings.modelReady = milliseconds(since: began)
        let audio: AsyncStream<AudioBuffer>
        do { audio = try capture.start() } catch {
            fail(error)
            return
        }
        timings.capture = milliseconds(since: began)
        state = .listening
        announce(dictationAnnouncement(.listening))
        onListening?()
        // the recognizer reads the audio through a stream that counts it
        let counted = AsyncStream<AudioBuffer> { continuation in
            let relay = Task { @MainActor in
                for await buffer in audio {
                    if timings.firstAudio == nil { timings.firstAudio = milliseconds(since: began) }
                    captured += .seconds(Double(buffer.samples.count) / buffer.sampleRate)
                    if recording {
                        samples += buffer.samples
                        sampleRate = buffer.sampleRate
                    }
                    continuation.yield(buffer)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in relay.cancel() }
        }
        for await event in recognizer.recognize(counted) {
            guard generation == mine else { return }
            if case .failed(let failure) = event {
                fail(failure)
                return
            }
            if let field, let edit = tentative.apply(event, to: field.text(), caret: field.caret()) {
                switch event {
                case .partial(let heard):
                    noteFirstWord(heard)
                    partialWords = wordCount(heard)
                    partial = heard
                case .final(let heard):
                    noteFirstWord(heard)
                    words += wordCount(heard)
                    partialWords = 0
                    partial = ""
                    finals.append(heard)
                case .failed: break
                }
                field.put(edit.text, edit.caret, tentative.range)
            }
        }
        guard generation == mine else { return }
        if let stoppedAt { timings.finalText = milliseconds(since: stoppedAt) }
        await clean(mine)
        // a cleanup that failed has told its cause, which is not a stop
        if generation == mine { end(announcing: failure == nil) }
    }

    /// Replaces the text this dictation added with the cleaned one, in the state `.cleaning`, which a skip, a failure and a text that changed meanwhile
    /// leave as it was: the raw text is never lost.
    private func clean(_ mine: Int) async {
        // the recognizer has answered: the time it was given is spent, and the cleanup has its own
        watchdog?.cancel()
        watchdog = nil
        guard let cleanup, let field else { return }
        settle()
        guard let range = tentative.written else { return }
        let ns = field.text() as NSString
        guard NSMaxRange(NSRange(location: range.lowerBound, length: range.count)) <= ns.length else { return }
        let added = ns.substring(with: NSRange(location: range.lowerBound, length: range.count))
        guard added.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        state = .cleaning
        let cleaned: String
        let cleaningFrom = now()
        do { cleaned = try await cleanup(added) } catch {
            guard generation == mine, let owner else { return }
            refuse(DictationFailure((error as? CleanupFailure)?.message ?? error.localizedDescription), for: owner)
            return
        }
        guard generation == mine else { return }
        let text = field.text() as NSString
        let place = NSRange(location: range.lowerBound, length: range.count)
        guard NSMaxRange(place) <= text.length, text.substring(with: place) == added else { return }
        // the cleanup trims, and a space that set the dictation apart from the words around it is not its text
        let raw = added.trimmingCharacters(in: .whitespacesAndNewlines), bounds = added.range(of: raw)!
        let replacement = added[..<bounds.lowerBound] + cleaned.trimmingCharacters(in: .whitespacesAndNewlines) + added[bounds.upperBound...]
        let caret = field.caret(), delta = (replacement as NSString).length - place.length
        field.put(
            text.replacingCharacters(in: place, with: String(replacement)),
            caret <= place.location ? caret : caret >= NSMaxRange(place) ? caret + delta : place.location + (replacement as NSString).length, nil
        )
        words = wordCount(cleaned)
        self.cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        cleanupSeconds = now().timeIntervalSince(cleaningFrom)
    }

    /// A partial text on the screen stays, as final, and its words count.
    private func settle() {
        guard let field else { return }
        if tentative.range != nil {
            words += partialWords
            partialWords = 0
            finals.append(partial)
            partial = ""
            tentative.close()
        }
        field.put(field.text(), field.caret(), nil)
    }

    private func noteFirstWord(_ heard: String) {
        if timings.firstWord == nil, wordCount(heard) > 0 { timings.firstWord = milliseconds(since: began) }
    }

    private func milliseconds(since start: Date) -> Int { Int((now().timeIntervalSince(start) * 1000).rounded()) }

    private func wordCount(_ heard: String) -> Int { heard.split(whereSeparator: \.isWhitespace).count }

    private func fail(_ error: Error) {
        let cause = error as? DictationFailure ?? DictationFailure(error.localizedDescription)
        if let owner { refuse(cause, for: owner) }
        end(.failed, announcing: false)
    }

    /// Back to idle: the audio is dropped, and a partial text on the screen is kept as final.
    private func end(_ ending: DictationTake.Ending = .stopped, announcing: Bool = true) {
        capture.stop()
        let modelName = model?.name ?? ""
        // the range is cleared even when the person's edit had already ended the writing
        settle()
        if announcing, state == .listening || state == .transcribing || state == .cleaning { announce(dictationAnnouncement(.stopped(words: words))) }
        watchdog?.cancel()
        watchdog = nil
        running = nil
        field = nil
        model = nil
        cleanup = nil
        if timings.isEmpty == false { timed(timings) }
        let finished = owner
        owner = nil
        generation += 1
        state = .idle
        let ended = now()
        let heard = DictationTake(
            owner: finished, started: began, text: finals.filter { $0.isEmpty == false }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines), model: modelName,
            audio: captured.inSeconds,
            transcription: stoppedAt.map { ended.timeIntervalSince($0) } ?? 0, ending: ending,
            cleaned: cleaned, cleanupSeconds: cleanupSeconds, clip: recording && samples.isEmpty == false ? AudioClip(samples: samples, sampleRate: sampleRate) : nil)
        samples = []
        take = heard
        onTake?(heard)
        onEnd?(finished)
        if let next = queued {
            queued = nil
            start(recognizer: next.recognizer, model: next.model, into: next.field, cleanup: next.cleanup)
        }
    }
}
