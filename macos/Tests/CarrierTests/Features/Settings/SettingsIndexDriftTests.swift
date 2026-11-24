import CarrierCore
import Foundation
import Testing

/// The search finds only what `settingsIndex` lists, so a row the views draw that is not listed cannot be found, and a listed one the views no
/// longer draw takes the person to nothing. The views are read as text: a title written as a string in a `SettingsTabRow`, a
/// `SettingsStackedRow` or a `SettingsGroup` has to be in the index, and every title in the index has to be written somewhere in the sources.
@Suite struct SettingsIndexDriftTests {
    private static let sources = testPaths().sources

    /// The text of every Swift file of a folder of the sources and its subfolders; fewer than `minimum` files fails.
    static func text(in folder: URL, minimum: Int) throws -> String {
        try swiftFiles(under: folder, minimum: minimum).sorted { $0.path < $1.path }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private static func text(of folder: String) throws -> String {
        try text(in: sources.appendingPathComponent(folder), minimum: 100)
    }

    /// Rows the pages draw that a search has no use for: a title that is a value (a model's name, an account), or one that exists only while a
    /// form is open.
    private static let notSearched: Set<String> = [
        "Details", "Label, icon and color", "Name", "Config folder", "Days", "Add account", "Carrier \\(version)",
        "Where it runs", "Advanced", "Remove account", "Accounts", "Models", "Version", "Signed out", "Use in an agent", "Found on this Mac", "Sign-ins and quotas", "Look at this Mac again", "In use", "Choosing is not available",
        "A session you stop using today", "Identity", "New sessions here", "Show when starting a session", "Agent", "Base branch", "Icon", "Tags", "Folder", "Folder not found", "Remote", "Remove",
        "New worktree", "After clone", "Command", "If it fails", "Worktrees and disk", "Worktrees", "Total", "Clean up", "Last clean up", "Let Carrier watch this project",
        "Reset to Agents", "Left alone", "Most dictations in a day", "Most words in a day", "Longest dictation", "Longest streak", "\\(metric.title) per day",
    ]

    @Test func everyTitleTheViewsDrawIsInTheIndex() throws {
        let views = try Self.text(of: "Carrier")
        let regex = try NSRegularExpression(pattern: #"(?:SettingsTabRow|SettingsStackedRow|SettingsGroup)\(\s*title:\s*"((?:[^"\\]|\\.)*)""#)
        let drawn = Set(regex.matches(in: views, range: NSRange(views.startIndex..., in: views)).compactMap { match in
            Range(match.range(at: 1), in: views).map { String(views[$0]) }
        })
        let indexed = Set(settingsIndex.flatMap { [$0.title, $0.group] })
        let missing = drawn.subtracting(indexed).subtracting(Self.notSearched).sorted()
        #expect(missing.isEmpty, "drawn by a page but not in settingsIndex (add it in CarrierCore/SettingsIndex.swift): \(missing)")
    }

    @Test func everyTitleInTheIndexIsWrittenInTheSources() throws {
        let code = try Self.text(of: "Carrier") + Self.text(of: "CarrierCore")
        let missing = settingsIndex.filter { $0.isPage == false }.map(\.title).filter { code.contains("\"\($0)\"") == false }
        #expect(Set(missing).isEmpty, "in settingsIndex but not drawn any more: \(Set(missing).sorted())")
    }

    @Test func readingAnEmptyFolderFails() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(throws: TooFewFiles.self) { try Self.text(in: scratch, minimum: 100) }
    }
}
