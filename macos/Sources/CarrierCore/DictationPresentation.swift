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
    public static let title = "Carrier can't use the microphone"
    public static let message = "macOS has it blocked for Carrier. Allow it in System Settings, then dictate again."
    public static let button = "Open System Settings"
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
/// `mic.slash` while the box is idle, and a click on it opens the popover.
public func dictationPresentation(_ state: DictationSession.State, registered: Bool, microphone: MicrophonePermission = .allowed) -> DictationPresentation? {
    guard registered else { return nil }
    switch state {
    case .idle where microphone == .denied:
        return DictationPresentation(
            icon: .micSlash, inAccent: false, pressable: true, caption: nil, sendEnabled: true, label: "Dictation is blocked", help: "Microphone blocked"
        )
    case .idle:
        return DictationPresentation(icon: .mic, inAccent: false, pressable: true, caption: nil, sendEnabled: true, label: "Dictate", help: "Dictate")
    case .gettingReady:
        return DictationPresentation(
            icon: .spinner, inAccent: false, pressable: false, caption: "Getting the model ready…", sendEnabled: false,
            label: "Dictation is getting ready", help: "Getting the model ready…"
        )
    case .listening:
        return DictationPresentation(icon: .mic, inAccent: true, pressable: true, caption: nil, sendEnabled: false, label: "Stop dictation", help: "Stop dictation")
    case .transcribing:
        return DictationPresentation(icon: .spinner, inAccent: false, pressable: false, caption: "Transcribing…", sendEnabled: false, label: "Transcribing", help: "Transcribing…")
    }
}

/// What VoiceOver is told about a dictation. Partial text is never one of them: it would speak over the person.
public enum DictationNotice: Equatable, Sendable {
    case gettingReady
    case listening
    case stopped(words: Int)
    case failed(DictationFailure)
}

public func dictationAnnouncement(_ notice: DictationNotice) -> String {
    switch notice {
    case .gettingReady: "Getting the model ready"
    case .listening: "Listening"
    case .stopped(let words): "Dictation stopped, \(words == 0 ? "no words" : words == 1 ? "1 word" : "\(words) words") added"
    case .failed(let failure): "Dictation failed: \(failure.cause)"
    }
}
