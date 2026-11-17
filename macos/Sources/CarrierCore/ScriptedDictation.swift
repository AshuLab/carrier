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
    private var events: AsyncStream<DictationEvent>?
    private var gate: AsyncStream<Void>.Continuation?
    private var held: AsyncStream<Void>?
    private let prepareError: DictationFailure?
    private let closing: [DictationEvent]?
    private var releases = 0
    private var prepares = 0
    private var buffers: [AudioBuffer] = []

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

    /// An event said before `recognize` is called (the model is still loading) waits and comes first.
    public func say(_ event: DictationEvent) { _ = lock.withLock { channel() }.yield(event) }

    /// Ends the events, as a recognizer does once it has said its last.
    public func finish() { lock.withLock { channel() }.finish() }

    /// The events of the dictation that listens, or that will: made by the first `say` or `finish`, or by `recognize` when none waits. Call with the lock held.
    private func channel() -> AsyncStream<DictationEvent>.Continuation {
        if let continuation { return continuation }
        let (events, continuation) = AsyncStream<DictationEvent>.makeStream()
        self.events = events
        self.continuation = continuation
        return continuation
    }

    public func prepare(_ model: SpeechModel) async throws {
        lock.withLock { prepares += 1 }
        let waiting = lock.withLock { () -> AsyncStream<Void>? in
            defer { held = nil }
            return held
        }
        if let waiting { for await _ in waiting {} }
        if let prepareError { throw prepareError }
    }

    /// How many times `prepare` and `release` were called.
    public var prepareCount: Int { lock.withLock { prepares } }
    public var releaseCount: Int { lock.withLock { releases } }
    /// The audio `recognize` has read, in the order it came.
    public var heard: [AudioBuffer] { lock.withLock { buffers } }

    public func release() async { lock.withLock { releases += 1 } }

    public func recognize(_ audio: AsyncStream<AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, continuation) = lock.withLock { () -> (AsyncStream<DictationEvent>, AsyncStream<DictationEvent>.Continuation) in
            // a dictation that already took its events leaves the next one its own
            if events == nil { continuation = nil }
            let made = channel()
            defer { events = nil }
            return (events!, made)
        }
        Task {
            for await buffer in audio { lock.withLock { buffers.append(buffer) } }
            guard let closing else { return }
            closing.forEach { continuation.yield($0) }
            continuation.finish()
        }
        return events
    }
}
