import Foundation
import Testing
@testable import CarrierCore

private func folder() -> String { NSTemporaryDirectory() + "carrier-dictation-records-\(UUID().uuidString)" }

/// A history opened again from `folder`, once its file is read.
@MainActor private func reopened(_ folder: String, keep: Bool = true, calendar: Calendar = .current) async -> DictationRecords {
    let records = DictationRecords(carrierFolder: folder, keep: { keep }, calendar: calendar)
    await records.load()
    return records
}

private func entry(
    _ text: String, at seconds: TimeInterval = 0, outcome: DictationOutcome = .pasted, destination: String = "Notes", cleaned: String? = nil
) -> DictationEntry {
    DictationEntry(
        started: Date(timeIntervalSince1970: 1_700_000_000 + seconds), text: text, cleaned: cleaned, model: "Apple", transcription: 0.4, audio: 6,
        destination: destination, outcome: outcome)
}

@MainActor @Test func anEntryIsRecordedWithItsFieldsAndIsThereAfterARelaunch() async throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let first = entry("hola mundo", at: 0)
    let second = entry("uno dos tres", at: 60, outcome: .copied, destination: DictationEntry.widgetOnly)
    #expect(records.record(first) && records.record(second))
    #expect(records.entries == [second, first] && first.words == 2 && second.words == 3)
    #expect(records.path == folder + "/app/state/dictations.jsonl")
    #expect(try String(contentsOfFile: records.path, encoding: .utf8).split(separator: "\n").count == 2)
    #expect(try FileManager.default.attributesOfItem(atPath: records.path)[.posixPermissions] as? Int == 0o600)
    let reread = await reopened(folder)
    #expect(reread.entries == [second, first])
}

@MainActor @Test func aTextWithNewlinesAndQuotesStaysOneLineAndComesBackTheSame() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let odd = entry("dijo \"hola\"\nluego / adiós", cleaned: "Dijo \"hola\".")
    records.record(odd)
    let reread = await reopened(folder)
    #expect(reread.entries == [odd])
}

@MainActor @Test func aDictationWithNoWordsRecordsNothingWhateverItsOutcome() {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    for outcome in DictationOutcome.allCases { #expect(records.record(entry("  \n", outcome: outcome)) == false) }
    #expect(records.entries.isEmpty && FileManager.default.fileExists(atPath: records.path) == false)
}

@MainActor @Test func withTheSwitchOffNothingNewIsRecordedAndWhatThereIsStays() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    nonisolated(unsafe) var keep = true
    let records = DictationRecords(carrierFolder: folder, keep: { keep })
    let kept = entry("hola")
    records.record(kept)
    keep = false
    #expect(records.record(entry("adiós", at: 5)) == false)
    #expect(records.entries == [kept])
    let reread = await reopened(folder, keep: false)
    #expect(reread.entries == [kept])
    // a delete is the person's own, so it works with the switch off too
    await records.delete(kept.id)
    let rereadOff = await reopened(folder, keep: false)
    #expect(records.entries.isEmpty && rereadOff.entries.isEmpty)
}

@MainActor @Test func deletingAnEntryRemovesOnlyThatOneFromTheListAndTheFile() async throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let (a, b, c) = (entry("uno", at: 0), entry("dos", at: 10), entry("tres", at: 20))
    [a, b, c].forEach { records.record($0) }
    await records.delete(b.id)
    await records.delete(UUID())
    #expect(records.entries == [c, a])
    #expect(try FileManager.default.attributesOfItem(atPath: records.path)[.posixPermissions] as? Int == 0o600)
    let reread = await reopened(folder)
    #expect(reread.entries == [c, a])
    records.record(entry("cuatro", at: 30))
    let rereadLast = await reopened(folder)
    #expect(rereadLast.entries.map(\.text) == ["cuatro", "tres", "uno"])
}

