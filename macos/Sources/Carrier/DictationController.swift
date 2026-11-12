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
            modelsRoot: dictationModelsRoot(), downloader: RealDownloads()
        )
        capture.onLevel = { level in Task { @MainActor in controller.level = level } }
        return controller
    }()

    let registry: RecognizerRegistry
    let session: DictationSession
    /// The speech models on disk, their downloads and their space.
    let store: ModelStore
    /// The voice's level, `0...1`, smoothed, while the microphone listens; 0 otherwise.
    private(set) var level: Float = 0
    private(set) var microphone: MicrophonePermission
    /// Whether the message boxes have a microphone. Off, nothing asks macOS for the microphone and nothing listens.
    private(set) var enabled: Bool
    @ObservationIgnored private let access: MicrophoneAccess
    @ObservationIgnored private let preferences: AppPreferences

    /// The defaults are a fixture build's: a capture that hears nothing, which the fixture recognizer does not need, and an allowed microphone.
    init(
        registry: RecognizerRegistry, capture: AudioCapture = ScriptedCapture(), microphone access: MicrophoneAccess = .allowed,
        log: DictationLog? = nil, preferences: AppPreferences = AppPreferences(),
        // a fixture build keeps its pretend downloads in a temporary folder, away from the person's own
        modelsRoot: URL = FileManager.default.temporaryDirectory.appending(path: "carrier-fixture-models"),
        downloader: any ModelDownloader = FixtureModelDownloader(),
        sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.registry = registry
        self.access = access
        self.preferences = preferences
        enabled = preferences.dictationEnabled
        microphone = access.status()
        store = ModelStore(
            root: modelsRoot, models: { registry.recognizers.flatMap(\.models) },
            downloader: downloader, inUse: { preferences.dictationModel(among: registry.recognizers.flatMap(\.models))?.id },
            log: { log?.append($0) }, announce: { AccessibilityNotification.Announcement($0).post() }
        )
        session = DictationSession(capture: capture, sleep: sleep, announce: { AccessibilityNotification.Announcement($0).post() }, log: { log?.append($0) })
        // sending the app to the background: nothing keeps listening unseen
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
        // the person may have allowed the microphone in System Settings and come back
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.microphone = self?.access.status() ?? .denied }
        }
    }

    /// The speech models on offer, those of every registered recognizer.
    var models: [SpeechModel] { registry.recognizers.flatMap(\.models) }

    /// The model the person chose, and Apple's when they did not or it is gone.
    var model: SpeechModel? { preferences.dictationModel(among: models) }

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
            if session.state == .listening { session.stop() }
            return .start
        }
        microphone = access.status()
        let click = dictationClick(microphone)
        guard click == .start, let model, let recognizer = registry.recognizers.first(where: { $0.models.contains(model) }) else { return click }
        if microphone == .allowed {
            session.start(recognizer: recognizer, model: model, into: field)
        } else {
            // the first click: macOS asks, and the dictation starts when the person allows it
            Task {
                let allowed = await access.request()
                microphone = access.status()
                if allowed, enabled { session.start(recognizer: recognizer, model: model, into: field) }
            }
        }
        return click
    }

    /// Stops the dictation of `owner`, or whichever runs when nil: a typed key, Enter and leaving (a session, the window, the app).
    func stop(ownedBy owner: String? = nil) {
        if owner == nil || session.owner == owner { session.stop() }
    }
}

/// Where the speech models live: `<Carrier folder>/app/models`.
func dictationModelsRoot() -> URL { URL(fileURLWithPath: currentCarrierFolder() + "/app/models") }

/// The downloader of a real build: each recognizer's own, FluidAudio's so far. The others arrive with their recognizers.
private struct RealDownloads: ModelDownloader {
    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        switch model.recognizer {
        case .fluidAudio: try await FluidAudioDownloader().download(model, into: folder, progress: progress)
        case .apple, .whisper: throw DictationFailure("This build cannot download \(model.name).")
        }
    }
}
