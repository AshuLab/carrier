import Foundation

// What the person can invoke from the message box (skills and commands), whatever the provider calls it. The host lists them as
// `ChatCommand`s and takes an invocation as a command id and what follows its name; how each provider is told is the host's. The box
// types `/name arguments` and the app finds the command in the text, so a provider that has none lists none and the box is plain.

/// One thing to invoke, as the host lists it.
public struct ChatCommand: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable, CaseIterable { case skill, command }

    /// The provider's own identity for it: what a send names it by.
    public let id: String
    /// What follows the slash.
    public let name: String
    public let description: String
    /// What it takes after its name, when the provider says (`<file>`).
    public let argumentHint: String?
    /// A skill is the person's or a plugin's; a command is the provider's own.
    public let kind: Kind

    public init(id: String, name: String, description: String, argumentHint: String? = nil, kind: Kind = .skill) {
        self.id = id
        self.name = name
        self.description = description
        self.argumentHint = argumentHint
        self.kind = kind
    }

    /// What a plugin's skill is prefixed with (`solve` of `solve:land`), when it is.
    public var source: String? { name.lastIndex(of: ":").map { String(name[..<$0]) } }
    /// The description without the `(plugin) ` some providers put before it, as the name already says it.
    public var summary: String {
        guard let source, description.hasPrefix("(\(source)) ") else { return description }
        return String(description.dropFirst(source.count + 3))
    }
    /// The name without its plugin.
    public var shortName: String { name.lastIndex(of: ":").map { String(name[name.index(after: $0)...]) } ?? name }
}

/// The word under the caret when it starts with a slash: its range (UTF-16, as `NSString` counts) and what is typed of its name, that
/// is what lies between the slash and the caret. A slash opens a word only after a space or at the start (a path is not a command), and
/// a word with another slash in it is not a name.
public struct CommandToken: Equatable {
    public let range: NSRange
    public let query: String
}

private func isBlank(_ unit: unichar) -> Bool {
    UnicodeScalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
}

public func commandToken(in text: String, cursor: Int) -> CommandToken? {
    let ns = text as NSString
    guard cursor >= 0, cursor <= ns.length else { return nil }
    var start = cursor
    while start > 0, isBlank(ns.character(at: start - 1)) == false { start -= 1 }
    var end = cursor
    while end < ns.length, isBlank(ns.character(at: end)) == false { end += 1 }
    guard start < cursor, ns.character(at: start) == 0x2F else { return nil }
    let query = ns.substring(with: NSRange(location: start + 1, length: cursor - start - 1))
    return query.contains("/") ? nil : CommandToken(range: NSRange(location: start, length: end - start), query: query)
}

/// The text with the chosen command in place of the word the caret was in, and where the caret goes: after one space that ends the name,
/// the one that was already there or a new one.
public func inserting(_ command: ChatCommand, over token: CommandToken, in text: String) -> (text: String, cursor: Int) {
    let ns = text as NSString
    let after = NSMaxRange(token.range)
    let spaced = after < ns.length && ns.character(at: after) == 0x20
    let name = "/\(command.name)"
    let replaced = ns.replacingCharacters(in: token.range, with: spaced ? name : name + " ")
    return (replaced, token.range.location + (name as NSString).length + 1)
}

/// The text with a slash at its end, after a space when the text does not end in one, to open the list of commands for a person who does
/// not know that a slash does.
public func appendingSlash(to text: String) -> (text: String, cursor: Int) {
    let ns = text as NSString
    let spaced = ns.length > 0 && isBlank(ns.character(at: ns.length - 1)) == false
    let appended = text + (spaced ? " /" : "/")
    return (appended, (appended as NSString).length)
}

/// The commands a typed name leads to: skills before the provider's own commands, and in each the names that start with it before the
/// ones that only contain it (or whose description does), each in the order the provider listed.
public func commandMatches(_ commands: [ChatCommand], query: String) -> [ChatCommand] {
    let needle = query.lowercased()
    func rank(_ command: ChatCommand) -> Int? {
        let name = command.name.lowercased()
        if needle.isEmpty || name.hasPrefix(needle) { return 0 }
        if name.contains(needle) { return 1 }
        return command.description.lowercased().contains(needle) ? 2 : nil
    }
    let ranked = commands.compactMap { command in rank(command).map { (command, $0) } }
    return ranked.sorted { ($0.0.kind == .skill ? 0 : 1, $0.1) < ($1.0.kind == .skill ? 0 : 1, $1.1) }.map(\.0)
}

/// The command a message invokes: a text that starts with a slash and the name of one of the commands, then nothing or whitespace.
/// `arguments` is what follows, trimmed. A text that starts with a slash and names none is an ordinary message.
public func invokedCommand(in text: String, among commands: [ChatCommand]) -> (command: ChatCommand, arguments: String)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/") else { return nil }
    let name = trimmed.dropFirst().prefix { $0.isWhitespace == false }
    guard let command = commands.first(where: { $0.name == name }) else { return nil }
    return (command, trimmed.dropFirst(1 + name.count).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// The commands a text names as words: each word that is a slash and the exact name of one of the commands, and where it is (UTF-16).
/// While the text is being written a word counts once a space follows it, so one still being typed is not taken; in a sent message
/// (`ended`) the last word counts too.
public func commandSpans(in text: String, among commands: [ChatCommand], ended: Bool = false) -> [(range: NSRange, command: ChatCommand)] {
    let ns = text as NSString
    let byName = Dictionary(commands.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    var spans: [(range: NSRange, command: ChatCommand)] = []
    var i = 0
    while i < ns.length {
        if isBlank(ns.character(at: i)) { i += 1; continue }
        var end = i
        while end < ns.length, isBlank(ns.character(at: end)) == false { end += 1 }
        let word = ns.substring(with: NSRange(location: i, length: end - i))
        if end < ns.length || ended, word.hasPrefix("/"), let command = byName[String(word.dropFirst())] {
            spans.append((NSRange(location: i, length: end - i), command))
        }
        i = end
    }
    return spans
}
