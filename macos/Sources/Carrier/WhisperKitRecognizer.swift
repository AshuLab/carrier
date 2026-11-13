import CarrierCore
import FluidAudio
import Foundation
import WhisperKit

/// WhisperKit's recognizer, Whisper on Core ML. Whisper goes through WhisperKit's plain transcription and the core's chunking
/// (`ChunkedRecognizer`), not through WhisperKit's streaming transcriber. By the rule of the spike (docs/research/dictation-chunked-partials.md)
/// a model gets partial text by chunks only when it is fast enough (one pass over 10 s at a real-time factor of 0.05 or less) and steady
/// enough (at most 10% of the words shown rewritten far back): none of the four passes both, so each gives its text when the person stops.
/// A model is loaded from `<root>/whisper/<model>/` and never fetched: the model's files are read from a folder, and the tokenizer, which
/// WhisperKit would otherwise download from the Hub when it cannot find it or fails to read it, is loaded here first, so a damaged one fails with
/// its cause and nothing goes online. Only `WhisperKitDownloader`, on the
/// person's explicit action, goes online.
final class WhisperKitRecognizer: Recognizer, @unchecked Sendable {
    struct Entry {
        let model: SpeechModel
        /// The folder of the model in the `whisperkit-coreml` repository.
        let variant: String
        /// The Hub repository of the model's tokenizer, which the download puts next to the model.
        let tokenizer: String
    }

    /// The 99 languages of Whisper, in base codes: WhisperKit's list without Cantonese, which only the large models of OpenAI know.
    static let languages = Constants.languageCodes.subtracting(["yue"])

    /// The sizes are those of the files each download brings (the model's folder and its tokenizer).
    static let entries: [Entry] = [
        entry("tiny", "Whisper Tiny", 79_000_000, "openai_whisper-tiny", "openai/whisper-tiny"),
        entry("base", "Whisper Base", 149_000_000, "openai_whisper-base", "openai/whisper-base"),
        entry("small", "Whisper Small", 489_000_000, "openai_whisper-small", "openai/whisper-small"),
        entry(
            "large-v3-turbo", "Whisper Large v3 Turbo", 648_000_000, "openai_whisper-large-v3-v20240930_turbo_632MB", "openai/whisper-large-v3"
        ),
    ]

    private static func entry(_ id: String, _ name: String, _ bytes: Int64, _ variant: String, _ tokenizer: String) -> Entry {
        let model = SpeechModel(
            id: "whisper.\(id)", recognizer: .whisper, name: name, bytes: bytes, languages: languages, detectsLanguage: true, partial: .atTheEnd,
            licence: "MIT", card: URL(string: "https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/\(variant)")!
        )
        return Entry(model: model, variant: variant, tokenizer: tokenizer)
    }

    static func entry(of model: SpeechModel) -> Entry? { entries.first { $0.model.id == model.id } }

    /// Where the files of the model are: WhisperKit's downloader keeps a repository's folders under `models/<repository>` of its download base,
    /// which is the model's folder.
    static func files(_ entry: Entry, in folder: URL) -> URL {
        folder.appending(path: "models/argmaxinc/whisperkit-coreml").appending(path: entry.variant)
    }

    /// The tokenizer's folder, where the loader of the library looks first: under `models/<repository>` of the model's folder.
    static func tokenizerFiles(_ entry: Entry, in folder: URL) -> URL { folder.appending(path: "models").appending(path: entry.tokenizer) }

    /// Where the Hub is, always: the library would read HF_ENDPOINT from the environment the app was launched with.
    static let hub = "https://huggingface.co"
    /// An empty token makes the library skip the Authorization header, where nil makes it read HF_TOKEN from the environment.
    static let noToken = ""

    /// Loads the tokenizer the way the library does from a folder (its `tokenizer.json` and `tokenizer_config.json` must parse and name a
    /// tokenizer it knows), and throws what is wrong with it. The library catches that failure and fetches the tokenizer from the Hub instead.
    static func checkTokenizer(_ entry: Entry, in folder: URL) async throws {
        let files = tokenizerFiles(entry, in: folder)
        for name in ["tokenizer.json", "tokenizer_config.json"] {
            let file = files.appending(path: name)
            guard FileManager.default.fileExists(atPath: file.path) else { throw WhisperError.tokenizerUnavailable("Tokenizer file not found at \(file.path)") }
        }
        do {
            _ = try await AutoTokenizerWrapper.from(modelFolder: files, hubApi: HubApiWrapper(downloadBase: folder, hfToken: noToken, endpoint: hub))
        } catch {
            throw WhisperError.tokenizerUnavailable("The tokenizer in \(files.path) is damaged: \(error.localizedDescription)")
        }
    }

