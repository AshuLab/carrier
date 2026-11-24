import Foundation

/// One line of the facts of a card that opens on a row (a session's, an epic's): a quiet label and a value. `kind` says how the value is
/// drawn, so a long path or branch is cut in the middle on one line instead of broken over several.
public struct CardFact: Equatable {
    public enum Kind: Equatable {
        /// Words, which wrap.
        case text
        /// A folder: monospaced, one line, cut in the middle, whole in its tooltip.
        case path
        /// A branch: the branch mark and its name, monospaced, one line, cut in the middle.
        case branch
        /// A chat agent: its account's mark and short name.
        case agent
    }

    public var label: String
    public var value: String
    public var kind: Kind = .text
    /// A line under the value, smaller and quiet: where it comes from or its whole path.
    public var detail: String?

    public init(label: String, value: String, kind: Kind = .text, detail: String? = nil) {
        self.label = label
        self.value = value
        self.kind = kind
        self.detail = detail
    }
}
