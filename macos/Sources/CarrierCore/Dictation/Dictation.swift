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
    /// `firm` will not change while the person speaks; `tentative` follows it and may. The text is `firm` then `tentative` as they are, so the
    /// space that sets them apart ends `firm` and `tentative` begins with a word.
    case partial(firm: String, tentative: String)
    case final(String)
    case failed(DictationFailure)

    /// A partial whose text only grows (the streaming models'): every word but the last is firm, since the last may still grow by a piece of a word.
    public static func growing(_ text: String) -> DictationEvent {
        guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).split(whereSeparator: \.isWhitespace).last,
            let range = text.range(of: last, options: .backwards)
        else { return .partial(firm: "", tentative: text) }
        return .partial(firm: String(text[..<range.lowerBound]), tentative: String(text[range.lowerBound...]))
    }
}

/// Why a dictation could not go on, in words for the person. `cause` is the English words, which `dictation.log` keeps and failures compare by; `shown` says the
/// reason in the language of the app. A cause that is a system's own words (an `Error`'s description) has no reason and is shown as it is.
public struct DictationFailure: Error, Equatable, Sendable {
    public let cause: String
    public let reason: Reason?

    public init(_ cause: String) {
        self.cause = cause
        reason = nil
    }

    public init(_ reason: Reason) {
        cause = reason.words(bundle: Copy.bundle("en"), locale: Locale(identifier: "en_US"))
        self.reason = reason
    }

    /// Two failures are the same when they say the same in English: the reason is only how it is said in another language.
    public static func == (left: DictationFailure, right: DictationFailure) -> Bool { left.cause == right.cause }

    public func shown(bundle: Bundle? = nil, locale: Locale = .current) -> String { reason?.words(bundle: bundle, locale: locale) ?? cause }

    /// What the app itself says went wrong; the argument of a case is a name or a system's description, which is not translated.
    public enum Reason: Equatable, Sendable {
        case recognizerSilent
        case modelNotReady
        case microphoneBlocked
        case noSpeechModel
        case speechModelStopped(String)
        case cleanup(CleanupFailure)
        case notAFluidAudioModel(String)
        case notAWhisperKitModel(String)
        case modelCouldNotLoad(model: String, detail: String)
        case modelNotPrepared
        case noAudioInput
        case microphoneCouldNotStart(String)
        case appleHasNoLanguage
        case appleNotPrepared
        case appleHasNoAudioFormat
        case appleStopped(String)
        case appleCouldNotConvert
        case cannotDownload(String)
        case fixtureNoMicrophone

        public func words(bundle: Bundle? = nil, locale: Locale = .current) -> String {
            switch self {
            case .recognizerSilent: Copy.dictationFailRecognizerSilent(bundle: bundle, locale: locale)
            case .modelNotReady: Copy.dictationFailModelNotReady(bundle: bundle, locale: locale)
            case .microphoneBlocked: Copy.dictationFailMicrophoneBlocked(bundle: bundle, locale: locale)
            case .noSpeechModel: Copy.dictationFailNoSpeechModel(bundle: bundle, locale: locale)
            case .speechModelStopped(let detail): Copy.dictationFailSpeechModelStopped(detail: detail, bundle: bundle, locale: locale)
            case .cleanup(let failure): failure.message(bundle: bundle, locale: locale)
            case .notAFluidAudioModel(let model): Copy.dictationFailNotFluidAudio(model: model, bundle: bundle, locale: locale)
            case .notAWhisperKitModel(let model): Copy.dictationFailNotWhisperKit(model: model, bundle: bundle, locale: locale)
            case .modelCouldNotLoad(let model, let detail): Copy.dictationFailModelCouldNotLoad(model: model, detail: detail, bundle: bundle, locale: locale)
            case .modelNotPrepared: Copy.dictationFailModelNotPrepared(bundle: bundle, locale: locale)
            case .noAudioInput: Copy.dictationFailNoAudioInput(bundle: bundle, locale: locale)
            case .microphoneCouldNotStart(let detail): Copy.dictationFailMicrophoneCouldNotStart(detail: detail, bundle: bundle, locale: locale)
            case .appleHasNoLanguage: Copy.dictationFailAppleNoLanguage(bundle: bundle, locale: locale)
            case .appleNotPrepared: Copy.dictationFailAppleNotPrepared(bundle: bundle, locale: locale)
            case .appleHasNoAudioFormat: Copy.dictationFailAppleNoAudioFormat(bundle: bundle, locale: locale)
            case .appleStopped(let detail): Copy.dictationFailAppleStopped(detail: detail, bundle: bundle, locale: locale)
            case .appleCouldNotConvert: Copy.dictationFailAppleCouldNotConvert(bundle: bundle, locale: locale)
            case .cannotDownload(let model): Copy.dictationFailCannotDownload(model: model, bundle: bundle, locale: locale)
            case .fixtureNoMicrophone: Copy.dictationFailFixtureNoMicrophone(bundle: bundle, locale: locale)
            }
        }
    }
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
