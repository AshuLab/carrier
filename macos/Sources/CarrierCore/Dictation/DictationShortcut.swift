import Foundation

// The shortcut of the global dictation and how it is activated (docs/macos/dictation.md): what the recorder in Settings accepts and how it is kept.

/// Toggle: the shortcut starts the dictation and the next press ends it. Hold: it listens while the keys are down and ends when they come up.
public enum DictationActivation: String, Sendable { case toggle, hold }

/// A key and its modifiers, as the hot key registers them: the key by its virtual key code, with the name it is shown by.
public struct DictationShortcut: Equatable {
    public let keyCode: Int
    public let modifiers: ShortcutModifiers
    public let key: String

    /// ⌥⇧ Space: ⌥ Space is held by ChatGPT and Handy (docs/research/global-dictation-input.md).
    public static let standard = DictationShortcut(keyCode: spaceKeyCode, modifiers: [.option, .shift], key: "Space")

    /// Esc on its own, which the widget holds while it is open; the recorder never takes it.
    public static let escape = DictationShortcut(keyCode: 53, modifiers: [], key: "Esc")

    /// As the menus write it: ⌃⌥⇧⌘ and the key.
    public var text: String {
        let symbols = [(ShortcutModifiers.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + (modifiers.isEmpty ? "" : " ") + key
    }

    fileprivate init(keyCode: Int, modifiers: ShortcutModifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// The form kept in the preferences: the modifiers, the key code and the name, with a colon between; one that does not pass the recorder's rules is nil.
    var stored: String { "\(modifiers.rawValue):\(keyCode):\(key)" }

    init?(stored: String) {
        let parts = stored.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let modifiers = Int(parts[0]), let keyCode = Int(parts[1]),
            case .accepted(let shortcut) = recordShortcut(keyCode: keyCode, characters: String(parts[2]), modifiers: ShortcutModifiers(rawValue: modifiers)),
            shortcut.key == parts[2]
        else { return nil }
        self = shortcut
    }
}

/// What the recorder does with the keys it was pressed: it takes them, or says why not.
public enum ShortcutRecording: Equatable {
    case accepted(DictationShortcut)
    case refused(String)
}

private let spaceKeyCode = 49

/// The keys that have no character to show, by key code.
private let keyNames: [Int: String] = [
    36: "Return", 48: "Tab", spaceKeyCode: "Space", 51: "Delete", 117: "Forward Delete", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
    123: "←", 124: "→", 125: "↓", 126: "↑",
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
]

/// A combination is taken when it has ⌃, ⌥ or ⌘ with it (⇧ alone would stop the key from typing), and the key has a name or one printable
/// character. `characters` is what the key types with no modifier held.
public func recordShortcut(
    keyCode: Int, characters: String, modifiers: ShortcutModifiers, bundle: Bundle? = nil, locale: Locale = .current
) -> ShortcutRecording {
    guard modifiers.isDisjoint(with: [.command, .control, .option]) == false else {
        return .refused(Copy.dictationShortcutNeedsModifier(bundle: bundle, locale: locale))
    }
    if let name = keyNames[keyCode] { return .accepted(DictationShortcut(keyCode: keyCode, modifiers: modifiers, key: name)) }
    guard characters.count == 1, characters.unicodeScalars.allSatisfy({ ![.control, .privateUse, .spaceSeparator].contains($0.properties.generalCategory) }) else {
        return .refused(Copy.dictationShortcutKeyRefused(bundle: bundle, locale: locale))
    }
    return .accepted(DictationShortcut(keyCode: keyCode, modifiers: modifiers, key: characters.uppercased()))
}

/// The keys line of the widget: what ends the dictation, and Esc.
public func dictationHint(shortcut: DictationShortcut, activation: DictationActivation, bundle: Bundle? = nil, locale: Locale = .current) -> String {
    activation == .hold
        ? Copy.dictationHintHold(shortcut: shortcut.text, bundle: bundle, locale: locale)
        : Copy.dictationHintToggle(shortcut: shortcut.text, bundle: bundle, locale: locale)
}
