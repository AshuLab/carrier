import Foundation
import Testing
@testable import CarrierCore

private func utc() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

/// Noon of 15 November 2026, UTC.
private let noon = Date(timeIntervalSince1970: 1_794_744_000)

@Test func theGeneratorsMakeWhatTheirNamesSay() {
    let entries = longDictationEntries(count: 5000, perDay: 100, newest: noon)
    #expect(entries.count == 5000 && Set(entries.map(\.id)).count == 5000)
    #expect(entries == entries.sorted { $0.started > $1.started })
    #expect(dictationDays(entries, calendar: utc()).count == 50)
    #expect(entries.contains { $0.outcome == .copied } && entries.contains { $0.destination == DictationEntry.carrier })

    let reply = largeFilesReply(paths: 2000)
    #expect(reply.sections.map(\.files.count) == [500, 500, 500, 500])
    #expect(Set(reply.sections.flatMap(\.files).map(\.path)).count == 2000)

    let diff = longFileDiff(rows: 1000)
    #expect(diff.rows.count == 1000 && diff.truncated && diff.rows.filter { $0.sign == "@" }.count == 20)
    #expect(longFileDiff(rows: 100).truncated == false)
    #expect(longChatEvents(rounds: 715).count == 5005)
}

/// With CARRIER_PERF_FIXTURES=<folder>: `<folder>/fixtures`, a copy of the golden files whose `files` reply has 2000 paths and whose diff has
/// 1000 rows (for `--fixture <folder>/fixtures`), and `<folder>/home/app/state/dictations.jsonl` with 10,000 dictations (for
/// CARRIER_HOME=<folder>/home). Run it to measure by hand: `swift test --filter writesTheLargeFixtures`.
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["CARRIER_PERF_FIXTURES"] != nil))
func writesTheLargeFixturesForAMeasurementByHand() throws {
    // an empty value would make the folder the current one, and the copy below would replace its `fixtures`
    let path = try #require(ProcessInfo.processInfo.environment["CARRIER_PERF_FIXTURES"])
    try #require(path.isEmpty == false)
    let root = URL(fileURLWithPath: path)
    let golden = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")
    let fixtures = root.appendingPathComponent("fixtures")
    let fileManager = FileManager.default
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    try? fileManager.removeItem(at: fixtures)
    try fileManager.copyItem(at: golden, to: fixtures)

    let encoder = JSONEncoder()
    try encoder.encode(largeFilesReply(paths: 2000)).write(to: fixtures.appendingPathComponent("reply-files.json"))
    // the fixture server answers every file with the first reply of this array
    try encoder.encode([longFileDiff(rows: 1000)]).write(to: fixtures.appendingPathComponent("reply-filediff.json"))

    // the format of `DictationRecords`: ISO 8601 dates, one entry to a line
    let lines = JSONEncoder()
    lines.dateEncodingStrategy = .iso8601
    lines.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let entries = longDictationEntries(count: 10_000, perDay: 50, newest: Date())
    let jsonl = try entries.reversed().map { String(decoding: try lines.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
    let home = root.appendingPathComponent("home")
    let dictations = home.appendingPathComponent("app/state/dictations.jsonl")
    try fileManager.createDirectory(at: dictations.deletingLastPathComponent(), withIntermediateDirectories: true)
    try jsonl.write(to: dictations, atomically: true, encoding: .utf8)

    // the server owns two threads, two sockets and a folder of its own until it is stopped
    let server = try FixtureServer(fixtures: fixtures.path)
    defer { server.stop() }
    let records = DictationRecords(carrierFolder: home.path, keep: { true })
    #expect(records.entries.count == 10_000)
}
