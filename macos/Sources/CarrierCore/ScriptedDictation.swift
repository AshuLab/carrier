import Foundation

// The recognizer and the capture that tests (and the fixture build) drive by hand, so a whole dictation runs with no audio of the Mac and no model.

/// A capture that hears only what it is fed. `stop` ends the stream it gave and counts.
public final class ScriptedCapture: AudioCapture, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<AudioBuffer>.Continuation?
    private var starts = 0
    private var stops = 0
    private let startError: Error?

    /// `startError` makes `start` throw, as a Mac with no input device does.
    public init(startError: Error? = nil) { self.startError = startError }

    public var startCount: Int { lock.withLock { starts } }
    public var stopCount: Int { lock.withLock { stops } }
    public var isRunning: Bool { lock.withLock { continuation != nil } }

    public func start() throws -> AsyncStream<AudioBuffer> {
        if let startError { throw startError }
        let (stream, continuation) = AsyncStream<AudioBuffer>.makeStream()
        lock.withLock {
            starts += 1
            self.continuation = continuation
        }
        return stream
    }

    public func stop() {
        let ended = lock.withLock {
            stops += 1
            defer { continuation = nil }
            return continuation
        }
        ended?.finish()
    }

    /// Gives the running stream a buffer, as the microphone would.
    public func feed(_ buffer: AudioBuffer) { _ = lock.withLock { continuation }?.yield(buffer) }
}

/// A recognizer that says what it is told. `prepare` waits while `holdPrepare` is on; `say` gives an event while it listens; when the
/// audio ends it gives `atAudioEnd` and ends its events (nil leaves them open, for `say` and `finish`).
public final class ScriptedRecognizer: Recognizer, @unchecked Sendable {
    public let id: RecognizerID
    public let models: [SpeechModel]
    private let lock = NSLock()
    private var continuation: AsyncStream<DictationEvent>.Continuation?
    private var gate: AsyncStream<Void>.Continuation?
    private var held: AsyncStream<Void>?
    private let prepareError: DictationFailure?
    private let closing: [DictationEvent]?

    public init(id: RecognizerID = .apple, partial: PartialText = .native, prepareError: DictationFailure? = nil, atAudioEnd: [DictationEvent]? = nil) {
        self.id = id
        models = [
            SpeechModel(
                id: "scripted.model", recognizer: id, name: "Scripted", bytes: nil, languages: ["es"], detectsLanguage: false, partial: partial,
                licence: "None", card: URL(string: "https://github.com/AshuLab/carrier")!
            )
        ]
        self.prepareError = prepareError
        closing = atAudioEnd
    }

    /// The next `prepare` waits for `releasePrepare`.
    public func holdPrepare() {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        lock.withLock {
            gate = continuation
            held = stream
        }
    }

    public func releasePrepare() { lock.withLock { gate }?.finish() }

    public func say(_ event: DictationEvent) { _ = lock.withLock { continuation }?.yield(event) }

    /// Ends the events, as a recognizer does once it has said its last.
    public func finish() { lock.withLock { continuation }?.finish() }

    public func prepare(_ model: SpeechModel) async throws {
        let waiting = lock.withLock { () -> AsyncStream<Void>? in
            defer { held = nil }
            return held
        }
        if let waiting { for await _ in waiting {} }
        if let prepareError { throw prepareError }
    }

    public func recognize(_ audio: AsyncStream<AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, continuation) = AsyncStream<DictationEvent>.makeStream()
        lock.withLock { self.continuation = continuation }
        if let closing {
            Task {
                for await _ in audio {}
                closing.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }
        return events
    }
}
