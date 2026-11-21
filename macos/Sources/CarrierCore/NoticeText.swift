import Foundation

/// A sentence of the host or of the app as a notice says it: the first part is the title and the rest, when there is one, what to do. It breaks at the
/// first ". " or ": " ("No provider can start a session: claude is signed out." → the title and the reason); a text with neither is all title.
public func splitNotice(_ text: String) -> (title: String, detail: String?) {
    let breaks = [". ", ": "].compactMap { text.range(of: $0) }
    guard let first = breaks.min(by: { $0.lowerBound < $1.lowerBound }) else { return (text, nil) }
    let detail = String(text[first.upperBound...]).trimmingCharacters(in: .whitespaces)
    // the full stop ends the title's sentence and goes; a colon goes too, as the title does not need it
    return (String(text[..<first.lowerBound]), detail.isEmpty ? nil : detail)
}
