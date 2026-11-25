import Foundation
import Observation

/// The field a dictation writes into: the session reads its text and caret and puts back the text, the caret and the range that is
/// still tentative (the firm words before it are normal text). `owner` says which box it is, so only that box draws the state.
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

/// One dictation, from the click that starts it to idle: listening (the capture runs from the press, and the audio waits for the recognizer while it loads
/// its model: `modelReady` says whether it has), getting ready (the person stopped while the model loads: the capture ended and the recognizer reads what it
/// kept once it is ready), transcribing when the model gives its text only at the end, and cleaning when the box asked for it. A failure at any point returns
/// to idle with its cause and keeps the text heard so far.
@MainActor @Observable public final class DictationSession {
    public enum State: Equatable, Sendable { case idle, gettingReady, listening, transcribing, cleaning }

    /// How long a recognizer has to answer after the audio ends before the dictation gives up: a floor, and a second more for each second of
    /// audio, because a model that gives its text at the end reads all of it in one pass.
    /// ponytail: a guess at the speed of a model; one slower than the audio itself still loses its text, so measure before raising it.
    public static let answerFloor = Duration.seconds(30)
    public static let answerPerAudioSecond = Duration.seconds(1)
    /// How long after the stop the final text of a model that gives it at the end may take before the dictation says it is transcribing: a quick one never does.
    public static let quickAnswer = Duration.milliseconds(250)

    public internal(set) var state = State.idle
    /// Whether the recognizer has loaded its model and reads the audio; false while a dictation listens to what it will read once it is.
    public internal(set) var modelReady = false
    /// Whether the final text of a dictation that is transcribing has taken longer than `quickAnswer`: only then do the box and the widget say "Transcribing…".
    public internal(set) var answerIsSlow = false
    /// The box that dictates, while one does.
    public internal(set) var owner: String?
    var failure: (owner: String, cause: DictationFailure)?

    @ObservationIgnored let capture: AudioCapture
    @ObservationIgnored let sleep: (Duration) async throws -> Void
    @ObservationIgnored let announce: (String) -> Void
    /// The language of what `announce` is told.
    @ObservationIgnored let bundle: Bundle?
    @ObservationIgnored let locale: Locale
    @ObservationIgnored private let log: (DictationFailure) -> Void
    @ObservationIgnored let timed: (DictationTimings) -> Void
    @ObservationIgnored let now: () -> Date
    @ObservationIgnored private let keepAudio: () -> Bool
    /// Told, with the owner of the box it was, each time a dictation ends: the widget of the global dictation hears its own end here.
    @ObservationIgnored public var onEnd: ((String?) -> Void)?
    /// Awaited before the recognizer prepares, so a load or a release queued ahead of this dictation (the controller's) is over by then and
    /// cannot drop what `prepare` loaded before `recognize` reads it.
    @ObservationIgnored public var beforePrepare: () async -> Void = {}
    /// Told each time a dictation begins to listen: the first audio of the capture has arrived.
    @ObservationIgnored public var onListening: (() -> Void)?
    /// What the dictation that just ended heard, set before `onEnd` and `onTake` hear of it.
    @ObservationIgnored public internal(set) var take: DictationTake?
    /// Told, with what it heard, each time a dictation ends: the history of the message boxes hears it here.
    @ObservationIgnored public var onTake: ((DictationTake) -> Void)?
    @ObservationIgnored var field: DictationField?
    @ObservationIgnored var model: SpeechModel?
    @ObservationIgnored var cleanup: DictationCleanup?
    @ObservationIgnored var tentative = TentativeText(caret: 0, in: "")
    @ObservationIgnored var running: Task<Void, Never>?
    @ObservationIgnored var watchdog: Task<Void, Never>?
    @ObservationIgnored var slowness: Task<Void, Never>?
    @ObservationIgnored var stopped = false
    /// Counts the dictations, so one that already ended cannot touch the next.
    @ObservationIgnored var generation = 0
    /// The words the final texts of this dictation added to the box, and those of the partial text on the screen.
    @ObservationIgnored var words = 0
    @ObservationIgnored var partialWords = 0
    /// The seconds of audio the capture gave, for the time a recognizer is given to answer after the stop.
    @ObservationIgnored var captured = Duration.zero
    /// The samples of this dictation and their rate, gathered only when `keepAudio` said so as it started.
    @ObservationIgnored var recording = false
    @ObservationIgnored var samples: [Float] = []
    @ObservationIgnored var sampleRate = 0.0
    /// What this dictation heard: the final texts, the partial one on the screen, and when it began and was stopped.
    @ObservationIgnored var finals: [String] = []
    @ObservationIgnored var partial = ""
    @ObservationIgnored var began = Date.distantPast
    @ObservationIgnored var stoppedAt: Date?
    @ObservationIgnored var timings = DictationTimings()
    @ObservationIgnored var cleaned: String?
    @ObservationIgnored var cleanupSeconds: Double?
    /// A dictation asked for while another one stops: it starts when that one is idle.
    @ObservationIgnored var queued: (recognizer: any Recognizer, model: SpeechModel, field: DictationField, cleanup: DictationCleanup?)?

