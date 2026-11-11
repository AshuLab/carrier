import Foundation

// A text pasted into the message box that is too long to keep in it: it stays beside the box as a card with what it holds, and goes with
// the message as a fenced block marked `pasted`, which the conversation reads back to show the card again under the bubble.

/// A paste with more characters than this is not typed into the box.
public let pastedTextThreshold = 2000

/// What a pasted text holds, in one line: "3,412 chars · 87 lines · ~850 tokens" (a token is about four characters).
public func pasteStats(_ text: String) -> String {
    let chars = text.utf16.count
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
    return "\(chars.formatted()) chars · \(lines.formatted()) \(lines == 1 ? "line" : "lines") · ~\(TurnSummary.tokens(Double((chars + 3) / 4))) tokens"
}

/// The message the agent gets: what the person wrote, then each pasted text in a fenced block marked `pasted`, whose fence is longer than any
/// run of backticks inside it.
public func messageWithPastes(_ text: String, pastes: [String]) -> String {
    guard pastes.isEmpty == false else { return text }
    let blocks = pastes.map { pasted -> String in
        var run = 0, longest = 0
        for character in pasted {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + "pasted\n" + pasted.trimmingCharacters(in: .newlines) + "\n" + fence
    }
    return (text.isEmpty ? "" : text + "\n\n") + blocks.joined(separator: "\n\n")
}

/// The message as the person wrote it and the texts pasted into it; the text itself when it has no fenced block marked `pasted` that is closed.
public func splitPastes(_ text: String) -> (text: String, pastes: [String]) {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    var kept: [Substring] = []
    var pastes: [String] = []
    var index = 0
    while index < lines.count {
        let line = lines[index]
        index += 1
        let ticks = line.prefix { $0 == "`" }
        guard ticks.count >= 3, line.dropFirst(ticks.count) == "pasted",
              let close = lines[index...].firstIndex(where: { $0 == ticks })
        else {
            kept.append(line)
            continue
        }
        pastes.append(lines[index..<close].joined(separator: "\n"))
        index = close + 1
    }
    guard pastes.isEmpty == false else { return (text, []) }
    return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), pastes)
}

/// A message as a line or two says it (the queued one, a notice): what was typed, then a few words for each pasted text.
public func messagePreview(_ text: String) -> String {
    let split = splitPastes(text)
    guard split.pastes.isEmpty == false else { return text }
    let notes = split.pastes.map { pasted -> String in
        let lines = pasted.split(separator: "\n", omittingEmptySubsequences: false).count
        return "Pasted text · \(lines.formatted()) \(lines == 1 ? "line" : "lines")"
    }
    return ((split.text.isEmpty ? [] : [split.text]) + notes).joined(separator: "\n")
}
