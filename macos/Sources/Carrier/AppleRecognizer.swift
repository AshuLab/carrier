import AVFoundation
import CarrierCore
import Foundation
import Speech

/// Apple's recognizer, over SpeechAnalyzer: the system keeps its models and fetches the assets of a language by itself, so there is
/// nothing to download here, and it gives its volatile results as native partial text. It takes one language: the first language of
/// macOS that it supports, until the Dictation page lets a person choose.
final class AppleRecognizer: Recognizer, @unchecked Sendable {
    static let modelID = "apple.speech-analyzer"

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
        var locale: Locale?
        for language in preferredLanguages where locale == nil {
            locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
        }
        guard let locale else { throw DictationFailure("Apple's speech recognition does not support any language of this Mac.") }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // the system fetches the assets of the language when it has not: this is what "Getting the model ready…" waits for
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) { try await request.downloadAndInstall() }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]))
        lock.withLock { prepared = (transcriber, analyzer) }
    }

    func recognize(_ audio: AsyncStream<CarrierCore.AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let taken = lock.withLock { () -> (transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer)? in
            defer { prepared = nil }
            return prepared
        }
        guard let (transcriber, analyzer) = taken else {
            out.yield(.failed(DictationFailure("Apple's recognizer was not prepared.")))
            out.finish()
            return events
        }
        Task {
            do {
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                    throw DictationFailure("Apple's speech recognition has no audio format for this Mac.")
                }
                let (inputs, input) = AsyncStream<AnalyzerInput>.makeStream()
                let heard = Task { () -> String in
                    // a final result closes a stretch of speech; the volatile ones that follow are the words still being heard
                    var settled = ""
                    do {
                        for try await result in transcriber.results {
                            let words = String(result.text.characters)
                            if result.isFinal { settled += words }
                            out.yield(.partial((settled + (result.isFinal ? "" : words)).trimmingCharacters(in: .whitespaces)))
                        }
                    } catch is CancellationError {}  // what cancelAndFinishNow ends the results with
                    return settled.trimmingCharacters(in: .whitespaces)
                }
                try await analyzer.start(inputSequence: inputs)
                var converter: AudioConverter?
                var fed = false
                for await buffer in audio {
                    if converter == nil { converter = AudioConverter(from: buffer.sampleRate, to: format) }
                    if let converted = converter?.convert(buffer) {
                        input.yield(AnalyzerInput(buffer: converted))
                        fed = true
                    }
                }
                input.finish()
                // no audio at all ends in an empty final, not in the failure the analyzer would raise
                if fed { try await analyzer.finalizeAndFinishThroughEndOfInput() } else { await analyzer.cancelAndFinishNow() }
                out.yield(.final(try await heard.value))
            } catch {
                out.yield(.failed(error as? DictationFailure ?? DictationFailure("Apple's speech recognition stopped: \(error.localizedDescription)")))
            }
            out.finish()
        }
        return events
    }
}

/// Puts the capture's mono Float samples in the format the analyzer asks for.
private final class AudioConverter {
    private let source: AVAudioFormat
    private let target: AVAudioFormat
    private let converter: AVAudioConverter

    init?(from sampleRate: Double, to target: AVAudioFormat) {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: source, to: target) else { return nil }
        (self.source, self.target, self.converter) = (source, target, converter)
    }

    func convert(_ heard: CarrierCore.AudioBuffer) -> AVAudioPCMBuffer? {
        guard heard.samples.isEmpty == false, let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(heard.samples.count)),
              let channel = input.floatChannelData?[0] else { return nil }
        heard.samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: heard.samples.count) }
        input.frameLength = AVAudioFrameCount(heard.samples.count)
        let capacity = AVAudioFrameCount(Double(heard.samples.count) * target.sampleRate / source.sampleRate) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var consumed = false
        var failure: NSError?
        converter.convert(to: output, error: &failure) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return input
        }
        return failure == nil && output.frameLength > 0 ? output : nil
    }
}