    let id = RecognizerID.whisper
    let models = entries.map(\.model)
    private let root: URL
    private let preferredLanguages: [String]
    private let lock = NSLock()
    /// Kept after the first load: the model stays in memory, so only the first dictation waits for "Getting the model ready…".
    private var loaded: (id: String, kit: WhisperKit)?
    private var chosenLanguage = automaticLanguage

    init(modelsRoot: URL, preferredLanguages: [String] = Locale.preferredLanguages) {
        root = modelsRoot
        self.preferredLanguages = preferredLanguages
    }

    func prepare(_ model: SpeechModel) async throws {
        let chosen = languageChoices(for: model, macOSLanguages: preferredLanguages, saved: AppPreferences().dictationLanguage).selected
        lock.withLock { chosenLanguage = chosen }
        if lock.withLock({ loaded?.id }) == model.id { return }
        guard let entry = Self.entry(of: model) else { throw DictationFailure("\(model.name) is not a model of WhisperKit.") }
        let folder = ModelStore.folder(in: root, for: model)
        do {
            // without a tokenizer it can read, the library would go and fetch one from the Hub
            try await Self.checkTokenizer(entry, in: folder)
            let config = WhisperKitConfig(
                modelFolder: Self.files(entry, in: folder).path, tokenizerFolder: folder, verbose: false, logLevel: .none, prewarm: false, load: true,
                download: false
            )
            let kit = try await WhisperKit(config)
            lock.withLock { loaded = (model.id, kit) }
        } catch {
            throw DictationFailure(
                "\(model.name) could not be loaded from its folder (\(error.localizedDescription)). Delete it on the Dictation page and download it again."
            )
        }
    }

    func recognize(_ audio: AsyncStream<CarrierCore.AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let (kit, language, partial) = lock.withLock { (loaded?.kit, chosenLanguage, Self.entries.first { $0.model.id == loaded?.id }?.model.partial) }
        Task {
            if let kit {
                let batch = ChunkedRecognizer(WhisperTranscriber(kit: kit, language: language), partials: partial == .chunked)
                for await event in batch.recognize(audio) { out.yield(event) }
            } else {
                out.yield(.failed(DictationFailure("The speech model was not prepared.")))
            }
            out.finish()
        }
        return events
    }
}

/// One pass of Whisper over the audio so far, as the words the core's chunking works with.
private struct WhisperTranscriber: BatchTranscriber, @unchecked Sendable {
    let kit: WhisperKit
    let language: String

    func transcribe(_ samples: [Float], sampleRate: Double) async throws -> [TimedWord] {
        let heard = try AudioConverter().resample(samples, from: sampleRate)
        let automatic = language == automaticLanguage
        let options = DecodingOptions(language: automatic ? nil : language, detectLanguage: automatic, wordTimestamps: true)
        let results = try await kit.transcribe(audioArray: heard, decodeOptions: options)
        return results.flatMap(\.allWords).compactMap { word in
            let text = word.word.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : TimedWord(text, start: Double(word.start), end: Double(word.end))
        }
    }
}

/// The only place WhisperKit goes online, on the person's click: the model's folder of the `whisperkit-coreml` repository, then the tokenizer,
/// both into the model's folder.
struct WhisperKitDownloader: CarrierCore.ModelDownloader {
    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        guard let entry = WhisperKitRecognizer.entry(of: model) else { throw DictationFailure("\(model.name) is not a model of WhisperKit.") }
        // the library's callback cannot hold the port's non-escaping `progress`: its fractions cross a stream, in order, to a loop that calls it
        let (fractions, sink) = AsyncStream<Double>.makeStream()
        let work = Task {
            defer { sink.finish() }
            // the model is most of the bytes: the tokenizer, which comes after, keeps the bar short of the end
            _ = try await WhisperKit.download(
                variant: entry.variant, downloadBase: folder, token: WhisperKitRecognizer.noToken, endpoint: WhisperKitRecognizer.hub
            ) { sink.yield(min($0.fractionCompleted, 0.99)) }
            let hub = HubApiWrapper(downloadBase: folder, hfToken: WhisperKitRecognizer.noToken, endpoint: WhisperKitRecognizer.hub)
            _ = try await AutoTokenizerWrapper.from(pretrained: entry.tokenizer, hubApi: hub)
        }
        do {
            try await withTaskCancellationHandler {
                for await fraction in fractions { await progress(fraction) }
                try await work.value
            } onCancel: { work.cancel() }
        } catch {
            throw ModelDownloadFailure(error) ?? error
        }
    }
}