@MainActor @Test func aLineThatDoesNotReadIsLeftOutAndTheRestLoads() async throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let good = entry("hola")
    records.record(good)
    let handle = try #require(FileHandle(forWritingAtPath: records.path))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{\"id\":\"cut here".utf8))
    try handle.close()
    let reread = await reopened(folder)
    #expect(reread.entries == [good])
}

@Test func theSearchLooksAtTheTextTheCleanedTextAndTheDestinationInAnyCaseAndTheFilterAtTheOutcome() {
    let all = [
        entry("Revisa el PRESUPUESTO", at: 0, destination: "Notes"),
        entry("hola", at: 1, outcome: .copied, destination: DictationEntry.widgetOnly, cleaned: "Hola, presupuesto."),
        entry("adiós", at: 2, outcome: .cancelled, destination: "Slack"),
        entry("fallo", at: 3, outcome: .failed, destination: "Slack"),
    ]
    #expect(dictationEntries(all, matching: "", outcome: nil) == all)
    #expect(dictationEntries(all, matching: " presupuesto ", outcome: nil).map(\.text) == ["Revisa el PRESUPUESTO", "hola"])
    #expect(dictationEntries(all, matching: "slack", outcome: nil).map(\.text) == ["adiós", "fallo"])
    #expect(dictationEntries(all, matching: "widget", outcome: nil).map(\.text) == ["hola"])
    #expect(dictationEntries(all, matching: "slack", outcome: .failed).map(\.text) == ["fallo"])
    #expect(dictationEntries(all, matching: "", outcome: .pasted).map(\.text) == ["Revisa el PRESUPUESTO"])
    #expect(dictationEntries(all, matching: "nada", outcome: nil).isEmpty)
}

@Test func theListIsGroupedByDayNewestFirstAndTheDayIsNamed() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
    let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12))!
    let at = { (days: Int, hour: Int) in calendar.date(byAdding: .hour, value: hour, to: calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: today))!)! }
    let entries = [(0, 14), (0, 9), (1, 20), (4, 8)].map {
        DictationEntry(started: at($0.0, $0.1), text: "x", model: "m", transcription: 0, audio: 0, destination: "d", outcome: .pasted)
    }
    let days = dictationDays(entries, calendar: calendar)
    #expect(days.map(\.entries.count) == [2, 1, 1])
    #expect(days.map { dictationDayTitle($0.day, now: today, calendar: calendar, bundle: english.bundle, locale: english.locale) } == ["Today", "Yesterday", "Thursday, Nov 12"])
    #expect(dictationDays([], calendar: calendar).isEmpty)
}

@MainActor @Test func aMessageBoxEndsAsPastedWhenStoppedAndKeepsItsOtherEndings() {
    #expect(boxOutcome(.stopped) == .pasted && boxOutcome(.cancelled) == .cancelled && boxOutcome(.failed) == .failed)
}

@Test func theEntryOfACleanedTakeHasTheRawAndTheCleanedTextAndTheCleanupModelAndTime() {
    let take = DictationTake(
        owner: "box", started: Date(timeIntervalSince1970: 1), text: "um hola", model: "m", audio: 2, transcription: 0.5, ending: .stopped,
        cleaned: "Hola.", cleanupSeconds: 1.5)
    let entry = DictationEntry(take, outcome: .pasted, destination: DictationEntry.carrier, cleanupModel: "qwen")
    #expect(entry.text == "um hola" && entry.cleaned == "Hola." && entry.cleanupModel == "qwen" && entry.cleanupSeconds == 1.5 && entry.shown == "Hola.")
    // a take that was not cleaned has no cleanup model, whatever the preference says now
    let raw = DictationEntry(
        DictationTake(owner: "box", started: .now, text: "hola", model: "m", audio: 1, transcription: 0, ending: .stopped, cleaned: nil, cleanupSeconds: nil),
        outcome: .pasted, destination: DictationEntry.carrier, cleanupModel: "qwen")
    #expect(raw.cleaned == nil && raw.cleanupModel == nil)
}

// The audio of the history: a temporary folder and a clock the tests set.

