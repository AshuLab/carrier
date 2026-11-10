import Foundation

// The look of a fenced code block in the chat as plain values: which language it is (named, aliased by the file's extension, or guessed),
// its pieces for colouring, the lines of a diff, what Copy takes of a shell session. ponytail: a scanner of comments, strings, numbers and
// words against a keyword list per language, not a grammar; template strings nested in templates, heredocs and the like colour as plain text.

public enum CodeTokenKind: Equatable { case plain, keyword, string, number, comment, function, type, prompt }

public struct CodeToken: Equatable {
    public let text: String
    public let kind: CodeTokenKind

    public init(text: String, kind: CodeTokenKind) {
        self.text = text
        self.kind = kind
    }
}

/// One line of a diff, which gives it its tint.
public enum DiffLineKind: Equatable { case added, removed, hunk, meta, context }

private let aliases: [String: String] = [
    "js": "javascript", "javascript": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript", "node": "javascript",
    "ts": "typescript", "typescript": "typescript", "tsx": "typescript",
    "py": "python", "python": "python", "python3": "python",
    "swift": "swift", "go": "go", "golang": "go", "rs": "rust", "rust": "rust",
    "sh": "shell", "bash": "shell", "zsh": "shell", "shell": "shell", "console": "shell", "terminal": "shell", "fish": "shell",
    "json": "json", "jsonc": "json", "yaml": "yaml", "yml": "yaml", "sql": "sql",
    "java": "java", "kt": "kotlin", "kotlin": "kotlin", "rb": "ruby", "ruby": "ruby",
    "c": "c", "h": "c", "cpp": "cpp", "cc": "cpp", "hpp": "cpp", "c++": "cpp",
    "diff": "diff", "patch": "diff",
]

private let names: [String: String] = [
    "javascript": "JavaScript", "typescript": "TypeScript", "python": "Python", "swift": "Swift", "go": "Go", "rust": "Rust", "shell": "Shell",
    "json": "JSON", "yaml": "YAML", "sql": "SQL", "java": "Java", "kotlin": "Kotlin", "ruby": "Ruby", "c": "C", "cpp": "C++", "diff": "Diff",
]

/// The language a fence names, by its name or its file extension; nil when it is not one this knows.
public func codeLanguage(_ info: String?) -> String? {
    info.flatMap { aliases[$0.lowercased()] }
}

