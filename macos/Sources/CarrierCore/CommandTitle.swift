import Foundation

// The title of a command in the log: what it starts with, not the whole line. The engine sends the command as the call's
// argument; the full text is one click away in the opened call.

/// The longest a title gets before it ends in an ellipsis.
let maxCommandTitle = 46

/// "git fetch -q" and 2 for `git fetch -q && git branch -r | grep x`: the first command that does something, and how many more
/// are chained after it. Leading `VAR=value` assignments do not count as commands, and neither does a leading `cd …` when
/// something else follows it (a command that is only `cd` keeps it as its title). Quotes and `$( )` keep a `;`, `&&` or `|`
/// inside them from splitting.
public func commandTitle(_ command: String) -> (title: String, more: Int) {
    let parts = commands(in: command)
    var real = parts.filter { isAssignment($0) == false }
    if real.count > 1, real[0] == "cd" || real[0].hasPrefix("cd ") { real.removeFirst() }
    guard let first = real.first ?? parts.first else { return (command, 0) }
    let head = first.count > maxCommandTitle ? String(first.prefix(maxCommandTitle - 1)) + "…" : first
    return (head, max(real.count - 1, 0))
}

private func commands(in text: String) -> [String] {
    var parts: [String] = []
    var current = ""
    var quote: Character?
    var depth = 0
    var previous: Character = " "
    let characters = Array(text)
    func finish() {
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty == false { parts.append(trimmed) }
        current = ""
    }
    for (index, character) in characters.enumerated() {
        if let open = quote {
            if character == open { quote = nil }
            current.append(character)
        } else if character == "'" || character == "\"" {
            quote = character
            current.append(character)
        } else if character == "(" && previous == "$" {
            depth += 1
            current.append(character)
        } else if character == ")" && depth > 0 {
            depth -= 1
            current.append(character)
        } else if depth == 0 && (character == ";" || character == "|" || (character == "&" && isRedirect(characters, index) == false)) {
            // `&&` and `||` are two characters of the same separator: the empty piece between them is dropped by `finish`
            finish()
        } else {
            current.append(character)
        }
        previous = character
    }
    finish()
    return parts
}

/// The `&` of `2>&1`, `>&2` or `&>file` is part of a redirection, not a separator.
private func isRedirect(_ characters: [Character], _ index: Int) -> Bool {
    (index > 0 && characters[index - 1] == ">") || (index + 1 < characters.count && characters[index + 1] == ">")
}

/// `NAME=value`, `NAME=$(…)`: a piece that only sets a variable.
private func isAssignment(_ part: String) -> Bool {
    guard let equals = part.firstIndex(of: "="), equals != part.startIndex else { return false }
    let name = part[..<equals]
    guard name.allSatisfy({ $0.isUppercase || $0.isNumber || $0 == "_" }), name.first?.isNumber == false else { return false }
    let value = part[part.index(after: equals)...]
    return value.hasPrefix("$(") ? value.hasSuffix(")") : value.contains(" ") == false
}
