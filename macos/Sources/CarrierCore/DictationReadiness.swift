import Foundation

// What the top of the Dictation page says (docs/macos/dictation.md#the-dictation-page): whether dictation can work now, what is in the way, and the
// three things it needs: the microphone, Accessibility (only for pasting into other apps) and a speech model. Decided here, from what the page
// knows, so it can be tested; the view only draws it.

/// The screens of the Dictation page that open from its first screen; the raw value is the place's path (`SettingsPlace.path`).
public enum DictationScreen: String, CaseIterable, Sendable {
    case recognition, global, cleanup, sounds, history, statistics

    public var title: String {
        switch self {
        case .recognition: "Speech recognition"
        case .global: "Global dictation"
        case .cleanup: "Cleanup"
        case .sounds: "Sounds"
        case .history: "History"
        case .statistics: "Statistics"
        }
    }

    /// The line under the title in the list of the first screen.
    public var detail: String {
        switch self {
        case .recognition: "Models, language and memory"
        case .global: "Any app: its shortcut and the widget"
        case .cleanup: "A model on this Mac rewrites what you said"
        case .sounds: "Start and end of a dictation"
        case .history: "What you dictated, to copy again"
        case .statistics: "How much you dictate and the time it saves"
        }
    }
}

/// The speech model the page would use, as far as being there goes.
public enum DictationModelReadiness: Equatable, Sendable {
    case ready(String)
    /// The model chosen is not on disk, so another (Apple's) listens until it is downloaded.
    case missing(String)
    case downloading(String)
}

public struct DictationReadiness: Equatable, Sendable {
    public enum Tone: Equatable, Sendable { case off, ready, attention, blocked }
    public enum Mark: Equatable, Sendable { case ok, attention, off }
    public enum Kind: Equatable, Sendable { case microphone, accessibility, model }
    /// What the person can do about an item from here.
    public enum Fix: Equatable, Sendable { case openMicrophoneSettings, openAccessibilitySettings }

    public struct Item: Equatable, Identifiable, Sendable {
        public let kind: Kind
        public let title: String
        public let state: String
        public let mark: Mark
        public let fix: Fix?
        public var id: Kind { kind }
    }

    public let tone: Tone
    public let title: String
    /// What is wrong, in the order it matters; empty when nothing is.
    public let notes: [String]
    /// The microphone, Accessibility and the model, whatever the tone: empty while Dictation is off.
    public let items: [Item]
}

/// `accessibilityTrusted` is what macOS says of Carrier; it only matters while Dictate in any app is on, since the message boxes never paste into
/// another app. With Dictation off nothing is checked.
public func dictationReadiness(
    enabled: Bool, microphone: MicrophonePermission, accessibilityTrusted: Bool, globalOn: Bool, model: DictationModelReadiness
) -> DictationReadiness {
    guard enabled else {
        return DictationReadiness(tone: .off, title: "Dictation is off", notes: ["No microphone in the message box, and nothing listens."], items: [])
    }
    let mic: DictationReadiness.Item
    switch microphone {
    case .allowed: mic = .init(kind: .microphone, title: "Microphone", state: "Allowed", mark: .ok, fix: nil)
    case .denied: mic = .init(kind: .microphone, title: "Microphone", state: "Not allowed", mark: .attention, fix: .openMicrophoneSettings)
    case .notAsked: mic = .init(kind: .microphone, title: "Microphone", state: "Not asked yet", mark: .off, fix: nil)
    }
    let accessibility: DictationReadiness.Item = accessibilityTrusted
        ? .init(kind: .accessibility, title: "Accessibility", state: "Allowed", mark: .ok, fix: nil)
        : .init(kind: .accessibility, title: "Accessibility", state: "Not allowed", mark: globalOn ? .attention : .off, fix: globalOn ? .openAccessibilitySettings : nil)
    let modelItem: DictationReadiness.Item
    switch model {
    case .ready(let name): modelItem = .init(kind: .model, title: name, state: "ready", mark: .ok, fix: nil)
    case .missing(let name): modelItem = .init(kind: .model, title: name, state: "not on disk", mark: .attention, fix: nil)
    case .downloading(let name): modelItem = .init(kind: .model, title: name, state: "downloading", mark: .off, fix: nil)
    }
    var notes: [String] = []
    if microphone == .denied { notes.append("macOS has the microphone blocked for Carrier, so dictation cannot listen.") }
    if case .missing(let name) = model { notes.append("\(name) is not on disk: download it in the models table or choose another.") }
    if accessibilityTrusted == false, globalOn { notes.append("Without Accessibility the text goes on the clipboard instead of being pasted.") }
    if microphone == .notAsked { notes.append("Carrier asks macOS the first time you dictate.") }
    let items = [mic, accessibility, modelItem]
    if microphone == .denied { return DictationReadiness(tone: .blocked, title: "Cannot listen yet", notes: notes, items: items) }
    let attention = items.filter { $0.mark == .attention }.count
    switch attention {
    case 0: return DictationReadiness(tone: .ready, title: "Ready to dictate", notes: notes, items: items)
    case 1: return DictationReadiness(tone: .attention, title: "Ready, with one thing to fix", notes: notes, items: items)
    default: return DictationReadiness(tone: .attention, title: "Ready, with \(attention) things to fix", notes: notes, items: items)
    }
}
