import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The one dictation of the app: what the message boxes read (the session's state, the recognizers on offer, the microphone's permission,
/// the level of the voice), the click that starts or stops it and the switch of the Dictation page, which the boxes of both views read at once.
/// The recognizer is the one of the model the person chose on that page, Apple's until they do.
@MainActor @Observable final class DictationController {
    static let shared: DictationController = {
        // a fixture build hears nothing and asks macOS for nothing: its recognizer is a canned phrase
        guard CommandLine.arguments.contains("--fixture") == false else { return DictationController(registry: .shared) }
        let capture = MicrophoneCapture()
        let controller = DictationController(
            registry: .shared, capture: capture, microphone: .system, log: DictationLog(carrierFolder: currentCarrierFolder()),
            modelsRoot: dictationModelsRoot(), downloader: RealDownloads(), recordsFolder: currentCarrierFolder()
        )
        capture.onLevel = { levels in Task { @MainActor in controller.voice = levels } }
        return controller
    }()

    let registry: RecognizerRegistry
    let session: DictationSession
    /// The speech models on disk, their downloads and their space.
    let store: ModelStore
    /// The history of dictations, which every dictation that ends with words is written to while Keep the text is on.
    let records: DictationRecords
    /// How loud the voice is, as a whole and in three bands, while the microphone listens; silence otherwise.
    private(set) var voice = VoiceLevels.silence
    var level: Float { voice.overall }
    private(set) var microphone: MicrophonePermission
    /// Whether the message boxes have a microphone. Off, nothing asks macOS for the microphone and nothing listens.
    private(set) var enabled: Bool
    @ObservationIgnored private let access: MicrophoneAccess
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let cleanupClient: any TextModelClient
    /// Whether macOS has the microphone prompt open, and the box whose click waits for its answer (nil once that box stops or leaves).
    @ObservationIgnored private var prompting = false
    @ObservationIgnored private var waiting: String?
    @ObservationIgnored private var sweep: Task<Void, Never>?

    /// The defaults are a fixture build's: a capture that hears nothing, which the fixture recognizer does not need, and an allowed microphone.
    init(
        registry: RecognizerRegistry, capture: AudioCapture = ScriptedCapture(), microphone access: MicrophoneAccess = .allowed,
        log: DictationLog? = nil, preferences: AppPreferences = AppPreferences(),
        // a fixture build keeps its pretend downloads in a temporary folder, away from the person's own
        modelsRoot: URL = FileManager.default.temporaryDirectory.appending(path: "carrier-fixture-models"),
        downloader: any ModelDownloader = FixtureModelDownloader(), cleanupClient: any TextModelClient = LocalModelClient(),
        // a fixture build, like a test, keeps its history in a temporary folder, never in the person's Carrier folder
        recordsFolder: String = NSTemporaryDirectory() + "carrier-fixture-dictations-\(UUID().uuidString)",
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.registry = registry
        self.access = access
        self.preferences = preferences
        self.cleanupClient = cleanupClient
        enabled = preferences.dictationEnabled
        microphone = access.status()
        store = ModelStore(
            root: modelsRoot, models: { registry.recognizers.flatMap(\.models) },
            downloader: downloader, inUse: { preferences.dictationModel(among: registry.recognizers.flatMap(\.models))?.id },
            log: { log?.append($0) }, announce: { AccessibilityNotification.Announcement($0).post() }
        )
        session = DictationSession(capture: capture, sleep: sleep, announce: { AccessibilityNotification.Announcement($0).post() }, log: { log?.append($0) },
            keepAudio: { preferences.dictationKeepAudio })
        records = DictationRecords(
            carrierFolder: recordsFolder, keep: { preferences.dictationKeepText }, keepAudio: { preferences.dictationKeepAudio },
            audioDays: { preferences.dictationDeleteAudioAfter })
        // the widget writes its own entries, which know where the text went; a message box's went into the box
        session.onTake = { [records] take in
            guard take.owner != GlobalDictation.owner else { return }
            records.record(
                DictationEntry(take, outcome: boxOutcome(take.ending), destination: DictationEntry.carrier, cleanupModel: preferences.dictationCleanupModel),
                audio: take.clip)
        }
        // sending the app to the background: nothing keeps listening unseen
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        // the person may have allowed the microphone in System Settings and come back
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.microphone = self?.access.status() ?? .denied }
        }
    }

    /// Deletes the audio past the limit of days now and once a day while the app runs.
    func startAudioSweep() {
        sweep = Task { [records] in
            while Task.isCancelled == false {
                records.deleteOldAudio()
                try? await Task.sleep(for: .seconds(86_400))
            }
        }
    }

    /// The speech models on offer, those of every registered recognizer.
    var models: [SpeechModel] { registry.recognizers.flatMap(\.models) }

    /// The model the person chose, and Apple's when they did not or it is gone.
    /// The model the person chose, whether or not it is still on disk (the page says when it is not).
    var chosenModel: SpeechModel? { preferences.dictationModel(among: models) }
    /// The model dictation uses: the chosen one when it is on disk, else Apple's, which is always there.
    var model: SpeechModel? {
        if let chosen = chosenModel, store.state(of: chosen) == .downloaded { return chosen }
        return models.first { $0.recognizer == .apple }
    }

    /// The model dictation uses and the recognizer that has it, for a dictation that is not a message box's (the widget).
    var speechModel: (any Recognizer, SpeechModel)? {
        guard let model, let recognizer = registry.recognizers.first(where: { $0.models.contains(model) }) else { return nil }
        return (recognizer, model)
    }

    /// What macOS says about the microphone now.
    func microphoneStatus() -> MicrophonePermission {
        microphone = access.status()
        return microphone
    }

    /// Asks macOS for the microphone, which it does only the first time.
    func requestMicrophone() async {
        _ = await access.request()
        microphone = access.status()
    }

    /// The rows of the speech models table, for the recognizer chosen in its filter (all of them when nil).
    func rows(filter: RecognizerID?) -> [SpeechModelRow] {
        speechModelRows(models: models, filter: filter, state: store.state(of:), inUse: model?.id)
    }

    /// Shows the models' folder, which may not exist yet.
    func showModelsInFinder() {
        try? FileManager.default.createDirectory(at: store.root, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.root])
    }

    func choose(model: SpeechModel) { preferences.dictationModelID = model.id }

    /// The Language popup for the chosen model, over the languages of this Mac.
    var languages: LanguageChoices? {
        model.map { languageChoices(for: $0, macOSLanguages: Locale.preferredLanguages, saved: preferences.dictationLanguage) }
    }

    func choose(language: String) { preferences.dictationLanguage = language }

    /// The switch of the page. Turning it off while a dictation listens stops it and keeps its text.
    func setEnabled(_ on: Bool) {
        preferences.dictationEnabled = on
        enabled = on
        if on == false { stop() }
    }

    /// Reset of the page: on, Apple's and the language of macOS. The downloaded models are not touched.
    func reset() {
        preferences.reset(.dictation)
        enabled = preferences.dictationEnabled
    }

    /// What `owner`'s box draws: nothing when Dictation is off or no recognizer is registered, and the state of the session only while that box is the one dictating.
    func presentation(for owner: String) -> DictationPresentation? {
        guard enabled else { return nil }
        return dictationPresentation(session.owner == owner ? session.state : .idle, registered: registry.recognizers.isEmpty == false, microphone: microphone)
    }

    /// A click on the microphone of a box: stops the dictation that box runs, or starts one into its field (stopping another box's first).
    /// Says `explainBlock` when macOS blocks the microphone, and the box opens its popover.
    @discardableResult
    func toggle(into field: DictationField) -> DictationClick {
        guard enabled else { return .start }
        guard session.owner != field.owner else {
            // a click while it cleans skips the cleanup and keeps the raw text
            if session.state == .listening { session.stop() } else if session.state == .cleaning { session.cancel() }
            return .start
        }
        // a second click while macOS asks waits for that answer, it does not ask again
        guard prompting == false else { return .start }
        microphone = access.status()
        let click = dictationClick(microphone)
        guard click == .start else { return click }
        guard let model, let recognizer = registry.recognizers.first(where: { $0.models.contains(model) }) else {
            session.refuse(DictationFailure("No speech model is available"), for: field.owner)
            return click
        }
        if microphone == .allowed {
            session.start(recognizer: recognizer, model: model, into: field, cleanup: cleanup())
        } else {
            // the first click: macOS asks, and the dictation starts when the person allows it and the box is still there
            prompting = true
            waiting = field.owner
            Task {
                let allowed = await access.request()
                microphone = access.status()
                prompting = false
                defer { waiting = nil }
                if allowed, enabled, waiting == field.owner { session.start(recognizer: recognizer, model: model, into: field, cleanup: cleanup()) }
            }
        }
        return click
    }

    /// The cleanup of the text a box dictates, when the person turned it on (a server and a model chosen); nil otherwise, and the dictation ends as it always did.
    func cleanup() -> DictationCleanup? {
        guard preferences.dictationCleanupEnabled, let server = preferences.dictationCleanupServer, let model = preferences.dictationCleanupModel else { return nil }
        let run = CleanupRun(client: cleanupClient), prompt = preferences.dictationCleanupPrompt
        return { try await run.run(server: server, model: model, prompt: prompt, text: $0).text }
    }

    /// Escape: cancels the dictation of `owner` and keeps the text that was on the screen. Says whether there was one, so the key is taken only then.
    func cancel(ownedBy owner: String) -> Bool {
        session.owner == owner && session.cancel()
    }

    /// Stops the dictation of `owner`, or whichever runs when nil: a typed key, Enter and leaving (a session, the window, the app).
    func stop(ownedBy owner: String? = nil) {
        guard let owner else { return session.stop() }
        if waiting == owner { waiting = nil }
        session.stop(ownedBy: owner)
    }
}

/// Where the speech models live: `<Carrier folder>/app/models`.
func dictationModelsRoot() -> URL { URL(fileURLWithPath: currentCarrierFolder() + "/app/models") }

/// The downloader of a real build: each recognizer's own.
private struct RealDownloads: ModelDownloader {
    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        switch model.recognizer {
        case .fluidAudio: try await FluidAudioDownloader().download(model, into: folder, progress: progress)
        case .whisper: try await WhisperKitDownloader().download(model, into: folder, progress: progress)
        case .apple: throw DictationFailure("This build cannot download \(model.name).")
        }
    }
}
