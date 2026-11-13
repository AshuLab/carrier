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

/// One dictation, from the click that starts it to idle: getting ready (the recognizer loads its model), listening, and transcribing
/// when the model gives its text only at the end. A failure at any point returns to idle with its cause and keeps the text heard so far.
@MainActor @Observable public final class DictationSession {
    public enum State: Equatable, Sendable { case idle, gettingReady, listening, transcribing }

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
    @ObservationIgnored private var field: DictationField?
    @ObservationIgnored private var model: SpeechModel?
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
    /// A dictation asked for while another one stops: it starts when that one is idle.
    @ObservationIgnored private var queued: (recognizer: any Recognizer, model: SpeechModel, field: DictationField)?

    /// `announce` is told what VoiceOver should say (`dictationAnnouncement`): the start, the stop and a failure, never partial text; `log` hears
    /// every failure, with its cause only.
    public init(
        capture: AudioCapture, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        announce: @escaping (String) -> Void = { _ in }, log: @escaping (DictationFailure) -> Void = { _ in }
    ) {
        self.capture = capture
        self.sleep = sleep
        self.announce = announce
        self.log = log
    }

    /// Why the last dictation of `owner` could not start or go on, until it starts another.
    public func failure(for owner: String) -> DictationFailure? { failure?.owner == owner ? failure?.cause : nil }

    /// A dictation that could not start for `owner`'s box, told and logged like any other failure.
    public func refuse(_ cause: DictationFailure, for owner: String) {
        failure = (owner, cause)
        announce(dictationAnnouncement(.failed(cause)))
        log(cause)
    }

    /// Starts a dictation at the field's caret. Only one runs at a time: while another does, it stops (keeping its text) and this one
    /// starts when it is idle.
    public func start(recognizer: any Recognizer, model: SpeechModel, into field: DictationField) {
        guard state == .idle else {
            queued = (recognizer, model, field)
            halt()
            return
        }
        failure = nil
        words = 0
        partialWords = 0
        captured = .zero
        self.field = field
        self.model = model
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
    public func stop(ownedBy owner: String) {
        if queued?.field.owner == owner { queued = nil }
        if self.owner == owner { halt() }
    }

    /// Cancels the dictation at once, in any state: the audio is dropped, nothing the recognizer says afterwards is written, and the text on the
    /// screen, a partial one included, stays as it is, as final. A model that gives its text at the end, which has shown none, adds none.
    /// Returns whether there was a dictation to cancel.
    @discardableResult
    public func cancel() -> Bool {
        queued = nil
        guard state != .idle else { return false }
        running?.cancel()
        end()
        return true
    }

    private func halt() {
        switch state {
        case .idle, .transcribing: return
        case .gettingReady:
            running?.cancel()
            end()
        case .listening:
            guard stopped == false else { return }
            stopped = true
            capture.stop()
            if model?.partial == .atTheEnd { state = .transcribing }
            let mine = generation
            let timeout = Self.answerFloor + Self.answerPerAudioSecond * captured.components.seconds
            watchdog = Task {
                guard (try? await sleep(timeout)) != nil, generation == mine else { return }
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
        let audio: AsyncStream<AudioBuffer>
        do { audio = try capture.start() } catch {
            fail(error)
            return
        }
        state = .listening
        announce(dictationAnnouncement(.listening))
        // the recognizer reads the audio through a stream that counts it
        let counted = AsyncStream<AudioBuffer> { continuation in
            let relay = Task { @MainActor in
                for await buffer in audio {
                    captured += .seconds(Double(buffer.samples.count) / buffer.sampleRate)
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
                case .partial(let heard): partialWords = wordCount(heard)
                case .final(let heard):
                    words += wordCount(heard)
                    partialWords = 0
                case .failed: break
                }
                field.put(edit.text, edit.caret, tentative.range)
            }
        }
        if generation == mine { end() }
    }

    private func wordCount(_ heard: String) -> Int { heard.split(whereSeparator: \.isWhitespace).count }

    private func fail(_ error: Error) {
        let cause = error as? DictationFailure ?? DictationFailure(error.localizedDescription)
        if let owner { refuse(cause, for: owner) }
        end(announcing: false)
    }

    /// Back to idle: the audio is dropped, and a partial text on the screen is kept as final.
    private func end(announcing: Bool = true) {
        capture.stop()
        // a partial text on the screen stays, so its words count; the range is cleared even when the person's edit had already ended the writing
        if let field {
            if tentative.range != nil {
                words += partialWords
                tentative.close()
            }
            field.put(field.text(), field.caret(), nil)
        }
        if announcing, state == .listening || state == .transcribing { announce(dictationAnnouncement(.stopped(words: words))) }
        watchdog?.cancel()
        watchdog = nil
        running = nil
        field = nil
        model = nil
        owner = nil
        generation += 1
        state = .idle
        if let next = queued {
            queued = nil
            start(recognizer: next.recognizer, model: next.model, into: next.field)
        }
    }
}
