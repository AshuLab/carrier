import Foundation

/// What the Pieces gallery (`PiecesGalleryView`, only under `--fixture`) draws the pieces with that is not words: code, paths, numbers and names of
/// tools, made up. Its words (the sentences the pieces show, the names of their states) are copy keys read through `Copy` (`pieceSample`,
/// `pieceState`, `piecesKind`), so the gallery reads in the language of the app like any other page.
public enum PiecesGalleryData {
    public static let path = "/Users/dev/carrier/macos/Sources"
    public static let branch = "feat/the-pieces-gallery"
    public static let file = "Parser.swift"
    public static let initials = "CA"
    public static let symbol = "star.fill"
    public static let count = "3"
    public static let number = 12
    public static let pullRequest = 1189
    public static let link = URL(string: "https://github.com/AshuLab/carrier/pull/1189")!
    public static let tools = ["claude", "codex", "antigravity"]
    /// A tool the app has no mark for: its first letter is drawn.
    public static let unknownTool = "unknown"
    public static let chips = ["claude", "codex", "main", "v1.2.3", "pnpm", "feat/login", "macos"]
    /// A command's output: the first line red when it failed.
    public static let lines = ["error: expected 3 but got 4", "  at src/parser.ts:12:5", "  at src/main.ts:40:1"]

    public static let icons: [AppIcon] = [.search, .copy, .check, .archive, .clock, .code]

    public static let code = """
        // reads a value
        func read(_ text: String) -> Int {
            let value = Int(text) ?? 0
            return value + 42
        }
        """

    public static let diff = """
        --- a/Parser.swift
        +++ b/Parser.swift
        @@ -1,4 +1,4 @@
         func read(_ text: String) -> Int {
        -    let value = Int(text)
        +    let value = Int(text) ?? 0
             return value
         }
        """

    /// Longer than a block shows before it folds.
    public static let longCode = (1...40).map { "let value\($0) = \($0)" }.joined(separator: "\n")

    /// A made-up catalog for the theme gallery: the real themes over and over, each cell numbered so the names differ.
    public static func themeCells(count: Int) -> [ThemeCell] {
        let themes = Theme.allCases
        return (0..<count).map { ThemeCell(id: "cell\($0)", title: "\(themes[$0 % themes.count].title()) \($0 + 1)", theme: themes[$0 % themes.count]) }
    }
}
