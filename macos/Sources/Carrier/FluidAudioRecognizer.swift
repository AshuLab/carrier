@preconcurrency import AVFoundation
import CarrierCore
import FluidAudio
import Foundation

/// FluidAudio's recognizer, on Core ML. The batch models (Parakeet TDT v3 and Ultra) keep the audio in memory while the person speaks and give
/// the text when they stop (`partial: .atTheEnd`; the core's chunking is another slice). The streaming ones (Parakeet EOU, Nemotron, Parakeet
/// Unified) decode as the audio arrives and give partial text natively. A model is loaded from `<root>/fluidaudio/<model>/` and never fetched:
/// the loaders used here do not touch FluidAudio's downloader, and its offline mode is on besides, so a damaged folder fails with its cause
/// instead of being deleted and downloaded again. Only `FluidAudioDownloader`, on the person's explicit action, goes online.
final class FluidAudioRecognizer: Recognizer, @unchecked Sendable {
    /// How a model runs, and so how it is downloaded and loaded.
    enum Engine {
        case batch(AsrModelVersion, Repo)
        case eou
        case nemotron
        case nemotronMultilingual
        case unified

        var repo: Repo {
            switch self {
            case .batch(_, let repo): repo
            case .eou: .parakeetEou320
            case .nemotron: .nemotronStreaming1120
            case .nemotronMultilingual: .nemotronMultilingual
            case .unified: .parakeetUnified
            }
        }
    }

    /// The streaming tiers are the ones of about a second: the words come soon and the models keep their accuracy. The multilingual one is the
    /// full vocabulary, since the Latin one has no Chinese or Japanese.
    static let multilingualTier = "multilingual/1120ms"
    static let unifiedConfig = UnifiedConfig(leftFrames: 70, chunkFrames: 7, rightFrames: 7)