/// The language of a block: the one it names, or, when it names none, a guess from what it looks like (a diff, a shell session, JSON).
public func resolvedCodeLanguage(_ info: String?, code: String) -> String? {
    if let named = codeLanguage(info) { return named }
    guard info == nil else { return nil }
    let lines = code.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.contains(where: { $0.hasPrefix("diff --git") || $0.hasPrefix("@@ ") }) { return "diff" }
    if lines.first?.hasPrefix("$ ") == true { return "shell" }
    let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{") || trimmed.hasPrefix("["), (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil { return "json" }
    return nil
}

/// What the header says of a language: "JavaScript" for js, the fence's own word when it is not known, "Code" when there is none.
public func codeLanguageName(_ info: String?, resolved: String?) -> String {
    if let resolved, let name = names[resolved] { return name }
    return info ?? "Code"
}

/// What follows the opening fence of a block: its language and the file it is from, as in "ts src/a.ts", "ts:src/a.ts", "ts title=src/a.ts" or
/// "src/a.ts" alone (the extension gives the language).
public func fenceInfo(_ info: String) -> (language: String?, file: String?) {
    var tokens = info.split(whereSeparator: \.isWhitespace).map(String.init)
    guard var first = tokens.first else { return (nil, nil) }
    tokens.removeFirst()
    var file: String?
    func isPath(_ token: String) -> Bool { aliases[token.lowercased()] == nil && (token.contains("/") || (token.dropFirst().contains(".") && token.last != ".")) }
    if let colon = first.firstIndex(of: ":"), colon != first.startIndex {
        file = String(first[first.index(after: colon)...])
        first = String(first[..<colon])
    } else if isPath(first) {
        file = first
        first = file.flatMap { $0.split(separator: ".").last.map(String.init) } ?? first
    }
    if file == nil, let next = tokens.first {
        let value = next.hasPrefix("title=") ? String(next.dropFirst(6)).trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) : next
        if isPath(value) { file = value }
    }
    return (first, file)
}

/// Per-line kinds of a diff: `+` and `-` lines, `@@` hunks and the file header lines.
public func diffLines(_ code: String) -> [DiffLineKind] {
    code.components(separatedBy: "\n").map { line in
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff ") || line.hasPrefix("index ") { return .meta }
        if line.hasPrefix("@@") { return .hunk }
        if line.hasPrefix("+") { return .added }
        if line.hasPrefix("-") { return .removed }
        return .context
    }
}

/// What Copy puts on the pasteboard: the code, except a shell session written with `$ ` prompts, which gives the commands alone.
public func codeCopyText(_ code: String, language: String?) -> String {
    guard language == "shell" else { return code }
    let commands = code.components(separatedBy: "\n").filter { $0.hasPrefix("$ ") }.map { String($0.dropFirst(2)) }
    return commands.isEmpty ? code : commands.joined(separator: "\n")
}

private struct Spec {
    var keywords: Set<String>
    var line: [String] = ["//"]
    var block: (open: String, close: String)? = ("/*", "*/")
    var triple = false
    var backtick = false
    var caseless = false
    /// Words at the start of a command are the commands (a shell).
    var commands = false
    /// A word or string followed by a colon is a key (JSON, YAML).
    var keys = false
    /// A capitalised word is a type.
    var types = true
    /// A word followed by "(" is a call.
    var calls = true
    var dollarWords = false
}

private func words(_ text: String) -> Set<String> { Set(text.split(whereSeparator: \.isWhitespace).map(String.init)) }

private let cKeywords = words("if else for while do switch case break continue return default goto sizeof struct enum union typedef static const extern void volatile inline new delete class public private protected virtual template typename namespace using nullptr true false this")
private let specs: [String: Spec] = [
    "javascript": Spec(keywords: words("const let var function return if else for while do switch case break continue default new delete typeof instanceof in of class extends super import export from as async await yield try catch finally throw this null undefined true false void static get set"), backtick: true, dollarWords: true),
    "typescript": Spec(keywords: words("const let var function return if else for while do switch case break continue default new delete typeof instanceof in of class extends implements super import export from as async await yield try catch finally throw this null undefined true false void static get set interface type enum namespace declare readonly abstract public private protected keyof infer satisfies is"), backtick: true, dollarWords: true),
    "python": Spec(keywords: words("def class return if elif else for while break continue pass import from as with try except finally raise lambda yield async await global nonlocal in is not and or None True False del assert self"), line: ["#"], block: nil, triple: true),
    "swift": Spec(keywords: words("let var func return if else guard switch case default for while repeat break continue in struct class enum protocol extension import init deinit self Self super nil true false try catch throw throws rethrows async await actor private fileprivate internal public open static final override mutating where as is some any typealias associatedtype defer inout lazy weak unowned @MainActor @State @Binding @Observable")),
    "go": Spec(keywords: words("package import func return if else for range switch case default break continue go defer select chan map struct interface type var const fallthrough goto nil true false iota"), backtick: true),
    "rust": Spec(keywords: words("fn let mut const static return if else match for while loop break continue in struct enum impl trait type use mod pub crate self Self super as ref move async await dyn where unsafe extern true false Some None Ok Err")),
    "shell": Spec(keywords: words("if then else elif fi for while until do done case esac in function select return exit export local readonly unset source alias set"), line: ["#"], block: nil, commands: true, types: false, calls: false),
    "json": Spec(keywords: words("true false null"), line: [], block: nil, keys: true, types: false, calls: false),
    "yaml": Spec(keywords: words("true false null yes no on off"), line: ["#"], block: nil, keys: true, types: false, calls: false),
    "sql": Spec(keywords: words("select from where and or not in is null as join left right inner outer full cross on group by order having limit offset insert into values update set delete create table alter drop index view primary key foreign references unique default distinct union all case when then else end exists between like asc desc with returning true false"), line: ["--"], caseless: true, types: false),
    "java": Spec(keywords: words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record null true false")),
    "kotlin": Spec(keywords: words("fun val var return if else when for while do break continue in is as class interface object enum data sealed open abstract override private protected public internal import package try catch finally throw this super null true false suspend companion init lateinit by where typealias")),
    "ruby": Spec(keywords: words("def end class module if elsif else unless case when while until for in do begin rescue ensure raise return yield self nil true false and or not then require require_relative include extend attr_accessor attr_reader puts"), line: ["#"], block: nil),
    "c": Spec(keywords: cKeywords),
    "cpp": Spec(keywords: cKeywords),
]

/// The pieces of a block in order; their text put together is the code. A language this does not know is one plain piece.
public func codeTokens(_ code: String, language: String?) -> [CodeToken] {
    guard let language, let spec = specs[language] else { return [CodeToken(text: code, kind: .plain)] }
    let c = Array(code)
    var out: [CodeToken] = []
    var plain = ""
    var atCommand = true
    func flush() {
        if plain.isEmpty == false { out.append(CodeToken(text: plain, kind: .plain)); plain = "" }
    }
    func emit(_ text: String, _ kind: CodeTokenKind) {
        flush()
        out.append(CodeToken(text: text, kind: kind))
    }
    func starts(_ prefix: String, at index: Int) -> Bool {
        let p = Array(prefix)
        return index + p.count <= c.count && c[index..<index + p.count].elementsEqual(p)
    }
    func nextSignificant(from index: Int) -> Character? {
        var k = index
        while k < c.count, c[k] == " " || c[k] == "\t" { k += 1 }
        return k < c.count ? c[k] : nil
    }
    var i = 0
    while i < c.count {
        let ch = c[i]
        let lineStart = i == 0 || c[i - 1] == "\n"
        if language == "shell", ch == "$", lineStart, starts("$ ", at: i) {
            emit("$ ", .prompt)
            i += 2
            continue
        }
        if let marker = spec.line.first(where: { starts($0, at: i) }), marker != "#" || i == 0 || c[i - 1].isWhitespace {
            var j = i
            while j < c.count, c[j] != "\n" { j += 1 }
            emit(String(c[i..<j]), .comment)
            i = j
            continue
        }
        if let block = spec.block, starts(block.open, at: i) {
            var j = i + block.open.count
            while j < c.count, starts(block.close, at: j) == false { j += 1 }
            j = min(c.count, j + block.close.count)
            emit(String(c[i..<j]), .comment)
            i = j
            continue
        }
        if spec.triple, starts("\"\"\"", at: i) || starts("'''", at: i) {
            let quote = String(c[i...i + 2])
            var j = i + 3
            while j < c.count, starts(quote, at: j) == false { j += 1 }
            j = min(c.count, j + 3)
            emit(String(c[i..<j]), .string)
            i = j
            atCommand = false
            continue
        }
        if ch == "\"" || ch == "'" || (ch == "`" && spec.backtick) {
            var j = i + 1
            while j < c.count {
                if c[j] == "\\" { j += 2; continue }
                if c[j] == ch { j += 1; break }
                if c[j] == "\n", ch != "`" { break }
                j += 1
            }
            j = min(j, c.count)
            let isKey = spec.keys && nextSignificant(from: j) == ":"
            emit(String(c[i..<j]), isKey ? .type : .string)
            i = j
            atCommand = false
            continue
        }
        if ch.isNumber, i == 0 || (c[i - 1].isLetter || c[i - 1] == "_" || c[i - 1].isNumber) == false {
            var j = i
            while j < c.count, c[j].isLetter || c[j].isNumber || c[j] == "." || c[j] == "_" { j += 1 }
            emit(String(c[i..<j]), .number)
            i = j
            atCommand = false
            continue
        }
        if ch.isLetter || ch == "_" || (ch == "@" && language == "swift") || (ch == "$" && spec.dollarWords) {
            var j = i + 1
            while j < c.count, c[j].isLetter || c[j].isNumber || c[j] == "_" || (c[j] == "$" && spec.dollarWords) { j += 1 }
            let word = String(c[i..<j])
            let lookup = spec.caseless ? word.lowercased() : word
            let kind: CodeTokenKind
            if spec.keywords.contains(lookup) {
                kind = .keyword
            } else if spec.commands, atCommand {
                kind = .function
            } else if spec.keys, nextSignificant(from: j) == ":" {
                kind = .type
            } else if spec.calls, nextSignificant(from: j) == "(" || (j < c.count && c[j] == "!" && nextSignificant(from: j + 1) == "(") {
                kind = .function
            } else if spec.types, ch.isUppercase {
                kind = .type
            } else {
                kind = .plain
            }
            if kind == .plain { plain += word } else { emit(word, kind) }
            i = j
            atCommand = spec.keywords.contains(lookup) && language == "shell"
            continue
        }
        plain.append(ch)
        if ch == "\n" || ch == ";" || ch == "|" || ch == "&" || ch == "(" || ch == "{" { atCommand = true } else if ch.isWhitespace == false { atCommand = false }
        i += 1
    }
    flush()
    return out
}
