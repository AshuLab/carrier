import Foundation

// What the Dictation area needs from the machine (docs/specs/macos-app-as-the-base-for-a-web-front-end.md, section 2): the models take these, their tests take a fake;
// the implementations are in `Carrier/Platform` (the recognizers, the microphone, the model downloads, the local model server).

/// The microphone, shared by every recognizer. The buffers live in memory only; `stop` ends the stream and drops them.
public protocol AudioCapture: Sendable {
    func start() throws -> AsyncStream<AudioBuffer>
    func stop()
}

/// Turns audio into text events. `prepare` loads what the model needs (it may take seconds, and returns at once when it is loaded); `release` drops it; `recognize` listens until the audio ends,
/// then gives its last `final` (an empty one when nothing was said, never a failure) and ends its events.
public protocol Recognizer: Sendable {
    var id: RecognizerID { get }
    var models: [SpeechModel] { get }
    func prepare(_ model: SpeechModel) async throws
    func recognize(_ audio: AsyncStream<AudioBuffer>) -> AsyncStream<DictationEvent>
    /// Drops what `prepare` loaded; the next `prepare` loads it again. Harmless when nothing is loaded.
    func release() async
}

/// A model that turns a whole piece of audio into words with their times. The core never gives it less than 300 ms.
public protocol BatchTranscriber: Sendable {
    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> [TimedWord]
}

/// Fetches one model into the folder it is given, reporting its progress as a fraction. It stops by throwing when its task is cancelled and
/// throws a `ModelDownloadFailure` for a cause the person can be told; anything else is told as a failure with its description.
public protocol ModelDownloader: Sendable {
    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws
}

/// What Cleanup needs from a model server: the models it lists and one completion with a system message and a user message, no tools.
public protocol TextModelClient: Sendable {
    func models(of server: CleanupServer) async throws -> [String]
    func complete(server: CleanupServer, model: String, system: String, text: String, timeout: Duration) async throws -> String
}
