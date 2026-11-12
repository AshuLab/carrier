import Foundation

/// The text a dictation writes, kept apart from the field: where the tentative range is, and what an event does to a field's text. A
/// partial replaces the range's content, a final replaces it and closes it at the caret, an empty final removes it, and nothing outside
/// the range is touched, empty text or caret at either end included. Positions are UTF-16 units of the plain text, like the box's caret.
public struct TentativeText: Equatable, Sendable {
    public struct Edit: Equatable, Sendable {
        public let text: String
        public let caret: Int
    }

    public private(set) var start: Int
    public private(set) var length = 0

    /// A dictation that begins at `caret`.
    public init(caret: Int) { start = caret }

    /// Where the partial text is, nil when there is none.
    public var range: Range<Int>? { length > 0 ? start..<start + length : nil }

    /// What `event` does to `text`; nil for an event that writes nothing.
    public mutating func apply(_ event: DictationEvent, to text: String) -> Edit? {
        let heard: String, closes: Bool
        switch event {
        case .partial(let words): (heard, closes) = (words, false)
        case .final(let words): (heard, closes) = (words, true)
        case .failed: return nil
        }
        let ns = text as NSString
        let from = min(max(start, 0), ns.length)
        let replaced = NSRange(location: from, length: min(length, ns.length - from))
        let end = from + (heard as NSString).length
        start = closes ? end : from
        length = closes ? 0 : end - from
        return Edit(text: ns.replacingCharacters(in: replaced, with: heard), caret: end)
    }

    /// Keeps what is there as final: the dictation ended with a partial on the screen.
    public mutating func close() {
        start += length
        length = 0
    }
}
