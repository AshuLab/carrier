import AVFoundation
import CarrierCore
import Foundation
import Speech

/// Apple's recognizer, over SpeechAnalyzer: the system keeps its models and fetches the assets of a language by itself, so there is
/// nothing to download here, and it gives its volatile results as native partial text. It takes one language: the one chosen on the Dictation
/// page, which starts on the first language of macOS that it supports.
final class AppleRecognizer: Recognizer, @unchecked Sendable {
    static let modelID = "apple.speech-analyzer"
    /// Buffers in a row that the conversion may drop (about a second and a half of capture) before the dictation fails: a broken conversion
    /// would else end in an empty "nothing said".
    static let droppedLimit = 20

    let id = RecognizerID.apple
    let models: [SpeechModel]
    private let preferredLanguages: [String]
    private let lock = NSLock()
    private var prepared: (transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer)?

    /// Asks the system which languages it supports, so a recognizer exists only on a Mac where SpeechTranscriber does.
    static func make(preferredLanguages: [String] = Locale.preferredLanguages) async -> AppleRecognizer? {
        guard SpeechTranscriber.isAvailable else { return nil }
        let languages = Set(await SpeechTranscriber.supportedLocales.compactMap { $0.language.languageCode?.identifier })
        return AppleRecognizer(languages: languages, preferredLanguages: preferredLanguages)
    }

    init(languages: Set<String>, preferredLanguages: [String]) {
        self.preferredLanguages = preferredLanguages
        models = [
            SpeechModel(
                id: Self.modelID, recognizer: .apple, name: "Apple", bytes: nil, languages: languages, detectsLanguage: false, partial: .native,
                licence: "System", card: URL(string: "https://developer.apple.com/documentation/speech/speechanalyzer")!
            )
        ]
    }

    func prepare(_ model: SpeechModel) async throws {
        // the language the page chose, or the first of macOS that Apple's supports; a regional variant of macOS's own is tried first
        let chosen = languageChoices(for: model, macOSLanguages: preferredLanguages, saved: AppPreferences().dictationLanguage).selected
        var locale: Locale?
        for language in preferredLanguages.filter({ baseLanguage($0) == chosen }) + [chosen] where locale == nil && chosen.isEmpty == false {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
        }
        guard let locale else { throw DictationFailure(.appleHasNoLanguage) }
        // the progressive preset without `fastResults`, which trades accuracy for speed
        var preset = SpeechTranscriber.Preset.progressiveTranscription
        preset.reportingOptions.remove(.fastResults)
        let transcriber = SpeechTranscriber(locale: locale, preset: preset)
        // the system fetches the assets of the language when it has not: this is what "Getting the model ready…" waits for
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
        // the system keeps the model loaded while it is ready, and `release` lets it go
        let analyzer = SpeechAnalyzer(modules: [transcriber], options: SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime))
        try await analyzer.prepareToAnalyze(in: await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]))
        lock.withLock { prepared = (transcriber, analyzer) }
    }

    func release() async {
        lock.withLock { prepared = nil }
        await SpeechModels.endRetention()
    }

    func recognize(_ audio: AsyncStream<CarrierCore.AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let taken = lock.withLock { () -> (transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer)? in
            defer { prepared = nil }
            return prepared
        }
        guard let (transcriber, analyzer) = taken else {
            out.yield(.failed(DictationFailure(.appleNotPrepared)))
            out.finish()
            return events
        }
        Task {
            let (inputs, input) = AsyncStream<AnalyzerInput>.makeStream()
            var heard: Task<String, Error>?
            do {
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                    throw DictationFailure(.appleHasNoAudioFormat)
                }
                let results = Task { () -> String in
                    // a final result closes a stretch of speech; the volatile ones that follow are the words still being heard
                    var settled = ""
                    do {
                        for try await result in transcriber.results {
                            let words = String(result.text.characters)
                            if result.isFinal { settled += words }
                            out.yield(Self.partial(settled: settled, volatile: result.isFinal ? "" : words))
                        }
                    } catch is CancellationError {}  // what cancelAndFinishNow ends the results with
                    return settled.trimmingCharacters(in: .whitespaces)
                }
                heard = results
                try await analyzer.start(inputSequence: inputs)
                let fed = try await Self.feed(audio, to: format) { input.yield(AnalyzerInput(buffer: $0)) }
                input.finish()
                // no audio at all ends in an empty final, not in the failure the analyzer would raise
                if fed { try await analyzer.finalizeAndFinishThroughEndOfInput() } else { await analyzer.cancelAndFinishNow() }
                out.yield(.final(try await results.value))
            } catch {
                // nothing is left listening to the results or holding the analyzer
                heard?.cancel()
                input.finish()
                await analyzer.cancelAndFinishNow()
                out.yield(.failed(error as? DictationFailure ?? DictationFailure(.appleStopped(error.localizedDescription))))
            }
            out.finish()
        }
        return events
    }

    /// The words so far: the final results are firm and the volatile ones tentative. The whitespace between them ends the firm part, so the
    /// tentative words begin with a word, and the text has none at either end.
    static func partial(settled: String, volatile: String) -> DictationEvent {
        let firm = String(settled.drop(while: \.isWhitespace)), words = volatile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard words.isEmpty == false else { return .partial(firm: firm.trimmingCharacters(in: .whitespacesAndNewlines), tentative: "") }
        return .partial(firm: firm + String(volatile.prefix(while: \.isWhitespace)), tentative: words)
    }

    /// The capture's buffers in the analyzer's format; whether any was fed. A conversion that drops `droppedLimit` buffers in a row is a failure.
    static func feed(_ audio: AsyncStream<CarrierCore.AudioBuffer>, to format: AVAudioFormat, deliver: (AVAudioPCMBuffer) -> Void) async throws -> Bool {
        var converter: CaptureConverter?
        var fed = false
        var dropped = 0
        for await buffer in audio where buffer.samples.isEmpty == false {
            if converter == nil { converter = CaptureConverter(from: buffer.sampleRate, to: format) }
            guard let converted = converter?.convert(buffer) else {
                dropped += 1
                guard dropped < droppedLimit else { throw DictationFailure(.appleCouldNotConvert) }
                continue
            }
            dropped = 0
            deliver(converted)
            fed = true
        }
        return fed
    }
}
