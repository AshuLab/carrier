import CarrierCore
import FluidAudio
import Foundation

/// FluidAudio's recognizer, with Parakeet TDT v3 on Core ML: it keeps the audio in memory while the person speaks and gives the text when they
/// stop (`partial: .atTheEnd`; the core's chunking is another slice). The model is loaded from `<root>/fluidaudio/<model>/` and never fetched:
/// `AsrModels.loadLocal` does not touch FluidAudio's downloader, and its offline mode is on besides, so a damaged folder fails with its
/// cause instead of being deleted and downloaded again. Only `FluidAudioDownloader`, on the person's explicit action, goes online.
final class FluidAudioRecognizer: Recognizer, @unchecked Sendable {
    static let parakeetID = "fluidaudio.parakeet-tdt-v3"

    /// The 25 languages of the model card, in base codes.
    static let parakeetLanguages: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl",
        "sv", "uk",
    ]

    let id = RecognizerID.fluidAudio
    let models = [
        SpeechModel(
            id: parakeetID, recognizer: .fluidAudio, name: "Parakeet TDT v3", bytes: 483_000_000, languages: parakeetLanguages, detectsLanguage: true,
            partial: .atTheEnd, licence: "CC-BY-4.0", card: URL(string: "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")!
        )
    ]
    private let root: URL
    private let preferredLanguages: [String]
    private let lock = NSLock()
    /// Kept after the first load: the model stays in memory, so only the first dictation waits for "Getting the model ready…".
    private var loaded: (id: String, manager: AsrManager)?
    private var language: Language?

    init(modelsRoot: URL, preferredLanguages: [String] = Locale.preferredLanguages) {
        root = modelsRoot
        self.preferredLanguages = preferredLanguages
        ModelHub.offlineMode = true
    }

    /// Where the files of the model are: FluidAudio keeps a repository in a folder of its own name, inside the model's folder.
    static func files(in folder: URL) -> URL { folder.appending(path: Repo.parakeetV3.folderName) }

    func prepare(_ model: SpeechModel) async throws {
        let chosen = languageChoices(for: model, macOSLanguages: preferredLanguages, saved: AppPreferences().dictationLanguage).selected
        lock.withLock { language = Language(rawValue: chosen) }  // nil for Automatic
        if lock.withLock({ loaded?.id }) == model.id { return }
        let files = Self.files(in: ModelStore.folder(in: root, for: model))
        do {
            let models = try AsrModels.loadLocal(from: files, version: .v3)
            let manager = AsrManager(models: models)
            lock.withLock { loaded = (model.id, manager) }
        } catch {
            throw DictationFailure(
                "\(model.name) could not be loaded from its folder (\(error.localizedDescription)). Delete it on the Dictation page and download it again."
            )
        }
    }

    func recognize(_ audio: AsyncStream<CarrierCore.AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let (taken, language) = lock.withLock { (loaded?.manager, language) }
        Task {
            guard let manager = taken else {
                out.yield(.failed(DictationFailure("Parakeet TDT v3 was not prepared.")))
                out.finish()
                return
            }
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
                    let result = try await manager.transcribe(heard, decoderState: &state, language: language)
                    out.yield(.final(result.text.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            } catch {
                out.yield(.failed(DictationFailure("Parakeet TDT v3 stopped: \(error.localizedDescription)")))
            }
            out.finish()
        }
        return events
    }
}

/// The only place FluidAudio goes online, on the person's click: it turns FluidAudio's offline mode off for the download and on again.
/// ponytail: a global flag, which assumes one FluidAudio download at a time; the loads never read it, so a dictation is never online.
struct FluidAudioDownloader: ModelDownloader {
    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        ModelHub.offlineMode = false
        defer { ModelHub.offlineMode = true }
        // the library's callback cannot hold the port's non-escaping `progress`: its fractions cross a stream, in order, to a loop that calls it
        let (fractions, sink) = AsyncStream<Double>.makeStream()
        let files = FluidAudioRecognizer.files(in: folder)
        let work = Task {
            defer { sink.finish() }
            try await AsrModels.download(to: files, version: .v3) { sink.yield($0.fractionCompleted) }
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
