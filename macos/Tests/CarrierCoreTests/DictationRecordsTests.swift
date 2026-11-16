import Foundation
import Testing
@testable import CarrierCore

private func folder() -> String { NSTemporaryDirectory() + "carrier-dictation-records-\(UUID().uuidString)" }

private func entry(
    _ text: String, at seconds: TimeInterval = 0, outcome: DictationOutcome = .pasted, destination: String = "Notes", cleaned: String? = nil
) -> DictationEntry {
    DictationEntry(
        started: Date(timeIntervalSince1970: 1_700_000_000 + seconds), text: text, cleaned: cleaned, model: "Apple", transcription: 0.4, audio: 6,
        destination: destination, outcome: outcome)
}

@MainActor @Test func anEntryIsRecordedWithItsFieldsAndIsThereAfterARelaunch() throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let first = entry("hola mundo", at: 0)
    let second = entry("uno dos tres", at: 60, outcome: .copied, destination: DictationEntry.widgetOnly)
    #expect(records.record(first) && records.record(second))
    #expect(records.entries == [second, first] && first.words == 2 && second.words == 3)
    #expect(records.path == folder + "/app/dictations.jsonl")
    #expect(try String(contentsOfFile: records.path, encoding: .utf8).split(separator: "\n").count == 2)
    #expect(try FileManager.default.attributesOfItem(atPath: records.path)[.posixPermissions] as? Int == 0o600)
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries == [second, first])
}

@MainActor @Test func aTextWithNewlinesAndQuotesStaysOneLineAndComesBackTheSame() {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let odd = entry("dijo \"hola\"\nluego / adiós", cleaned: "Dijo \"hola\".")
    records.record(odd)
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries == [odd])
}

@MainActor @Test func aDictationWithNoWordsRecordsNothingWhateverItsOutcome() {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    for outcome in DictationOutcome.allCases { #expect(records.record(entry("  \n", outcome: outcome)) == false) }
    #expect(records.entries.isEmpty && FileManager.default.fileExists(atPath: records.path) == false)
}

@MainActor @Test func withTheSwitchOffNothingNewIsRecordedAndWhatThereIsStays() {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    nonisolated(unsafe) var keep = true
    let records = DictationRecords(carrierFolder: folder, keep: { keep })
    let kept = entry("hola")
    records.record(kept)
    keep = false
    #expect(records.record(entry("adiós", at: 5)) == false)
    #expect(records.entries == [kept])
    #expect(DictationRecords(carrierFolder: folder, keep: { false }).entries == [kept])
    // a delete is the person's own, so it works with the switch off too
    records.delete(kept.id)
    #expect(records.entries.isEmpty && DictationRecords(carrierFolder: folder, keep: { false }).entries.isEmpty)
}

@MainActor @Test func deletingAnEntryRemovesOnlyThatOneFromTheListAndTheFile() {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let (a, b, c) = (entry("uno", at: 0), entry("dos", at: 10), entry("tres", at: 20))
    [a, b, c].forEach { records.record($0) }
    records.delete(b.id)
    records.delete(UUID())
    #expect(records.entries == [c, a])
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries == [c, a])
    records.record(entry("cuatro", at: 30))
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries.map(\.text) == ["cuatro", "tres", "uno"])
}

@MainActor @Test func aLineThatDoesNotReadIsLeftOutAndTheRestLoads() throws {
    let folder = folder()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = DictationRecords(carrierFolder: folder, keep: { true })
    let good = entry("hola")
    records.record(good)
    let handle = try #require(FileHandle(forWritingAtPath: records.path))
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("{\"id\":\"cut here".utf8))
    try handle.close()
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries == [good])
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
    #expect(days.map { dictationDayTitle($0.day, now: today, calendar: calendar) } == ["Today", "Yesterday", "Thursday, Nov 12"])
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
    #expect(url.path == folder + "/app/audio/\(saved.id.uuidString).wav")
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
    #expect(FileManager.default.fileExists(atPath: folder + "/app/audio") == false)
    let on = records(folder, clock)
    #expect(on.record(entry("quieto", at: 1), audio: AudioClip(samples: [], sampleRate: 16_000)))
    #expect(on.record(entry("  ", at: 2), audio: clip) == false)
    #expect(on.audioIDs.isEmpty && FileManager.default.fileExists(atPath: folder + "/app/audio") == false)
}

@MainActor @Test func theLimitOfDaysDeletesTheAudioPastItAndKeepsTheEntriesAndTheRecentAudio() {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock, days: 30)
    let (recent, old, older) = (recordedAgo(5, "reciente", in: records, clock), recordedAgo(40, "viejo", in: records, clock), recordedAgo(100, "más viejo", in: records, clock))
    records.deleteOldAudio()
    #expect(records.audioIDs == [recent.id])
    #expect(Set(records.entries.map(\.id)) == [recent.id, old.id, older.id])
    // 29 days old, still inside the limit; two days on it is past it
    clock.now.addTimeInterval(24 * day)
    records.deleteOldAudio()
    #expect(records.audioIDs == [recent.id])
    clock.now.addTimeInterval(2 * day)
    records.deleteOldAudio()
    #expect(records.audioIDs.isEmpty && records.audioBytes == 0 && records.entries.count == 3)
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries.count == 3)
}

@MainActor @Test func neverKeepsEveryAudioWhateverItsAge() {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock, days: 0)
    _ = recordedAgo(1000, "antiguo", in: records, clock)
    records.deleteOldAudio()
    #expect(records.audioIDs.count == 1)
}

@MainActor @Test func deleteAllAudioDeletesEveryFileAndKeepsEveryTranscript() {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock)
    let kept = [recordedAgo(0, "uno", in: records, clock), recordedAgo(2, "dos", in: records, clock)]
    records.deleteAllAudio()
    #expect(records.audioIDs.isEmpty && records.audioBytes == 0)
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder + "/app/audio")) ?? []).isEmpty)
    #expect(Set(records.entries.map(\.id)) == Set(kept.map(\.id)))
    #expect(DictationRecords(carrierFolder: folder, keep: { true }).entries.count == 2)
}

@MainActor @Test func deletingAnEntryDeletesItsAudioAndOnlyItsAudio() {
    let folder = folder(), clock = Clock()
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let records = records(folder, clock)
    let (gone, stays) = (recordedAgo(0, "uno", in: records, clock), recordedAgo(1, "dos", in: records, clock))
    records.delete(gone.id)
    #expect(records.audioIDs == [stays.id] && records.audioURL(of: gone.id) == nil)
    #expect(FileManager.default.fileExists(atPath: folder + "/app/audio/\(gone.id.uuidString).wav") == false)
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
    #expect(formatAudioOnDisk(bytes: 0, files: 0) == "No audio")
    #expect(formatAudioOnDisk(bytes: 12_400, files: 1) == "12 KB in 1 file")
    #expect(formatAudioOnDisk(bytes: 182_000_000, files: 214) == "182 MB in 214 files")
}