private let day = 86_400.0
private let clip = AudioClip(samples: [0, 0.5, -0.5, 1], sampleRate: 16_000)

@MainActor private final class Clock {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

@MainActor private func records(_ folder: String, _ clock: Clock, audio: Bool = true, days: Int = 30) -> DictationRecords {
    DictationRecords(carrierFolder: folder, keep: { true }, keepAudio: { audio }, audioDays: { days }, now: { clock.now })
}

@MainActor private func recordedAgo(_ days: Double, _ text: String, in records: DictationRecords, _ clock: Clock) -> DictationEntry {
    let old = DictationEntry(
        started: clock.now.addingTimeInterval(-days * day), text: text, model: "Apple", transcription: 0.4, audio: 1, destination: "Notes", outcome: .pasted)
    records.record(old, audio: clip)
    return old
}

@MainActor @Test func withKeepAudioOnADictationSavesItsAudioAsAFileNextToTheHistoryAndAfterARelaunchItIsStillThere() throws {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock)
    let saved = recordedAgo(0, "hola", in: records, clock)
    let url = try #require(records.audioURL(of: saved.id))
    #expect(url.path == folder + "/app/state/audio/\(saved.id.uuidString).wav")
    #expect(try Data(contentsOf: url) == wavData(clip))
    #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int == 0o600)
    #expect(records.audioBytes == wavData(clip).count && records.audioIDs == [saved.id])
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).audioIDs == [saved.id])
}

@MainActor @Test func withKeepAudioOffNoAudioIsWrittenAndAnEmptyOrWordlessDictationHasNone() {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let off = records(folder, clock, audio: false)
    let text = recordedAgo(0, "hola", in: off, clock)
    #expect(off.entries == [text] && off.audioURL(of: text.id) == nil && off.audioBytes == 0)
    #expect(FileManager.default.fileExists(atPath: folder + "/app/state/audio") == false)
    let on = records(folder, clock)
    #expect(on.record(entry("quieto", at: 1), audio: AudioClip(samples: [], sampleRate: 16_000)))
    #expect(on.record(entry("  ", at: 2), audio: clip) == false)
    #expect(on.audioIDs.isEmpty && FileManager.default.fileExists(atPath: folder + "/app/state/audio") == false)
}

@MainActor @Test func theLimitOfDaysDeletesTheAudioPastItAndKeepsTheEntriesAndTheRecentAudio() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock, days: 30)
    let (recent, old, older) = (recordedAgo(5, "reciente", in: records, clock), recordedAgo(40, "viejo", in: records, clock), recordedAgo(100, "más viejo", in: records, clock))
    await records.deleteOldAudio()
    #expect(records.audioIDs == [recent.id])
    #expect(Set(records.entries.map(\.id)) == [recent.id, old.id, older.id])
    // 29 days old, still inside the limit; two days on it is past it
    clock.now.addTimeInterval(24 * day)
    await records.deleteOldAudio()
    #expect(records.audioIDs == [recent.id])
    clock.now.addTimeInterval(2 * day)
    await records.deleteOldAudio()
    #expect(records.audioIDs.isEmpty && records.audioBytes == 0 && records.entries.count == 3)
    let reread = await reopened(folder)
    #expect(reread.entries.count == 3)
}

@MainActor @Test func neverKeepsEveryAudioWhateverItsAge() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock, days: 0)
    _ = recordedAgo(1000, "antiguo", in: records, clock)
    await records.deleteOldAudio()
    #expect(records.audioIDs.count == 1)
}

@MainActor @Test func deleteAllAudioDeletesEveryFileAndKeepsEveryTranscript() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock)
    let kept = [recordedAgo(0, "uno", in: records, clock), recordedAgo(2, "dos", in: records, clock)]
    records.deleteAllAudio()
    #expect(records.audioIDs.isEmpty && records.audioBytes == 0)
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder + "/app/state/audio")) ?? []).isEmpty)
    #expect(Set(records.entries.map(\.id)) == Set(kept.map(\.id)))
    let reread = await reopened(folder)
    #expect(reread.entries.count == 2)
}