    /// `announce` is told what VoiceOver should say (`dictationAnnouncement`): the start, the stop and a failure, never partial text; `log` hears
    /// every failure, with its cause only; `timed` hears where the time of each dictation went when it ends. `keepAudio` is asked as each dictation
    /// starts: when it says yes the take carries the audio.
    public init(
        capture: AudioCapture, sleep: ((Duration) async throws -> Void)? = nil,
        announce: @escaping (String) -> Void = { _ in }, log: @escaping (DictationFailure) -> Void = { _ in },
        timed: @escaping (DictationTimings) -> Void = { _ in }, now: @escaping () -> Date = Date.init, keepAudio: @escaping () -> Bool = { false },
        bundle: Bundle? = nil, locale: Locale = .current
    ) {
        self.keepAudio = keepAudio
        self.timed = timed
        self.capture = capture
        // the real sleep is chosen here and not as the default of the argument: an async closure literal there is compiled into every client of
        // the initialiser, and Xcode 26's debug builds can pair the body of one copy with the frame size of another and abort the test process
        self.sleep = sleep ?? { try await Task.sleep(for: $0) }
        self.announce = announce
        self.bundle = bundle
        self.locale = locale
        self.log = log
        self.now = now
    }

    /// Why the last dictation of `owner` could not start or go on, until it starts another.
    public func failure(for owner: String) -> DictationFailure? { failure?.owner == owner ? failure?.cause : nil }

    /// A dictation that could not start for `owner`'s box, told and logged like any other failure.
    public func refuse(_ cause: DictationFailure, for owner: String) {
        failure = (owner, cause)
        announce(dictationAnnouncement(.failed(cause), bundle: bundle, locale: locale))
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
        modelReady = false
        state = .gettingReady
        announce(dictationAnnouncement(.gettingReady, bundle: bundle, locale: locale))
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

    /// `stop` for a window that hides or an app that leaves: whatever is not `kept`'s stops as `stop()` stops it (a cleanup that is running
    /// goes on, the microphone being off already) and the dictation of another that waits is dropped, so none opens the microphone unseen;
    /// the dictation of `kept`, running or waiting, goes on.
    public func stop(except kept: String) {
        if queued?.field.owner != kept { queued = nil }
        guard let owner, owner != kept else { return }
        halt()
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
    func skip(_ ending: DictationTake.Ending = .stopped) {
        running?.cancel()
        end(ending)
    }

    private func halt() {
        switch state {
        case .idle, .transcribing, .cleaning: return
        case .gettingReady:
            // the capture has not started, or the person already stopped it and the model still loads
            if stopped == false { skip() }
        case .listening:
            guard stopped == false else { return }
            // a stop before the model is ready with nothing captured has nothing to read: it ends, as a release right after the press in Hold does
            if modelReady == false, captured == .zero { return skip() }
            stopped = true
            stoppedAt = now()
            capture.stop()
            // the model still loads: the recognizer reads what was captured once it is ready, and its time to answer starts then
            if modelReady == false {
                state = .gettingReady
                return
            }
            if model?.partial == .atTheEnd { transcribe() }
            waitForTheAnswer()
        }
    }
}
