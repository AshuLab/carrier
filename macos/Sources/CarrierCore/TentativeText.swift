import Foundation

/// The text a dictation writes, kept apart from the field: where the tentative range is, and what an event does to a field's text. A
/// partial replaces the range's content, a final replaces it and closes it at the caret, an empty final removes it, and nothing outside
/// the range is touched, empty text or caret at either end included. Positions are UTF-16 units of the plain text, like the box's caret.
///
/// The person may edit the text while the dictation still writes (the last words of a stop, a model that answers at the end): an edit before
/// the range moves it, one after it leaves it, and one inside it ends the dictation's writing, so it never overwrites what the person did.
public struct TentativeText: Equatable, Sendable {
    public struct Edit: Equatable, Sendable {
        public let text: String
        public let caret: Int
    }

    public private(set) var start: Int
    public private(set) var length = 0
    /// The text as this left it (or as it was at the start), to find what the person changed since.
    private var known: String
    /// The person edited inside the range: what the dictation hears from now on is not written.
    public private(set) var lost = false

    /// A dictation that begins at `caret` in `text`.
    public init(caret: Int, in text: String) {
        start = caret
        known = text
    }

    /// Where the partial text is, nil when there is none.
    public var range: Range<Int>? { length > 0 ? start..<start + length : nil }

    /// What `event` does to `text`, with the caret where it is now; nil for an event that writes nothing. The caret stays where the person
    /// put it, and goes after the written text only when it was at or inside the range.
    public mutating func apply(_ event: DictationEvent, to text: String, caret: Int) -> Edit? {
        let heard: String, closes: Bool
        switch event {
        case .partial(let words): (heard, closes) = (words, false)
        case .final(let words): (heard, closes) = (words, true)
        case .failed: return nil
        }
        follow(text)
        guard lost == false else { return nil }
        let ns = text as NSString
        let from = min(max(start, 0), ns.length)
        let replaced = NSRange(location: from, length: min(length, ns.length - from))
        // the words that open a dictation are set apart from what is before them with a space, which is not part of the range
        let lead = length == 0 && opens(heard, after: from, in: ns) ? " " : ""
        let end = from + lead.utf16.count + (heard as NSString).length
        start = closes ? end : from + lead.utf16.count
        length = closes ? 0 : end - start
        let written = ns.replacingCharacters(in: replaced, with: lead + heard)
        known = written
        return Edit(text: written, caret: caret < NSMaxRange(replaced) ? (caret > from ? end : caret) : caret + end - NSMaxRange(replaced))
    }

    /// Whether `heard` needs a space before it at `position`: something that is not a space comes before, and it does not begin with a space
    /// or the mark that ends a phrase.
    private func opens(_ heard: String, after position: Int, in text: NSString) -> Bool {
        guard position > 0, let first = heard.first, first.isWhitespace == false, ".,;:!?)…".contains(first) == false else { return false }
        return text.substring(with: NSRange(location: position - 1, length: 1)).allSatisfy(\.isWhitespace) == false
    }

    /// Keeps what is there as final: the dictation ended with a partial on the screen.
    public mutating func close() {
        start += length
        length = 0
    }

    /// Finds what the person changed in `text` since this wrote it, as the part between the common beginning and the common end.
    private mutating func follow(_ text: String) {
        guard text != known else { return }
        let old = Array(known.utf16), new = Array(text.utf16)
        let shortest = min(old.count, new.count)
        var before = 0
        while before < shortest, old[before] == new[before] { before += 1 }
        var after = 0
        while after < shortest - before, old[old.count - 1 - after] == new[new.count - 1 - after] { after += 1 }
        if old.count - after <= start {
            start += new.count - old.count
        } else if before < start + length {
            lost = true
            length = 0
        }
        known = text
    }
}
