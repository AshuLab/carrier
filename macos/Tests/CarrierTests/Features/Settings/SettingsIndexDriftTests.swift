@testable import CarrierCore
import Foundation
import Testing

/// The search finds only what `settingsIndex` lists, so a row the views draw that is not listed cannot be found, and a listed one the views no
/// longer draw takes the person to nothing. The views are read as text and paired with the index by identifier, never by title: the `id:` a
/// `SettingsTabRow`, a `SettingsStackedRow` or a `SettingsGroup` carries has to be one of the index, and the identifier of every entry of the
/// index has to be carried by a view.
@Suite struct SettingsIndexDriftTests {
    private static let sources = testPaths().sources

    /// The text of every Swift file of a folder of the sources and its subfolders; fewer than `minimum` files fails.
    static func text(in folder: URL, minimum: Int) throws -> String {
        try swiftFiles(under: folder, minimum: minimum).sorted { $0.path < $1.path }.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    private static func text(of folder: String) throws -> String {
        try text(in: sources.appendingPathComponent(folder), minimum: 100)
    }

    /// Titles drawn with no identifier, because a search has no use for them: a title that is a value (a model's name, an account), or one that
    /// exists only while a form is open. A row that is searched carries an identifier (`id:`) and has an entry.
    private static let notSearched: Set<String> = [
        "", "Details", "Label, icon and color", "Name", "Config folder", "Days", "Add account", "Carrier \\(version)",
        "Where it runs", "Advanced", "Remove account", "Accounts", "Models", "Version", "Signed out", "Use in an agent", "Found on this Mac", "Sign-ins and quotas", "Look at this Mac again", "In use", "Choosing is not available",
        "A session you stop using today", "Identity", "New sessions here", "Show when starting a session", "Agent", "Base branch", "Icon", "Tags", "Folder", "Folder not found", "Remote", "Remove",
        "New worktree", "After clone", "Command", "If it fails", "Worktrees and disk", "Worktrees", "Total", "Clean up", "Last clean up", "Let Carrier watch this project",
        "Reset to Agents", "Left alone", "Actions", "Most dictations in a day", "Most words in a day", "Longest dictation", "Longest streak", "\\(metric.title) per day",
    ]

    private static let rowViews = "SettingsTabRow|SettingsStackedRow|SettingsGroup|NavigationRow|ShortcutRecorderRow"

    private static func matches(_ pattern: String, in text: String) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// The identifiers the views carry: the one a row or a group is given (`id: "..."`) or anchored with, and the ones the models that a page is
    /// drawn from give (a shortcut's, a behavior row's, a role's and its stages', an engine row's, a dictation screen's, a health row's).
    private static func drawnIdentifiers() throws -> Set<String> {
        let views = try text(of: "Carrier")
        let core = try text(of: "CarrierCore")
        // a view (or the helper of a page that draws rows) given the identifier as its first argument, and the model groups and rows that carry one
        let carriers = "\(rowViews)|soundRow|row|HealthRow|HealthSection|BehaviorGroup|EngineGroup"
        let literal = try matches(#"\b(?:\#(carriers))\(\s*id:\s*"([^"]+)""#, in: views + core) + matches(#"settingsAnchored\("([^"]+)""#, in: views)
        let models = ShortcutCommand.allCases.map(\.rawValue) + behaviorGroups().flatMap { $0.rows.map(\.key) } + AgentRole.allCases.flatMap { [$0.rawValue] + $0.stages().map(\.id) }
            + EngineRowID.allCases.map(\.rawValue) + DictationScreen.allCases.map(\.rawValue)
        return Set(literal + models)
    }

    /// What is drawn with an identifier that no entry has.
    static func drawnWithNoEntry(_ drawn: Set<String>, entries: [SettingsEntry]) -> [String] {
        drawn.subtracting(entries.flatMap { [$0.rowID, $0.groupID] }).sorted()
    }

    /// The entries that no view draws (a page's own entry is the page's, not a row's).
    static func entriesNoViewDraws(_ drawn: Set<String>, entries: [SettingsEntry]) -> [String] {
        entries.filter { $0.isPage == false && drawn.contains($0.rowID) == false }.map(\.anchor)
    }

    @Test func everyRowTheViewsDrawIsAnEntryOfTheIndexByItsIdentifier() throws {
        let missing = Self.drawnWithNoEntry(try Self.drawnIdentifiers(), entries: settingsIndex)
        #expect(missing.isEmpty, "drawn by a page but not in settingsIndex (add it in CarrierCore/SettingsIndex.swift): \(missing)")
    }

    @Test func aRowThatIsSearchedCarriesAnIdentifier() throws {
        let views = try Self.text(of: "Carrier")
        let bare = try Self.matches(#"(?:\#(Self.rowViews))\(\s*title:\s*"((?:[^"\\]|\\.)*)""#, in: views)
        let missing = Set(bare).subtracting(Self.notSearched).sorted()
        #expect(missing.isEmpty, "drawn with a title and no id: (give it one, and an entry in settingsIndex): \(missing)")
    }

    @Test func everyEntryOfTheIndexIsDrawnWithItsIdentifier() throws {
        let missing = Self.entriesNoViewDraws(try Self.drawnIdentifiers(), entries: settingsIndex)
        #expect(missing.isEmpty, "in settingsIndex but not drawn any more: \(missing)")
    }

    @Test func aRowWithNoEntryAndAnEntryWithNoRowAreBothCaught() {
        let entry = SettingsEntry(page: .general, groupID: "menu-bar", group: "Menu bar", rowID: "icon-style", title: "Icon style")
        #expect(Self.drawnWithNoEntry(["icon-style", "menu-bar", "stray"], entries: [entry]) == ["stray"])
        #expect(Self.entriesNoViewDraws(["menu-bar"], entries: [entry]) == ["general.menu-bar.icon-style"])
        // a title is not what pairs them: the same identifier with another title is the same row
        let renamed = SettingsEntry(page: .general, groupID: "menu-bar", group: "Barra", rowID: "icon-style", title: "Estilo")
        #expect(Self.drawnWithNoEntry(["icon-style", "menu-bar"], entries: [renamed]).isEmpty && Self.entriesNoViewDraws(["icon-style"], entries: [renamed]).isEmpty)
    }

    @Test func readingAnEmptyFolderFails() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(throws: TooFewFiles.self) { try Self.text(in: scratch, minimum: 100) }
    }
}
