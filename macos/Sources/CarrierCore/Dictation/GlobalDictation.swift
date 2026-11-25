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
    /// `running` is a dictation in any stage (the session says which); `failed` is the widget left open with its cause, until Esc or the shortcut;
    /// `copied` is the widget left open with the text, which was only copied for the reason, until Dismiss, Esc or a new dictation.
    public enum State: Equatable, Sendable { case idle, running, failed(String), copied(PasteReason) }

    /// The session's owner for the widget, so its failures and its end are told apart from a message box's.
    public static let owner = "global"

    public private(set) var state = State.idle
    /// What was heard so far, and when the shortcut started it.
    public private(set) var text = ""
    /// Where the words still forming are in `text` (UTF-16 units), nil when all of it is firm.
    public private(set) var tentative: Range<Int>?
    public private(set) var startedAt: Date?
    public let session: DictationSession

    /// `text` apart where the tentative words begin: the widget draws only the second part as partial text.
    public var split: (firm: String, tentative: String) {
        let whole = text as NSString
        guard let tentative, tentative.upperBound <= whole.length else { return (text, "") }
        return (whole.substring(to: tentative.lowerBound), whole.substring(with: NSRange(location: tentative.lowerBound, length: tentative.count)))
    }
    /// How the last dictation ended when the widget shows it for a moment, `pasted` or `cancelled`, until the next one begins.
    public private(set) var farewell: DictationWidgetState?
    /// Why the text of this dictation was not cleaned when Cleanup was on and failed, which the widget says next to the raw text it pasted or copied.
    public private(set) var notCleaned: String?

    @ObservationIgnored private let speechModel: () -> (any Recognizer, SpeechModel)?
    @ObservationIgnored private let microphone: () -> MicrophonePermission
    @ObservationIgnored private let decision: () -> PasteDecision
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let perform: (GlobalDictationEffect) -> Void
    @ObservationIgnored private let moment: (GlobalDictationMoment) -> Void
    @ObservationIgnored private let activation: () -> DictationActivation
    @ObservationIgnored private let record: (DictationEntry) -> Void
    @ObservationIgnored private let frontApp: () -> String?
    @ObservationIgnored private let cleanup: () -> DictationCleanup?
    @ObservationIgnored private let cleanupModel: () -> String?
    /// The language the causes that the widget shows are said in (`dictation.log` keeps its English).
    @ObservationIgnored private let bundle: Bundle?
    @ObservationIgnored private let locale: Locale
    /// Whether the widget's dictation listens and has not been stopped, so a second press before the text arrives is no second end.
    @ObservationIgnored private var listening = false
    /// Whether this dictation was started as a hold, which the key coming up ends; read when it starts, so changing the setting under way changes nothing.
    @ObservationIgnored private var holding = false

    /// `speechModel` is the speech model the person chose and its recognizer (nil when there is none); `decision` says whether the text may be pasted
    /// right now or only copied, and why (`pasteDecision`). `record` hears each dictation that ends with words, and `frontApp` names the app a paste goes to.
    /// `cleanup` is the Cleanup of the text when the person turned it on (nil: the flow is as it was) and `cleanupModel` the model it uses, for the history.
    public init(
        session: DictationSession, speechModel: @escaping () -> (any Recognizer, SpeechModel)?, microphone: @escaping () -> MicrophonePermission,
        decision: @escaping () -> PasteDecision, activation: @escaping () -> DictationActivation = { .toggle }, now: @escaping () -> Date = Date.init,
        moment: @escaping (GlobalDictationMoment) -> Void = { _ in }, record: @escaping (DictationEntry) -> Void = { _ in },
        frontApp: @escaping () -> String? = { nil }, cleanup: @escaping () -> DictationCleanup? = { nil }, cleanupModel: @escaping () -> String? = { nil },
        perform: @escaping (GlobalDictationEffect) -> Void, bundle: Bundle? = nil, locale: Locale = .current
    ) {
        self.session = session
        self.speechModel = speechModel
        self.microphone = microphone
        self.decision = decision
        self.activation = activation
        self.now = now
        self.perform = perform
        self.moment = moment
        self.record = record
        self.frontApp = frontApp
        self.cleanup = cleanup
        self.cleanupModel = cleanupModel
        self.bundle = bundle
        self.locale = locale
        session.onEnd = { [weak self] owner in self?.ended(owner) }
        session.onListening = { [weak self] in self?.began() }
    }

    /// What the widget draws now (`dictationWidgetLook`). Before the session says anything, and between a dictation and the next, it reads as working.
    public var shown: DictationWidgetState {
        switch state {
        case .failed: .failed
        case .copied: .copied
        case .running: session.state == .listening ? .listening : session.state == .cleaning ? .cleaning : .working
        case .idle: farewell ?? .working
        }
    }

    public func handle(_ key: GlobalDictationKey) {
        switch (key, state) {
        case (.down, .idle): begin()
        case (.down, .running): finish()
        case (.up, .running) where holding: finish()
        case (.down, .failed), (.escape, .failed), (.escape, .copied): dismiss()
        // a new dictation closes the widget that was left open
        case (.down, .copied):
            dismiss()
            begin()
        // Esc while it cleans skips the cleanup: the session ends and the raw text goes on to be pasted
        case (.escape, .running) where session.state == .cleaning: session.cancel()
        case (.escape, .running):
            // before the cancel, so the session's end is not taken for the person's own
            state = .idle
            if listening {
                listening = false
                moment(.cancelled)
            }
            if session.cancel() { remember(.cancelled) }
            farewell = .cancelled
            dismiss()
        // a toggle has nothing to do with the key coming up, and a hold that Esc or a failure already ended has nothing left to end
        case (.up, _), (.escape, .idle): break
        }
    }

    /// The end the person asked for, with the second press or the release: the session stops and goes on to paste.
    private func finish() {
        guard session.state != .transcribing else { return }
        session.stop()
        if listening {
            listening = false
            moment(.stopped)
        }
    }

    private func begin() {
        holding = activation() == .hold
        farewell = nil
        notCleaned = nil
        text = ""
        tentative = nil
        startedAt = now()
        perform(.show)
        guard microphone() != .denied else { return fail(DictationFailure(.microphoneBlocked)) }
        guard let (recognizer, model) = speechModel() else { return fail(DictationFailure(.noSpeechModel)) }
        state = .running
        session.start(
            recognizer: recognizer, model: model,
            into: DictationField(
                owner: Self.owner, text: { self.text }, caret: { self.text.utf16.count }, put: { text, _, range in
                    self.text = text
                    self.tentative = range
                }
            ),
            cleanup: cleanup()
        )
    }

    /// A dictation that could not start: told in the widget and logged, like any failure.
    private func fail(_ cause: DictationFailure) {
        session.refuse(cause, for: Self.owner)
        state = .failed(cause.shown(bundle: bundle, locale: locale))
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
            // a cleanup that failed ended the dictation as a stop: its raw text goes on, with the cause
            guard session.take?.ending != .failed else {
                state = .failed(cause.shown(bundle: bundle, locale: locale))
                remember(.failed)
                return
            }
            notCleaned = cause.shown(bundle: bundle, locale: locale)
        }
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // nothing was said: nothing is pasted and the widget goes quietly
        guard heard.isEmpty == false else { return dismiss() }
        text = heard
        switch decision() {
        case .paste:
            remember(.pasted, to: frontApp() ?? Copy.dictationDestinationAnotherApp(bundle: bundle, locale: locale))
            perform(.paste(heard))
            farewell = notCleaned == nil ? .pasted : .pastedRaw
            dismiss()
        case .copyOnly(let reason):
            remember(.copied)
            perform(.copy(heard))
            state = .copied(reason)
        }
    }

    /// The history hears of the dictation that just ended, which went to `destination` (the widget only, when it went to no app).
    private func remember(_ outcome: DictationOutcome, to destination: String = DictationEntry.widgetOnly) {
        if let take = session.take { record(DictationEntry(take, outcome: outcome, destination: destination, cleanupModel: cleanupModel())) }
    }

    /// The Copy button of a widget left open: the text goes on the clipboard again.
    public func copyAgain() {
        guard case .copied = state else { return }
        perform(.copy(text))
    }

    /// The Dismiss button.
    public func dismissCopied() { if case .copied = state { dismiss() } }

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