@MainActor @Test func deletingAnEntryDeletesItsAudioAndOnlyItsAudio() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock)
    let (gone, stays) = (recordedAgo(0, "uno", in: records, clock), recordedAgo(1, "dos", in: records, clock))
    await records.delete(gone.id)
    #expect(records.audioIDs == [stays.id] && records.audioURL(of: gone.id) == nil)
    #expect(FileManager.default.fileExists(atPath: folder + "/app/state/audio/\(gone.id.uuidString).wav") == false)
}

@Test func theWavFileHasTheHeaderOfASixteenBitMonoClipAndItsSamples() {
    let data = wavData(clip)
    #expect(data.count == 44 + 8 && String(decoding: data.prefix(4), as: UTF8.self) == "RIFF" && String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
    #expect(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt32.self) } == 16_000)
    #expect(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 44 + 6, as: Int16.self) } == Int16.max)
    // a sample that is not a number is silence, not a crash
    #expect(wavData(AudioClip(samples: [.nan, .infinity], sampleRate: 8_000)).count == 48)
}

@Test func theAudioOnDiskIsSaidInMegabytesKilobytesAndFiles() {
    #expect(formatAudioOnDisk(bytes: 0, files: 0, bundle: english.bundle, locale: english.locale) == "No audio")
    #expect(formatAudioOnDisk(bytes: 12_400, files: 1, bundle: english.bundle, locale: english.locale) == "12 KB in 1 file")
    #expect(formatAudioOnDisk(bytes: 182_000_000, files: 214, bundle: english.bundle, locale: english.locale) == "182 MB in 214 files")
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

@MainActor @Test func aDictationThatEndsPastedOrCopiedIsCountedWhateverTheHistorySaysAndTheCountersHoldNoText() throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    var keep = true
    let records = DictationRecords(carrierFolder: folder, keep: { keep }, calendar: utc)
    // 2023-11-14 22:13:20 UTC
    records.record(entry("uno dos", at: 0))
    records.record(entry("tres", at: 60, outcome: .copied))
    keep = false
    records.record(entry("cuatro cinco seis", at: 120))
    #expect(records.counts == [DictationCount(day: "2023-11-14", hour: 22, model: "Apple", dictations: 3, words: 6, seconds: 18, longest: 6)])
    #expect(records.entries.count == 2)
    let file = try String(contentsOfFile: records.statisticsPath, encoding: .utf8)
    #expect(file.contains("uno") == false && file.contains("hola") == false)
    #expect(try FileManager.default.attributesOfItem(atPath: records.statisticsPath)[.posixPermissions] as? Int == 0o600)
    #expect(DictationRecords(carrierFolder: folder, keep: { true }, calendar: utc).counts == records.counts)
}

@MainActor @Test func aCancelledFailedOrEmptyDictationIsNotCounted() {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true }, calendar: utc)
    records.record(entry("uno", outcome: .cancelled))
    records.record(entry("dos", outcome: .failed))
    records.record(entry("  ", outcome: .pasted))
    #expect(records.counts.isEmpty && FileManager.default.fileExists(atPath: records.statisticsPath) == false)
}

@MainActor @Test func theCountersSplitByHourDayAndModelAndSurviveDeletingEntriesAndTurningTheHistoryOff() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    var keep = true
    let records = DictationRecords(carrierFolder: folder, keep: { keep }, calendar: utc)
    let first = entry("uno", at: 0)
    records.record(first)
    records.record(entry("dos", at: 3600))
    records.record(entry("tres", at: 86400))
    records.record(DictationEntry(started: first.started, text: "cuatro", model: "Whisper", transcription: 1, audio: 9, destination: "Notes", outcome: .pasted))
    #expect(records.counts.map(\.hour) == [22, 23, 22, 22] && records.counts.map(\.day) == ["2023-11-14", "2023-11-14", "2023-11-15", "2023-11-14"])
    let before = records.counts
    await records.delete(first.id)
    keep = false
    #expect(records.counts == before && records.entries.count == 3)
}

