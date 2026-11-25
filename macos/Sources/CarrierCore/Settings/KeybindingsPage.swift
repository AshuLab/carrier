import Foundation

/// What a row of the Keybindings page says for one action, from what the page knows of it. The titles of a command and of its group are keys the Shell's enums read.
public struct ShortcutRowText: Equatable, Sendable {
    /// The label of the key cap: the keys, or that it waits for them, or None.
    public let keys: String
    /// The line under the action's title.
    public let detail: String
    /// What flags the combination, when the system keeps it or another action has it.
    public let warning: String?
    public let defaultButton: String
    public let backToDefault: String
    public let label: String
    public let value: String
}

/// `refused` is the combination the last try was refused for, when it was for this action; `clash` the other action that has this one's combination.
public func shortcutRowText(
    command: ShortcutCommand, combo: KeyCombo?, clash: ShortcutCommand?, refused: KeyCombo?, recording: Bool, bundle: Bundle? = nil, locale: Locale = .current
) -> ShortcutRowText {
    let none = Copy.keybindingsNone(bundle: bundle, locale: locale)
    let keys = recording ? Copy.keybindingsPressKeys(bundle: bundle, locale: locale) : combo?.text ?? none
    let detail = command.defaultCombo.map { Copy.keybindingsDefault(combo: $0.text, bundle: bundle, locale: locale) } ?? Copy.keybindingsDefaultNone(bundle: bundle, locale: locale)
    var warning: String?
    if let refused {
        warning = Copy.keybindingsSystems(combo: refused.text, bundle: bundle, locale: locale)
    } else if let clash {
        warning = Copy.keybindingsAlso(action: clash.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale)
    }
    return ShortcutRowText(
        keys: keys, detail: detail, warning: warning, defaultButton: Copy.keybindingsDefaultButton(bundle: bundle, locale: locale),
        backToDefault: Copy.keybindingsBackToDefault(action: command.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale),
        label: Copy.keybindingsShortcutFor(action: command.title(bundle: bundle, locale: locale), bundle: bundle, locale: locale), value: combo?.text ?? none)
}