    /// The 25 languages of the Parakeet TDT v3 card, in base codes.
    static let parakeetLanguages: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl",
        "sv", "uk",
    ]

    /// The list, from FluidAudio's `Models.md` at 0.18.3 and the models' cards; the sizes are those of the files each download brings.
    static let entries: [(model: SpeechModel, engine: Engine)] = [
        (entry("parakeet-tdt-v3", "Parakeet TDT v3", 483_000_000, parakeetLanguages, true, .atTheEnd, "CC-BY-4.0", "parakeet-tdt-0.6b-v3-coreml"), .batch(.v3, .parakeetV3)),
        (entry("parakeet-ultra", "Parakeet Ultra", 632_000_000, parakeetLanguages, true, .atTheEnd, "CC-BY-4.0", "parakeet-ultra-coreml"), .batch(.ultra, .parakeetUltra)),
        (entry("parakeet-eou-120m", "Parakeet EOU 120M", 224_000_000, ["en"], false, .native, "NVIDIA Open Model License", "parakeet-realtime-eou-120m-coreml"), .eou),
        (entry("nemotron-streaming-en", "Nemotron Streaming EN", 627_000_000, ["en"], false, .native, "NVIDIA Open Model License", "nemotron-speech-streaming-en-0.6b-coreml"), .nemotron),
        (entry("nemotron-3.5-multilingual", "Nemotron 3.5 Multilingual", 664_000_000, ["de", "en", "es", "fr", "it", "ja", "pt", "zh"], true, .native, "OpenMDW-1.1", "Nemotron-3.5-ASR-Streaming-Multilingual-0.6b-CoreML"), .nemotronMultilingual),
        // NVIDIA's licence governs these weights: the converted card says CC-BY-4.0, which NVIDIA's own card does not
        (entry("parakeet-unified-0.6b", "Parakeet Unified 0.6B", 609_000_000, ["en"], false, .native, "NVIDIA Open Model License", "parakeet-unified-en-0.6b-coreml"), .unified),
    ]

    private static func entry(
        _ id: String, _ name: String, _ bytes: Int64, _ languages: Set<String>, _ detects: Bool, _ partial: PartialText, _ licence: String, _ card: String
    ) -> SpeechModel {
        SpeechModel(
            id: "fluidaudio.\(id)", recognizer: .fluidAudio, name: name, bytes: bytes, languages: languages, detectsLanguage: detects, partial: partial,
            licence: licence, card: URL(string: "https://huggingface.co/FluidInference/\(card)")!
        )
    }

    static func engine(of model: SpeechModel) -> Engine? { entries.first { $0.model.id == model.id }?.engine }

    /// Where the files of the model are: FluidAudio keeps a repository in a folder of its own name, inside the model's folder.
    static func files(_ engine: Engine, in folder: URL) -> URL {
        let repo = folder.appending(path: engine.repo.folderName)
        if case .nemotronMultilingual = engine { return repo.appending(path: multilingualTier) }
        return repo
    }

    /// A streaming manager behind the same few closures, since the multilingual one shares no protocol with the others.
    private struct Streamer {
        let onPartial: (@escaping @Sendable (String) -> Void) async -> Void
        let setLanguage: (String) async -> Void
        let feed: (AVAudioPCMBuffer) async throws -> Void
        let finish: () async throws -> String
        let reset: () async throws -> Void
    }

    private enum Loaded {
        case batch(AsrManager)
        case streaming(Streamer)
    }

    let id = RecognizerID.fluidAudio
    let models = entries.map(\.model)
    private let root: URL
    private let preferredLanguages: [String]
    private let lock = NSLock()
    /// Kept after the first load: the model stays in memory, so only the first dictation waits for "Getting the model ready…".
    private var loaded: (id: String, model: Loaded)?
    private var chosenLanguage = automaticLanguage

    init(modelsRoot: URL, preferredLanguages: [String] = Locale.preferredLanguages) {
        root = modelsRoot
        self.preferredLanguages = preferredLanguages
        ModelHub.offlineMode = true
    }

    func prepare(_ model: SpeechModel) async throws {
        let chosen = languageChoices(for: model, macOSLanguages: preferredLanguages, saved: AppPreferences().dictationLanguage).selected
        lock.withLock { chosenLanguage = chosen }
        if lock.withLock({ loaded?.id }) == model.id { return }
        guard let engine = Self.engine(of: model) else { throw DictationFailure("\(model.name) is not a model of FluidAudio.") }
        let files = Self.files(engine, in: ModelStore.folder(in: root, for: model))
        do {
            let model = (model.id, try await Self.load(engine, from: files))
            lock.withLock { loaded = model }
        } catch {
            throw DictationFailure(
                "\(model.name) could not be loaded from its folder (\(error.localizedDescription)). Delete it on the Dictation page and download it again."
            )
        }
    }

    private static func load(_ engine: Engine, from files: URL) async throws -> Loaded {
        switch engine {
        case .batch(let version, _):
            return .batch(AsrManager(models: try AsrModels.loadLocal(from: files, version: version)))
        case .eou:
            let manager = StreamingEouAsrManager(chunkSize: .ms320)
            try await manager.loadModels(from: files)
            return .streaming(Streamer(
                onPartial: { await manager.setPartialCallback($0) }, setLanguage: { _ in },
                feed: { _ = try await manager.process(audioBuffer: $0) }, finish: { try await manager.finish() }, reset: { await manager.reset() }
            ))
        case .nemotron:
            let manager = StreamingNemotronAsrManager(requestedChunkSize: .ms1120)
            try await manager.loadModels(from: files)
            return .streaming(Streamer(
                onPartial: { await manager.setPartialCallback($0) }, setLanguage: { _ in },
                feed: { _ = try await manager.process(audioBuffer: $0) }, finish: { try await manager.finish() }, reset: { await manager.reset() }
            ))
        case .nemotronMultilingual:
            let manager = StreamingNemotronMultilingualAsrManager()
            try await manager.loadModels(from: files)
            return .streaming(Streamer(
                onPartial: { await manager.setPartialCallback($0) },
                // the model's prompts know "es" but not "zh" or "ja", which want their region
                setLanguage: { await manager.setLanguage($0 == automaticLanguage ? "auto" : ["zh": "zh-CN", "ja": "ja-JP"][$0] ?? $0) },
                feed: { _ = try await manager.process(audioBuffer: $0) }, finish: { try await manager.finish() }, reset: { await manager.reset() }
            ))
        case .unified:
            let manager = StreamingUnifiedAsrManager(config: unifiedConfig)
            try await manager.loadModels(from: files)
            return .streaming(Streamer(
                onPartial: { await manager.setPartialTranscriptCallback($0) }, setLanguage: { _ in },
                feed: { try await manager.appendAudio($0); try await manager.processBufferedAudio() }, finish: { try await manager.finish() },
                reset: { try await manager.reset() }
            ))
        }
    }

    func recognize(_ audio: AsyncStream<CarrierCore.AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let (taken, language) = lock.withLock { (loaded?.model, chosenLanguage) }
        Task {
            switch taken {
            case .batch(let manager): await Self.recognize(audio, with: manager, language: language, into: out)
            case .streaming(let streamer): await Self.recognize(audio, with: streamer, language: language, into: out)
            case nil: out.yield(.failed(DictationFailure("The speech model was not prepared.")))
            }
            out.finish()
        }
        return events
    }

    private static func recognize(
        _ audio: AsyncStream<CarrierCore.AudioBuffer>, with manager: AsrManager, language: String, into out: AsyncStream<DictationEvent>.Continuation
    ) async {
        var samples: [Float] = []
        var sampleRate = 0.0
        for await buffer in audio {
            samples += buffer.samples
            sampleRate = buffer.sampleRate
        }
        do {
            let heard = sampleRate > 0 ? try AudioConverter().resample(samples, from: sampleRate) : []
            // less than 300 ms is silence to the model, which refuses it: no speech ends in an empty final, never in a failure
            if heard.count < 4_800 {
                out.yield(.final(""))
            } else {
                var state = try TdtDecoderState(decoderLayers: await manager.decoderLayerCount)
                let result = try await manager.transcribe(heard, decoderState: &state, language: Language(rawValue: language))  // nil for Automatic
                out.yield(.final(result.text.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        } catch {
            out.yield(.failed(DictationFailure("The speech model stopped: \(error.localizedDescription)")))
        }
    }

    private static func recognize(
        _ audio: AsyncStream<CarrierCore.AudioBuffer>, with streamer: Streamer, language: String, into out: AsyncStream<DictationEvent>.Continuation
    ) async {
        let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        do {
            try await streamer.reset()
            await streamer.setLanguage(language)
            await streamer.onPartial { if $0.isEmpty == false { out.yield(.partial($0)) } }
            var converter: CaptureConverter?
            var fed = false
            for await buffer in audio {
                if converter == nil { converter = CaptureConverter(from: buffer.sampleRate, to: target) }
                guard let heard = converter?.convert(buffer) else { continue }
                try await streamer.feed(heard)
                fed = true
            }
            // no audio ends in an empty final, never in a failure
            out.yield(.final(fed ? try await streamer.finish().trimmingCharacters(in: .whitespacesAndNewlines) : ""))
        } catch {
            out.yield(.failed(DictationFailure("The speech model stopped: \(error.localizedDescription)")))
        }
    }
}

/// The only place FluidAudio goes online, on the person's click: it turns FluidAudio's offline mode off while a download runs and on again when
/// the last one ends, since the person can start several. The loads never read the flag, so a dictation is never online.
struct FluidAudioDownloader: ModelDownloader {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var running = 0

    private static func going(_ delta: Int) {
        lock.withLock {
            running += delta
            ModelHub.offlineMode = running == 0
        }
    }

    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        guard let engine = FluidAudioRecognizer.engine(of: model) else { throw DictationFailure("\(model.name) is not a model of FluidAudio.") }
        Self.going(1)
        defer { Self.going(-1) }
        // the library's callback cannot hold the port's non-escaping `progress`: its fractions cross a stream, in order, to a loop that calls it
        let (fractions, sink) = AsyncStream<Double>.makeStream()
        let work = Task {
            defer { sink.finish() }
            let report: ProgressHandler = { sink.yield($0.fractionCompleted) }
            switch engine {
            case .batch(let version, _):
                try await AsrModels.download(to: FluidAudioRecognizer.files(engine, in: folder), version: version) { report($0) }
            case .nemotronMultilingual:
                _ = try await StreamingNemotronMultilingualAsrManager.downloadVariant(languageCode: "auto", chunkMs: 1120, to: folder, progressHandler: report)
            case .unified:
                let config = FluidAudioRecognizer.unifiedConfig
                let encoder = config.family.streamingEncoderFile(precision: .int8, contextSuffix: config.contextSuffix)
                try await ModelHub.download(.parakeetUnified, to: folder, additionalModelNames: [encoder], progressHandler: report)
            case .eou, .nemotron:
                try await ModelHub.download(engine.repo, to: folder, progressHandler: report)
            }
        }
        do {
            try await withTaskCancellationHandler {
                for await fraction in fractions { await progress(fraction) }
                try await work.value
            } onCancel: { work.cancel() }
        } catch {
            throw Self.failure(error) ?? error
        }
    }

    /// What the person caused or can fix, as the table tells it; nil for anything else.
    private static func failure(_ error: Error) -> ModelDownloadFailure? {
        switch error {
        case DownloadError.downloadFailed(_, let underlying): failure(underlying)
        case DownloadError.invalidArtifact: .didNotCheck
        case let error as URLError where error.code != .cancelled: .noConnection
        case let error as CocoaError where error.code == .fileWriteOutOfSpace: .noSpace
        case let error as POSIXError where error.code == .ENOSPC: .noSpace
        default: nil
        }
    }
}