@MainActor @Test func resetStatisticsDeletesTheCountersAndLeavesTheHistory() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true }, calendar: utc)
    records.record(entry("uno dos"))
    records.resetStatistics()
    #expect(records.counts.isEmpty && records.entries.count == 1)
    #expect(DictationRecords(carrierFolder: folder, keep: { true }, calendar: utc).counts.isEmpty)
    let reread = await reopened(folder, calendar: utc)
    #expect(reread.entries.count == 1)
}

@MainActor @Test func deletingAudioOrAnEntryWithAudioLeavesTheCountersAsTheyWereAndTheyAreCountedWithTheAudioAndTheTextOff() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock)
    let (gone, stays) = (recordedAgo(0, "uno", in: records, clock), recordedAgo(1, "dos tres", in: records, clock))
    let before = records.counts
    #expect(before.map(\.dictations).reduce(0, +) == 2 && before.map(\.words).reduce(0, +) == 3)
    await records.delete(gone.id)
    records.deleteAllAudio()
    await records.deleteOldAudio()
    #expect(records.counts == before && records.entries.map(\.id) == [stays.id])
    let off = DictationRecords(carrierFolder: folder + "-off", keep: { false }, keepAudio: { true })
    defer { try? FileManager.default.removeItem(atPath: folder + "-off") }
    off.record(DictationEntry(started: .now, text: "hola", model: "Apple", transcription: 0, audio: 1, destination: "Notes", outcome: .pasted), audio: clip)
    #expect(off.counts.count == 1 && off.entries.isEmpty && off.audioIDs.isEmpty)
}

// MARK: the work of grouping

/// Noon of 15 November 2026, UTC: a day's dictations a second apart do not cross midnight.
private let noon = Date(timeIntervalSince1970: 1_794_744_000)

@Test func groupingADayOfFiveThousandDictationsTouchesEachOnce() {
    let entries = longDictationEntries(count: 5000, perDay: 5000, newest: noon)
    var work = 0
    let days = dictationDays(entries, calendar: utc, work: &work)
    #expect(days.count == 1 && days[0].entries.count == 5000 && days[0].entries == entries)
    #expect(work == 5000)
}

@Test func theHistoryDrawsOnlyTheFirstPageOfWhatMatchesAndSaysHowManyMatch() {
    let entries = longDictationEntries(count: 5000, perDay: 2000, newest: noon)
    let first = dictationHistory(entries, matching: "", outcome: nil, limit: dictationHistoryPage, calendar: utc)
    #expect(first.matched == 5000 && first.days.map(\.entries.count).reduce(0, +) == dictationHistoryPage)
    #expect(first.days.flatMap(\.entries) == Array(entries.prefix(dictationHistoryPage)))
    let all = dictationHistory(entries, matching: "", outcome: nil, limit: 10_000, calendar: utc)
    #expect(all.matched == 5000 && all.days.map(\.entries.count).reduce(0, +) == 5000)
}

@Test func theHistoryCountsWhatMatchesNotWhatItDraws() {
    // the fixture's destination is "Slack" or Carrier, so "slack" matches two of every three entries
    let entries = longDictationEntries(count: 600, perDay: 600, newest: noon)
    let found = dictationHistory(entries, matching: "slack", outcome: nil, limit: dictationHistoryPage, calendar: utc)
    let matching = dictationEntries(entries, matching: "slack", outcome: nil)
    #expect(matching.count == 400 && found.matched == 400)
    #expect(found.days.flatMap(\.entries) == Array(matching.prefix(dictationHistoryPage)))
}

// MARK: loading the history off the main thread

/// A history of `count` dictations on disk, in `folder`, newest first as `entries` lists them.
@MainActor private func writtenHistory(_ folder: String, count: Int) -> [DictationEntry] {
    let writer = DictationRecords(carrierFolder: folder, keep: { true })
    let all = (0..<count).map { entry("dictado \($0) uno", at: Double($0) * 10) }
    all.forEach { writer.record($0) }
    return all.reversed()
}

