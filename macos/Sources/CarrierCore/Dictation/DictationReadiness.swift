import Foundation

// What the top of the Dictation page says (docs/macos/dictation.md#the-dictation-page): whether dictation can work now, what is in the way, and the
// three things it needs: the microphone, Accessibility (only for pasting into other apps) and a speech model. Decided here, from what the page
// knows, so it can be tested; the view only draws it.

/// The screens of the Dictation page that open from its first screen; the raw value is the place's path (`SettingsPlace.path`).
public enum DictationScreen: String, CaseIterable, Sendable {
    case recognition, global, cleanup, sounds, history, statistics

    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        Copy.dictationScreenTitle(which: Copy.DictationScreenTitle(self), bundle: bundle, locale: locale)
    }

    /// The line under the title in the list of the first screen.
    public func detail(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        Copy.dictationScreenDetail(which: Copy.DictationScreenDetail(self), bundle: bundle, locale: locale)
    }
}

extension Copy.DictationScreenTitle {
    fileprivate init(_ screen: DictationScreen) {
        switch screen {
        case .recognition: self = .recognition
        case .global: self = .global
        case .cleanup: self = .cleanup
        case .sounds: self = .sounds
        case .history: self = .history
        case .statistics: self = .statistics
        }
    }
}

extension Copy.DictationScreenDetail {
    fileprivate init(_ screen: DictationScreen) {
        switch screen {
        case .recognition: self = .recognition
        case .global: self = .global
        case .cleanup: self = .cleanup
        case .sounds: self = .sounds
        case .history: self = .history
        case .statistics: self = .statistics
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
    enabled: Bool, microphone: MicrophonePermission, accessibilityTrusted: Bool, globalOn: Bool, model: DictationModelReadiness,
    bundle: Bundle? = nil, locale: Locale = .current
) -> DictationReadiness {
    guard enabled else {
        return DictationReadiness(
            tone: .off, title: Copy.dictationReadyOff(bundle: bundle, locale: locale), notes: [Copy.dictationNoteOff(bundle: bundle, locale: locale)], items: []
        )
    }
    let microphoneTitle = Copy.dictationItemMicrophone(bundle: bundle, locale: locale)
    let accessibilityTitle = Copy.dictationItemAccessibility(bundle: bundle, locale: locale)
    let allowed = Copy.dictationStateAllowed(bundle: bundle, locale: locale)
    let notAllowed = Copy.dictationStateNotAllowed(bundle: bundle, locale: locale)
    let mic: DictationReadiness.Item
    switch microphone {
    case .allowed: mic = .init(kind: .microphone, title: microphoneTitle, state: allowed, mark: .ok, fix: nil)
    case .denied: mic = .init(kind: .microphone, title: microphoneTitle, state: notAllowed, mark: .attention, fix: .openMicrophoneSettings)
    case .notAsked:
        mic = .init(kind: .microphone, title: microphoneTitle, state: Copy.dictationStateNotAsked(bundle: bundle, locale: locale), mark: .off, fix: nil)
    }
    let accessibility: DictationReadiness.Item = accessibilityTrusted
        ? .init(kind: .accessibility, title: accessibilityTitle, state: allowed, mark: .ok, fix: nil)
        : .init(kind: .accessibility, title: accessibilityTitle, state: notAllowed, mark: globalOn ? .attention : .off, fix: globalOn ? .openAccessibilitySettings : nil)
    let modelItem: DictationReadiness.Item
    switch model {
    case .ready(let name):
        modelItem = .init(kind: .model, title: name, state: Copy.dictationStateReady(bundle: bundle, locale: locale), mark: .ok, fix: nil)
    case .missing(let name):
        modelItem = .init(kind: .model, title: name, state: Copy.dictationStateNotOnDisk(bundle: bundle, locale: locale), mark: .attention, fix: nil)
    case .downloading(let name):
        modelItem = .init(kind: .model, title: name, state: Copy.dictationStateDownloading(bundle: bundle, locale: locale), mark: .off, fix: nil)
    }
    var notes: [String] = []
    if microphone == .denied { notes.append(Copy.dictationNoteMicrophoneBlocked(bundle: bundle, locale: locale)) }
    if case .missing(let name) = model { notes.append(Copy.dictationNoteModelMissing(model: name, bundle: bundle, locale: locale)) }
    if accessibilityTrusted == false, globalOn { notes.append(Copy.dictationNoteNoAccessibility(bundle: bundle, locale: locale)) }
    if microphone == .notAsked { notes.append(Copy.dictationNoteAskedFirst(bundle: bundle, locale: locale)) }
    let items = [mic, accessibility, modelItem]
    if microphone == .denied {
        return DictationReadiness(tone: .blocked, title: Copy.dictationReadyBlocked(bundle: bundle, locale: locale), notes: notes, items: items)
    }
    let attention = items.filter { $0.mark == .attention }.count
    let tone: DictationReadiness.Tone = attention == 0 ? .ready : .attention
    return DictationReadiness(tone: tone, title: Copy.dictationReadyTitle(attention: attention, bundle: bundle, locale: locale), notes: notes, items: items)
}
