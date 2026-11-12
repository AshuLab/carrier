import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The one dictation of the app: what the message boxes read (the session's state, the recognizers on offer, the microphone's permission,
/// the level of the voice) and the click that starts or stops it. The recognizer is the first one registered and its first model until the
/// Dictation page lets a person choose.
@MainActor @Observable final class DictationController {
    static let shared: DictationController = {
        // a fixture build hears nothing and asks macOS for nothing: its recognizer is a canned phrase
        guard CommandLine.arguments.contains("--fixture") == false else { return DictationController(registry: .shared) }
        let capture = MicrophoneCapture()
        let controller = DictationController(
            registry: .shared, capture: capture, microphone: .system, log: DictationLog(carrierFolder: currentCarrierFolder())
        )
        capture.onLevel = { level in Task { @MainActor in controller.level = level } }
        return controller
    }()

    let registry: RecognizerRegistry
    let session: DictationSession
    /// The voice's level, `0...1`, smoothed, while the microphone listens; 0 otherwise.
    private(set) var level: Float = 0
    private(set) var microphone: MicrophonePermission
    @ObservationIgnored private let access: MicrophoneAccess

    /// The defaults are a fixture build's: a capture that hears nothing, which the fixture recognizer does not need, and an allowed microphone.
    init(
        registry: RecognizerRegistry, capture: AudioCapture = ScriptedCapture(), microphone access: MicrophoneAccess = .allowed,
        log: DictationLog? = nil, sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.registry = registry
        self.access = access
        microphone = access.status()
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

    /// What `owner`'s box draws: nothing when no recognizer is registered, and the state of the session only while that box is the one dictating.
    func presentation(for owner: String) -> DictationPresentation? {
        dictationPresentation(session.owner == owner ? session.state : .idle, registered: registry.recognizers.isEmpty == false, microphone: microphone)
    }

    /// A click on the microphone of a box: stops the dictation that box runs, or starts one into its field (stopping another box's first).
    /// Says `explainBlock` when macOS blocks the microphone, and the box opens its popover.
    @discardableResult
    func toggle(into field: DictationField) -> DictationClick {
        guard session.owner != field.owner else {
            if session.state == .listening { session.stop() }
            return .start
        }
        microphone = access.status()
        let click = dictationClick(microphone)
        guard click == .start, let recognizer = registry.recognizers.first, let model = recognizer.models.first else { return click }
        if microphone == .allowed {
            session.start(recognizer: recognizer, model: model, into: field)
        } else {
            // the first click: macOS asks, and the dictation starts when the person allows it
            Task {
                let allowed = await access.request()
                microphone = access.status()
                if allowed { session.start(recognizer: recognizer, model: model, into: field) }
            }
        }
        return click
    }

    /// Stops the dictation of `owner`, or whichever runs when nil: a typed key, Enter and leaving (a session, the window, the app).
    func stop(ownedBy owner: String? = nil) {
        if owner == nil || session.owner == owner { session.stop() }
    }
}
