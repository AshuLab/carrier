import Foundation

public enum DictationIcon: Equatable, Sendable { case mic, micSlash, spinner }

/// What macOS says about the microphone for Carrier. A restricted microphone is a denied one to the person.
public enum MicrophonePermission: Equatable, Sendable { case allowed, denied, notAsked }

/// What a click on the microphone does: `start` goes on to listen (and the first time macOS asks for the microphone on the way), and
/// `explainBlock` opens the popover of a blocked microphone, with its way to System Settings.
public enum DictationClick: Equatable, Sendable { case start, explainBlock }

public func dictationClick(_ microphone: MicrophonePermission) -> DictationClick { microphone == .denied ? .explainBlock : .start }

/// The popover of a blocked microphone (dictation-composer-spec.html, section 4).
public enum MicrophoneBlockedPopover {
    public static func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.dictationBlockedTitle(bundle: bundle, locale: locale) }
    public static func message(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.dictationBlockedMessage(bundle: bundle, locale: locale) }
    public static func button(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.dictationOpenSystemSettings(bundle: bundle, locale: locale) }
    /// The Microphone pane of System Settings.
    public static let settingsURL = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
}

/// What the message box draws and says for a state of the session (dictation-composer-spec.html, section 4).
public struct DictationPresentation: Equatable, Sendable {
    public let icon: DictationIcon
    public let inAccent: Bool
    public let pressable: Bool
    /// The short line in the bottom row, for the two states a spinner cannot explain.
    public let caption: String?
    public let sendEnabled: Bool
    public let label: String
    public let help: String
}

/// The microphone of the box for `state`; nil when no recognizer is registered, and then the box draws none. A blocked microphone shows
/// `mic.slash` while the box is idle, and a click on it opens the popover. A dictation that listens before its model is ready (`modelReady` false) is drawn
/// as listening, with the caption of the model getting ready. A dictation that transcribes has no caption until its answer is slow (`answerIsSlow`).
public func dictationPresentation(
    _ state: DictationSession.State, registered: Bool, microphone: MicrophonePermission = .allowed, modelReady: Bool = true, answerIsSlow: Bool = false,
    bundle: Bundle? = nil, locale: Locale = .current
) -> DictationPresentation? {
    guard registered else { return nil }
    let gettingReady = Copy.dictationGettingReady(bundle: bundle, locale: locale)
    switch state {
    case .idle where microphone == .denied:
        return DictationPresentation(
            icon: .micSlash, inAccent: false, pressable: true, caption: nil, sendEnabled: true, label: Copy.dictationLabelBlocked(bundle: bundle, locale: locale),
            help: Copy.dictationHelpBlocked(bundle: bundle, locale: locale)
        )
    case .idle:
        let dictate = Copy.dictationDictate(bundle: bundle, locale: locale)
        return DictationPresentation(icon: .mic, inAccent: false, pressable: true, caption: nil, sendEnabled: true, label: dictate, help: dictate)
    case .gettingReady:
        return DictationPresentation(
            icon: .spinner, inAccent: false, pressable: false, caption: gettingReady, sendEnabled: false,
            label: Copy.dictationLabelGettingReady(bundle: bundle, locale: locale), help: gettingReady
        )
    case .listening:
        let stop = Copy.dictationStop(bundle: bundle, locale: locale)
        return DictationPresentation(
            icon: .mic, inAccent: true, pressable: true, caption: modelReady ? nil : gettingReady, sendEnabled: false, label: stop, help: stop
        )
    case .transcribing:
        let caption = Copy.dictationTranscribingCaption(bundle: bundle, locale: locale)
        return DictationPresentation(
            icon: .spinner, inAccent: false, pressable: false, caption: answerIsSlow ? caption : nil, sendEnabled: false,
            label: Copy.dictationLabelTranscribing(bundle: bundle, locale: locale), help: caption
        )
    case .cleaning:
        // pressable: a click, like Esc, skips the cleanup and keeps the raw text
        return DictationPresentation(
            icon: .spinner, inAccent: false, pressable: true, caption: Copy.dictationCleaningCaption(bundle: bundle, locale: locale), sendEnabled: false,
            label: Copy.dictationLabelCleaning(bundle: bundle, locale: locale), help: Copy.dictationHelpCleaning(bundle: bundle, locale: locale)
        )
    }
}

/// What VoiceOver is told about a dictation. Partial text is never one of them: it would speak over the person.
public enum DictationNotice: Equatable, Sendable {
    case gettingReady
    case listening
    case stopped(words: Int)
    case failed(DictationFailure)
}

public func dictationAnnouncement(_ notice: DictationNotice, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    switch notice {
    case .gettingReady: Copy.dictationAnnounceGettingReady(bundle: bundle, locale: locale)
    case .listening: Copy.dictationAnnounceListening(bundle: bundle, locale: locale)
    case .stopped(let words): Copy.dictationAnnounceStopped(words: words, bundle: bundle, locale: locale)
    case .failed(let failure): Copy.dictationAnnounceFailed(cause: failure.shown(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
    }
}
