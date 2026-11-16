import CoreGraphics
import Foundation
import Observation

// Global dictation (docs/specs/global-dictation.md): the shortcut pressed in any app opens a widget, dictates and pastes the text once. This is the
// machine behind it, apart from the window, the hot key and the clipboard, which are the app's: it is fed what the keys do and asks the outside to
// show the widget, paste, copy or close it. The dictation itself is the `DictationSession` of the message boxes.

/// What the person does with the keys of the global dictation: the shortcut going down and up, and Esc.
public enum GlobalDictationKey: Sendable { case down, up, escape }

/// The moments of a dictation that the sounds follow: it begins to listen, the person stops it and it goes on, the person cancels it.
public enum GlobalDictationMoment: Equatable, Sendable { case listening, stopped, cancelled }

/// What the machine asks the outside to do. The text on show is `GlobalDictation.text`, which the widget reads.
public enum GlobalDictationEffect: Equatable, Sendable { case show, paste(String), copy(String), close }

@MainActor @Observable public final class GlobalDictation {
    /// `running` is a dictation in any stage (the session says which); `failed` is the widget left open with its cause, until Esc or the shortcut.
    public enum State: Equatable, Sendable { case idle, running, failed(String) }

    /// The session's owner for the widget, so its failures and its end are told apart from a message box's.
    public static let owner = "global"

    public private(set) var state = State.idle
    /// What was heard so far, and when the shortcut started it.
    public private(set) var text = ""
    public private(set) var startedAt: Date?
    public let session: DictationSession

    @ObservationIgnored private let speechModel: () -> (any Recognizer, SpeechModel)?
    @ObservationIgnored private let microphone: () -> MicrophonePermission
    @ObservationIgnored private let refusal: () -> String?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let perform: (GlobalDictationEffect) -> Void
    @ObservationIgnored private let moment: (GlobalDictationMoment) -> Void
    /// Whether the widget's dictation listens and has not been stopped, so a second press before the text arrives is no second end.
    @ObservationIgnored private var listening = false

    /// `speechModel` is the speech model the person chose and its recognizer (nil when there is none); `refusal` says why the text must not be pasted
    /// right now (no Accessibility permission, a secure field), nil when it may.
    public init(
        session: DictationSession, speechModel: @escaping () -> (any Recognizer, SpeechModel)?, microphone: @escaping () -> MicrophonePermission,
        refusal: @escaping () -> String?, now: @escaping () -> Date = Date.init,
        moment: @escaping (GlobalDictationMoment) -> Void = { _ in }, perform: @escaping (GlobalDictationEffect) -> Void
    ) {
        self.session = session
        self.speechModel = speechModel
        self.microphone = microphone
        self.refusal = refusal
        self.now = now
        self.perform = perform
        self.moment = moment
        session.onEnd = { [weak self] owner in self?.ended(owner) }
        session.onListening = { [weak self] in self?.began() }
    }

    public func handle(_ key: GlobalDictationKey) {
        switch (key, state) {
        case (.down, .idle): begin()
        case (.down, .running):
            guard session.state != .transcribing else { break }
            session.stop()
            if listening {
                listening = false
                moment(.stopped)
            }
        case (.down, .failed), (.escape, .failed): dismiss()
        case (.escape, .running):
            // before the cancel, so the session's end is not taken for the person's own
            state = .idle
            if listening {
                listening = false
                moment(.cancelled)
            }
            session.cancel()
            dismiss()
        // a toggle has nothing to do with the key coming up
        case (.up, _), (.escape, .idle): break
        }
    }

    private func begin() {
        text = ""
        startedAt = now()
        perform(.show)
        guard microphone() != .denied else { return fail(DictationFailure("macOS has the microphone blocked for Carrier. Allow it in System Settings, then dictate again.")) }
        guard let (recognizer, model) = speechModel() else { return fail(DictationFailure("No speech model is available")) }
        state = .running
        session.start(
            recognizer: recognizer, model: model,
            into: DictationField(
                owner: Self.owner, text: { self.text }, caret: { self.text.utf16.count }, put: { text, _, _ in self.text = text }
            )
        )
    }

    /// A dictation that could not start: told in the widget and logged, like any failure.
    private func fail(_ cause: DictationFailure) {
        session.refuse(cause, for: Self.owner)
        state = .failed(cause.cause)
    }

    private func began() {
        guard session.owner == Self.owner, state == .running else { return }
        listening = true
        moment(.listening)
    }

    private func ended(_ owner: String?) {
        guard owner == Self.owner, state == .running else { return }
        listening = false
        if let cause = session.failure(for: Self.owner) {
            state = .failed(cause.cause)
            return
        }
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // nothing was said: nothing is pasted and the widget goes quietly
        guard heard.isEmpty == false else { return dismiss() }
        if let why = refusal() {
            perform(.copy(heard))
            state = .failed("\(why) The text is on the clipboard.")
        } else {
            perform(.paste(heard))
            dismiss()
        }
    }

    private func dismiss() {
        state = .idle
        startedAt = nil
        perform(.close)
    }
}

/// The time of a dictation as the widget writes it: minutes and seconds, "0:07".
public func dictationClock(_ elapsed: TimeInterval) -> String {
    let seconds = max(0, Int(elapsed))
    return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
}

/// The display a window is mostly on, as an index of `displays` (both in the same coordinates): the one it overlaps the most, nil when it overlaps none.
public func displayIndex(of window: CGRect, in displays: [CGRect]) -> Int? {
    let overlaps = displays.map { $0.intersection(window) }.map { $0.isNull ? 0 : $0.width * $0.height }
    guard let most = overlaps.max(), most > 0 else { return nil }
    return overlaps.firstIndex(of: most)
}
