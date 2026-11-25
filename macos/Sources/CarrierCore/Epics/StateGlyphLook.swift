import Foundation

/// A color a state's glyph is drawn in: the ones the app tells states apart by. The front-end maps each to the system's.
public enum GlyphTint: Equatable, Sendable {
    case red, orange, blue, green, gray
}

/// What an epic's state glyph is made of: a ring that turns, a filled disc with a mark (or, with "Tell states apart by shape" on, the symbol of its
/// `shape`) or a hollow circle; in `tint`; and the words a screen reader says for it.
public struct StateGlyphLook: Equatable, Sendable {
    public enum Form: Equatable, Sendable { case ring, disc, hollow }

    public var form: Form
    public var tint: GlyphTint
    public var mark: String
    public var shape: StateShape?
    public var label: String
}

extension Attention {
    /// Red when something failed, orange when a person's input is needed (and for an epic whose kind is not known).
    public var tint: GlyphTint { self == .error ? .red : .orange }
}

extension EpicMenuState {
    /// What the state is called where it has no words beside it.
    public func label(bundle: Bundle? = nil, locale: Locale = .current) -> String {
        switch self {
        case .needsYou: Copy.epicsStateNeedsAttention(bundle: bundle, locale: locale)
        case .running: Copy.epicsStateRunning(bundle: bundle, locale: locale)
        case .waiting: Copy.epicsStateUpNext(bundle: bundle, locale: locale)
        case .ready: Copy.epicsStateReady(bundle: bundle, locale: locale)
        case .done: Copy.epicsStateDone(bundle: bundle, locale: locale)
        case .cancelled: Copy.epicsStateCancelled(bundle: bundle, locale: locale)
        }
    }

    /// The glyph of the state: a turning ring while it runs, a disc with a mark when it needs you (red when `attention` says it failed), a hollow circle while
    /// it waits, a blue disc with a tick when it is ready, and a green or grey one when it is done or cancelled.
    public func glyphLook(attention: Attention? = nil, bundle: Bundle? = nil, locale: Locale = .current) -> StateGlyphLook {
        let (form, tint, mark): (StateGlyphLook.Form, GlyphTint, String) =
            switch self {
            case .running: (.ring, .green, "")
            case .needsYou: (.disc, (attention ?? .input).tint, "!")
            case .waiting: (.hollow, .gray, "")
            case .ready: (.disc, .blue, "✓")
            case .done: (.disc, .green, "✓")
            case .cancelled: (.disc, .gray, "✕")
            }
        return StateGlyphLook(form: form, tint: tint, mark: mark, shape: shape(attention: attention), label: label(bundle: bundle, locale: locale))
    }
}
