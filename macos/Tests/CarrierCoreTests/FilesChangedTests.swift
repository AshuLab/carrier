import AppKit
import Foundation
import Testing
@testable import CarrierCore

// MARK: icons

@Test(arguments: [
    ("src/app.ts", FileCategory.code), ("a/b/View.swift", .code), ("index.html", .code),
    ("package.json", .data), ("ci/build.yml", .data), ("Dockerfile", .data), (".env", .data),
    ("docs/readme.md", .text), ("notes.txt", .text),
    ("logo.png", .image), ("icon.svg", .image),
    ("app.css", .style), ("theme.scss", .style),
    ("scripts/run.sh", .shell), ("Makefile", .shell), (".zshrc", .shell),
    ("Cargo.lock", .lock), ("pnpm-lock.yaml", .lock), ("package-lock.json", .lock),
    ("src/token.test.ts", .test), ("src/token.spec.js", .test), ("tests/helpers.ts", .test), ("foo_test.go", .test), ("test_foo.py", .test),
    ("archive.xyz", .other), ("LICENSE", .other), (".gitignore", .other), ("", .other),
])
func eachPathGetsItsCategory(path: String, category: FileCategory) {
    #expect(fileCategory(path) == category, "\(path)")
}

@Test func upperCaseNamesAndExtensionsAreRead() {
    #expect(fileCategory("README.MD") == .text)
    #expect(fileCategory("SRC/APP.TS") == .code)
    #expect(fileCategory("DOCKERFILE") == .data)
    #expect(fileCategory("Gemfile.LOCK") == .lock)
}

@Test func aTestFileIsATestWhateverItsLanguage() {
    #expect(fileCategory("src/a.test.json") == .test)
    #expect(fileCategory("Tests/CarrierTests/X.swift") == .test)
}

@Test func everyCategoryHasItsOwnRealSymbol() {
    let symbols = FileCategory.allCases.map(\.symbol)
    #expect(Set(symbols).count == FileCategory.allCases.count)
    for symbol in symbols { #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)") }
}

// MARK: model

private func file(_ path: String, _ added: Int, _ removed: Int, alsoIn: [String] = []) -> FilesReply.File {
    .init(path: path, added: added, removed: removed, alsoIn: alsoIn)
}

private func section(_ id: String, _ kind: String, _ files: [FilesReply.File]) -> FilesReply.Section {
    .init(id: id, kind: kind, title: id.capitalized, added: 0, removed: 0, files: files)
}

@Test func theFilesAreGroupedBySectionWithTotalsPerSectionAndOverall() {
    let model = filesChangedModel(FilesReply(sections: [
        section("lane-1", "lane", [file("src/a.ts", 10, 2), file("docs/b.md", 5, 0)]),
        section("merged", "merged", [file("src/c.ts", 100, 20)]),
    ]))
    #expect(model.sections.map(\.id) == ["lane-1", "merged"])
    #expect(model.sections.map(\.added) == [15, 100])
    #expect(model.sections.map(\.removed) == [2, 20])
    #expect((model.fileCount, model.added, model.removed) == (3, 115, 22))
    #expect((model.fileCount, model.added, model.removed) == (3, 115, 22))
    let row = model.sections[0].files[0]
    #expect((row.directory, row.name, row.category) == ("src/", "a.ts", .code))
    #expect(row.icon == fileIcon("src/a.ts"))
}

@Test func aFileAtTheRootHasNoDirectory() {
    let model = filesChangedModel(FilesReply(sections: [section("s", "session", [file("package.json", 1, 1)])]))
    #expect((model.sections[0].files[0].directory, model.sections[0].files[0].name) == ("", "package.json"))
}

@Test func aFileInTwoSectionsCountsOnceOverallAndIsFlaggedInBothWorkingOnes() {
    let model = filesChangedModel(FilesReply(sections: [
        section("lane-1", "lane", [file("src/t.ts", 30, 6, alsoIn: ["lane-2"])]),
        section("lane-2", "lane", [file("src/t.ts", 4, 1, alsoIn: ["lane-1"])]),
    ]))
    #expect(model.fileCount == 1)
    #expect((model.fileCount, model.added, model.removed) == (1, 34, 7))
    #expect(model.sections[0].files[0].alsoIn == ["Lane-2"])
    #expect(model.sections[1].files[0].alsoIn == ["Lane-1"])
}

@Test func aMergedSectionNeverCarriesTheAlsoInWarning() {
    let model = filesChangedModel(FilesReply(sections: [
        section("lane-1", "lane", [file("src/t.ts", 3, 0, alsoIn: ["merged"])]),
        section("merged", "merged", [file("src/t.ts", 9, 0, alsoIn: ["lane-1"])]),
    ]))
    #expect(model.sections.flatMap(\.files).map(\.alsoIn) == [[], []])
}

@Test func aSectionWithNoFilesStaysWithZeroTotals() {
    let model = filesChangedModel(FilesReply(sections: [section("s", "session", []), section("t", "session", [file("a.ts", 1, 0)])]))
    #expect(model.sections.count == 2)
    #expect((model.sections[0].files.count, model.sections[0].added, model.sections[0].removed) == (0, 0, 0))
    #expect(model.isEmpty == false)
}

@Test func withNoFilesAnywhereTheModelIsEmpty() {
    #expect(filesChangedModel(nil).isEmpty)
    #expect(filesChangedModel(FilesReply(sections: [])).isEmpty)
    #expect(filesChangedModel(FilesReply(sections: [section("s", "session", [])])).isEmpty)
}

@Test func workingSectionsStartOpenAndMergedOnesFolded() {
    let model = filesChangedModel(FilesReply(sections: [
        section("lane-1", "lane", [file("a.ts", 1, 0)]),
        section("sess", "session", [file("b.ts", 1, 0)]),
        section("merged", "merged", [file("c.ts", 1, 0)]),
    ]))
    #expect(model.sections.map(\.openByDefault) == [true, true, false])
}

@Test func theFixtureReplyReadsAsTheEngineSendsIt() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-files.json")
    let model = filesChangedModel(try JSONDecoder().decode(FilesReply.self, from: Data(contentsOf: url)))
    #expect(model.sections.map(\.openByDefault) == [true, true, false, true])
    #expect(model.sections[0].files[0].alsoIn == ["Lane 2"])
    #expect(model.fileCount == 3)
}

