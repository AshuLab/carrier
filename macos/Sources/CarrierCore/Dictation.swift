import Foundation
import Observation

// Dictation (docs/specs/dictation-in-the-app.md): the boundary every recognizer sits behind and the registry that lists them. The session
// that drives one dictation is `DictationSession`, the text it writes is `TentativeText`, what the message box draws is `dictationPresentation`.

public enum RecognizerID: String, Sendable, CaseIterable { case apple, fluidAudio, whisper }

/// How a speech model gives the words while the person still speaks.
public enum PartialText: Sendable { case native, chunked, atTheEnd }

public struct SpeechModel: Identifiable, Sendable, Equatable {
    public let id: String
    public let recognizer: RecognizerID
    public let name: String
    /// nil for Apple's: the system manages them.
    public let bytes: Int64?
    /// Base codes ("es"); Apple's come from the system.
    public let languages: Set<String>
    public let detectsLanguage: Bool
    public let partial: PartialText
    public let licence: String
    public let card: URL

    public init(
        id: String, recognizer: RecognizerID, name: String, bytes: Int64?, languages: Set<String>, detectsLanguage: Bool,
        partial: PartialText, licence: String, card: URL
    ) {
        self.id = id
        self.recognizer = recognizer
        self.name = name
        self.bytes = bytes
        self.languages = languages
        self.detectsLanguage = detectsLanguage
        self.partial = partial
        self.licence = licence
        self.card = card
    }
}

public enum DictationEvent: Sendable, Equatable {
    case partial(String)
    case final(String)
    case failed(DictationFailure)
}

/// Why a dictation could not go on, in words for the person.
public struct DictationFailure: Error, Equatable, Sendable {
    public let cause: String

    public init(_ cause: String) { self.cause = cause }
}

/// What a capture heard for a moment: mono samples.
public struct AudioBuffer: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

/// The microphone, shared by every recognizer. The buffers live in memory only; `stop` ends the stream and drops them.
public protocol AudioCapture: Sendable {
    func start() throws -> AsyncStream<AudioBuffer>
    func stop()
}

/// Turns audio into text events. `prepare` loads what the model needs (it may take seconds); `recognize` listens until the audio ends,
/// then gives its last `final` (an empty one when nothing was said, never a failure) and ends its events.
public protocol Recognizer: Sendable {
    var id: RecognizerID { get }
    var models: [SpeechModel] { get }
    func prepare(_ model: SpeechModel) async throws
    func recognize(_ audio: AsyncStream<AudioBuffer>) -> AsyncStream<DictationEvent>
}

/// The recognizers a build offers: with none, the message box draws no microphone.
@MainActor @Observable public final class RecognizerRegistry {
    public static let shared = RecognizerRegistry()
    public private(set) var recognizers: [any Recognizer] = []

    public init() {}

    /// A recognizer registered again under the same id replaces the one before it.
    public func register(_ recognizer: any Recognizer) {
        recognizers.removeAll { $0.id == recognizer.id }
        recognizers.append(recognizer)
    }
}
