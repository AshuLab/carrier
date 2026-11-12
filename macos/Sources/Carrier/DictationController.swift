import AppKit
import CarrierCore
import Observation
import SwiftUI

/// The one dictation of the app: what the message boxes read (the session's state, the recognizers on offer) and the click that starts or
/// stops it. The recognizer is the first one registered and its first model until the Dictation page lets a person choose.
@MainActor @Observable final class DictationController {
    static let shared = DictationController(registry: .shared)

    let registry: RecognizerRegistry
    let session: DictationSession

    /// ponytail: a capture that hears nothing, which the fixture recognizer does not need; the microphone replaces it with the real recognizers.
    init(registry: RecognizerRegistry, capture: AudioCapture = ScriptedCapture(), sleep: @escaping (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.registry = registry
        session = DictationSession(capture: capture, sleep: sleep) { AccessibilityNotification.Announcement($0).post() }
        // sending the app to the background: nothing keeps listening unseen
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    /// What `owner`'s box draws: nothing when no recognizer is registered, and the state of the session only while that box is the one dictating.
    func presentation(for owner: String) -> DictationPresentation? {
        dictationPresentation(session.owner == owner ? session.state : .idle, registered: registry.recognizers.isEmpty == false)
    }

    /// A click on the microphone of a box: stops the dictation that box runs, or starts one into its field (stopping another box's first).
    func toggle(into field: DictationField) {
        guard session.owner != field.owner else {
            if session.state == .listening { session.stop() }
            return
        }
        guard let recognizer = registry.recognizers.first, let model = recognizer.models.first else { return }
        session.start(recognizer: recognizer, model: model, into: field)
    }

    /// Stops the dictation of `owner`, or whichever runs when nil: a typed key, Enter and leaving (a session, the window, the app).
    func stop(ownedBy owner: String? = nil) {
        if owner == nil || session.owner == owner { session.stop() }
    }
}