@Test func theFiveSquaresFollowTheProportionAndKeepBothColoursWhenBothExist() {
    #expect(diffSquares(added: 0, removed: 0) == (0, 0))
    #expect(diffSquares(added: 9, removed: 0) == (5, 0))
    #expect(diffSquares(added: 0, removed: 3) == (0, 5))
    #expect(diffSquares(added: 50, removed: 50) == (3, 2))
    #expect(diffSquares(added: 1000, removed: 1) == (4, 1))
    #expect(diffSquares(added: 1, removed: 1000) == (1, 4))
}

// MARK: fragments

@Test func aReplyBecomesTheRowsTheTranscriptDrawsWithAHunkRowBetweenFragments() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures/reply-filediff.json")
    let replies = try JSONDecoder().decode([FileDiffReply].self, from: Data(contentsOf: url))
    guard case .rows(let rows, let truncated) = fileFragment(replies[0]) else { Issue.record("no rows"); return }
    #expect(rows.map(\.sign) == [.hunk, .context, .removed, .added, .added, .context, .context, .hunk, .context, .removed, .added, .context])
    #expect(rows[0].text == "@@ -1,4 +1,5 @@" && rows[2].text == "const alg = \"HS256\";")
    #expect(truncated)
    #expect(fileFragment(FileDiffReply(rows: [.init(sign: "+", text: String(repeating: "x", count: 3000))], truncated: false, note: nil))
        == .rows([DiffRow(sign: .added, text: String(repeating: "x", count: maxDiffLineLength) + "…")], truncated: false))
}

@Test func aReplyWithANoteIsOneLine() {
    let note = { (value: String?) in fileFragment(FileDiffReply(rows: [], truncated: false, note: value)) }
    #expect(note("binary") == .note("Binary file: no preview"))
    #expect(note("too-big") == .note("Too big: no preview"))
    #expect(note("no-changes") == .note("No changes: the file is as it was"))
    #expect(note("something-new") == .note("No preview"))
    #expect(note(nil) == .note("No changes: the file is as it was"))
}
