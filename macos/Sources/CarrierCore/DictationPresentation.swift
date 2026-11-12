import Foundation

public enum DictationIcon: Equatable, Sendable { case mic, spinner }

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

/// The microphone of the box for `state`; nil when no recognizer is registered, and then the box draws none.
public func dictationPresentation(_ state: DictationSession.State, registered: Bool) -> DictationPresentation? {
    guard registered else { return nil }
    switch state {
    case .idle:
        return DictationPresentation(icon: .mic, inAccent: false, pressable: true, caption: nil, sendEnabled: true, label: "Dictate", help: "Dictate")
    case .gettingReady:
        return DictationPresentation(
            icon: .spinner, inAccent: false, pressable: false, caption: "Getting the model ready…", sendEnabled: true,
            label: "Dictation is getting ready", help: "Getting the model ready…"
        )
    case .listening:
        return DictationPresentation(icon: .mic, inAccent: true, pressable: true, caption: nil, sendEnabled: false, label: "Stop dictation", help: "Stop dictation")
    case .transcribing:
        return DictationPresentation(icon: .spinner, inAccent: false, pressable: false, caption: "Transcribing…", sendEnabled: false, label: "Transcribing", help: "Transcribing…")
    }
}