@MainActor @Test func theInitReadsNoHistoryAndLoadGivesWhatTheFileHolds() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let written = writtenHistory(folder, count: 50)
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    #expect(records.entries.isEmpty && records.loaded == false)
    await records.load()
    #expect(records.entries == written && records.loaded)
}

@MainActor @Test func loadingTwiceReadsOnceAndTheSecondCallWaitsForTheFirst() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let written = writtenHistory(folder, count: 5)
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    async let first: Void = records.load()
    async let second: Void = records.load()
    _ = await (first, second)
    #expect(records.entries == written)
    // a line another process added since does not come in: the history is read once
    DictationRecords(carrierFolder: folder, keep: { true }).record(entry("tarde", at: 9_999))
    await records.load()
    #expect(records.entries == written)
}

@MainActor @Test func aDictationRecordedBeforeTheLoadStaysOnTopOnceAndTheOldOnesComeUnderIt() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let written = writtenHistory(folder, count: 3)
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let fresh = entry("recién dicho", at: 5_000)
    #expect(records.record(fresh))
    #expect(records.entries == [fresh])
    await records.load()
    #expect(records.entries == [fresh] + written)
}

@MainActor @Test func deletingBeforeTheLoadKeepsEveryOtherEntryInTheFile() async throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let written = writtenHistory(folder, count: 4)
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let gone = written[1]
    await records.delete(gone.id)
    let rest = written.filter { $0.id != gone.id }
    #expect(records.entries == rest)
    let file = try String(contentsOfFile: records.path, encoding: .utf8).split(separator: "\n")
    #expect(file.count == 3 && file.allSatisfy { $0.contains(gone.id.uuidString) == false })
    let reread = await reopened(folder)
    #expect(reread.entries == rest)
}

@MainActor @Test func deletingTheEntryRecordedBeforeTheLoadDoesNotRewriteTheFileFromThatEntryAlone() async {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let written = writtenHistory(folder, count: 3)
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let fresh = entry("nuevo", at: 5_000)
    records.record(fresh)
    await records.delete(fresh.id)
    let reread = await reopened(folder)
    #expect(reread.entries == written)
}

@MainActor @Test func theAudioSweepBeforeTheLoadReadsTheAgesInTheFileAndDeletesNothingElse() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let before = records(folder, clock, days: 30)
    let (recent, old) = (recordedAgo(5, "reciente", in: before, clock), recordedAgo(40, "viejo", in: before, clock))
    let relaunched = records(folder, clock, days: 30)
    #expect(relaunched.entries.isEmpty && relaunched.audioIDs == [recent.id, old.id])
    await relaunched.deleteOldAudio()
    #expect(relaunched.audioIDs == [recent.id] && Set(relaunched.entries.map(\.id)) == [recent.id, old.id])
}

@MainActor @Test func aSweepWithNoLimitLeavesTheHistoryUnread() async {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    _ = recordedAgo(400, "viejo", in: records(folder, clock, days: 0), clock)
    let relaunched = records(folder, clock, days: 0)
    await relaunched.deleteOldAudio()
    #expect(relaunched.loaded == false && relaunched.audioIDs.count == 1)
}

@MainActor @Test func aLargeHistoryLoadsAndTheInitDecodesNoneOfIt() async throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let jsonl = try longDictationEntries(count: 10_000, perDay: 50, newest: noon).reversed().map { String(decoding: try encoder.encode($0), as: UTF8.self) }.joined(separator: "\n") + "\n"
    let path = DictationRecords(carrierFolder: folder, keep: { true }).path
    try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    try jsonl.write(toFile: path, atomically: true, encoding: .utf8)
    let opened = DictationRecords(carrierFolder: folder, keep: { true })
    #expect(opened.entries.isEmpty)
    await opened.load()
    #expect(opened.entries.count == 10_000)
}
