import Foundation
import Observation

// The history of dictations (docs/adr/0031-dictation-keeps-a-history-and-its-statistics-live-apart-from-it.md): one entry per dictation in a JSON
// Lines file of the app's folder, read into memory and filtered there. `dictation.log` never holds text; this file does, and says so on its page.

/// How a dictation ended: its text was put in a field (pasted, or typed into a Carrier box), it was only copied, or it was cancelled or failed.
public enum DictationOutcome: String, Codable, CaseIterable, Sendable {
    case pasted, copied, cancelled, failed

    public var title: String { rawValue.capitalized }
}

/// What a message box's dictation ended in: the text stays in the box, so a stop is a paste.
public func boxOutcome(_ ending: DictationTake.Ending) -> DictationOutcome {
    switch ending {
    case .stopped: .pasted
    case .cancelled: .cancelled
    case .failed: .failed
    }
}

/// One dictation. The cleanup is empty when none ran.
public struct DictationEntry: Codable, Equatable, Identifiable, Sendable {
    /// Where a dictation went when it went to no app: the widget only (copied, cancelled or failed).
    public static let widgetOnly = "Widget only"
    /// Where a message box's dictation went.
    public static let carrier = "Carrier"

    public let id: UUID
    public let started: Date
    /// As recognized.
    public let text: String
    /// After the cleanup model, when there was one.
    public var cleaned: String?
    public let model: String
    /// Seconds the recognizer took after the person stopped.
    public let transcription: Double
    public var cleanupModel: String?
    public var cleanupSeconds: Double?
    /// Seconds of audio.
    public let audio: Double
    public let words: Int
    public let destination: String
    public let outcome: DictationOutcome

    public init(
        id: UUID = UUID(), started: Date, text: String, cleaned: String? = nil, model: String, transcription: Double, cleanupModel: String? = nil,
        cleanupSeconds: Double? = nil, audio: Double, destination: String, outcome: DictationOutcome
    ) {
        self.id = id
        self.started = started
        self.text = text
        self.cleaned = cleaned
        self.model = model
        self.transcription = transcription
        self.cleanupModel = cleanupModel
        self.cleanupSeconds = cleanupSeconds
        self.audio = audio
        words = text.split(whereSeparator: \.isWhitespace).count
        self.destination = destination
        self.outcome = outcome
    }

    /// The entry of a dictation that ended with `outcome` and went to `destination`; `cleanupModel` is the model that cleaned it, when the take was cleaned.
    public init(_ take: DictationTake, outcome: DictationOutcome, destination: String, cleanupModel: String? = nil) {
        self.init(
            started: take.started, text: take.text, cleaned: take.cleaned, model: take.model, transcription: take.transcription,
            cleanupModel: take.cleaned == nil ? nil : cleanupModel, cleanupSeconds: take.cleanupSeconds, audio: take.audio, destination: destination,
            outcome: outcome)
    }

    /// What the list shows and Copy copies: the cleaned text when there is one.
    public var shown: String { cleaned ?? text }
}

@MainActor @Observable public final class DictationRecords {
    public let path: String
    /// The counters of the statistics, in their own file: they hold no text and neither the switch nor a delete touches them.
    public let statisticsPath: String
    /// Every entry, newest first. Empty until `load()` has read the file, except what was recorded since the app opened.
    public private(set) var entries: [DictationEntry] = []
    /// Whether `entries` has the file's history: what rewrites the file (a delete) and what reads the ages (the audio sweep) wait for it.
    public private(set) var loaded = false
    /// What was dictated per day, hour and model, in the order it was first counted.
    public private(set) var counts: [DictationCount] = []
    /// The audio files, `<id>.wav` each, next to the history.
    public let audioFolder: String
    /// The entries that have their audio on disk, and what it takes.
    public private(set) var audioIDs: Set<UUID> = []
    public private(set) var audioBytes = 0
    @ObservationIgnored private let keep: () -> Bool
    @ObservationIgnored private let keepAudio: () -> Bool
    @ObservationIgnored private let audioDays: () -> Int
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// `keep` says whether the text is kept right now (the Keep the text switch), `keepAudio` whether the audio is too, and `audioDays` how many days
    /// the audio stays (0 is for ever); `calendar` says which day and hour a dictation belongs to.
    public init(
        carrierFolder: String, keep: @escaping () -> Bool, keepAudio: @escaping () -> Bool = { false }, audioDays: @escaping () -> Int = { 0 },
        now: @escaping () -> Date = Date.init, calendar: Calendar = .current
    ) {
        let signpost = Signposts.launch.beginInterval("dictation records")
        let places = CarrierPlaces(folder: carrierFolder)
        path = places.dictations
        statisticsPath = places.dictationStatistics
        audioFolder = places.dictationAudio
        self.keep = keep
        self.keepAudio = keepAudio
        self.audioDays = audioDays
        self.now = now
        self.calendar = calendar
        if let data = FileManager.default.contents(atPath: statisticsPath) { counts = (try? JSONDecoder().decode([DictationCount].self, from: data)) ?? [] }
        scanAudio()
        Signposts.launch.endInterval("dictation records", signpost)
    }

    /// Reads the history off the main thread, once (a second call waits for the first); what was recorded meanwhile stays on top, once.
    /// A line that does not read (the last one, cut by a crash) is left out, and goes when the next delete rewrites the file.
    public func load() async {
        if let loading { return await loading.value }
        let path = path
        let task = Task {
            let signpost = Signposts.launch.beginInterval("dictation history")
            let read = await Task.detached { Self.read(path) }.value
            if entries.isEmpty {
                entries = read
            } else {
                let mine = Set(entries.map(\.id))
                entries = (entries + read.filter { mine.contains($0.id) == false }).sorted { $0.started > $1.started }
            }
            loaded = true
            Signposts.launch.endInterval("dictation history", signpost, "\(self.entries.count) entries")
        }
        loading = task
        await task.value
    }

    /// The file's entries, newest first; the decoder is made here because the class's own belongs to the main actor.
    nonisolated static func read(_ path: String) -> [DictationEntry] {
        guard let file = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let kept = file.split(separator: "\n").compactMap { try? decoder.decode(DictationEntry.self, from: Data($0.utf8)) }
        return kept.reversed().sorted { $0.started > $1.started }
    }

    /// Counts a dictation that had words and ended pasted or copied, whatever the switches say, adds its entry at the top when the text is kept, and
    /// saves its `audio` when that is kept too. Says whether it added the entry.
    @discardableResult
    public func record(_ entry: DictationEntry, audio: AudioClip? = nil) -> Bool {
        guard entry.words > 0 else { return false }
        count(entry)
        guard keep() else { return false }
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            var line = try Self.encoder.encode(entry)
            line.append(UInt8(ascii: "\n"))
            if let handle = FileHandle(forWritingAtPath: path) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                // the text is private to the person's account
                guard FileManager.default.createFile(atPath: path, contents: line, attributes: [.posixPermissions: 0o600]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        } catch {
            FileHandle.standardError.write(Data("carrier: dictations.jsonl could not be written: \(error)\n".utf8))
            return false
        }
        entries.insert(entry, at: 0)
        if keepAudio(), let audio, audio.samples.isEmpty == false { saveAudio(audio, of: entry.id) }
        return true
    }

    /// The file of an entry's audio, when it has one.
    public func audioURL(of id: UUID) -> URL? { audioIDs.contains(id) ? audioFile(id) : nil }

    /// Deletes the audio of the entries older than the limit of days; the entries stay. Run when the app starts and once a day.
    /// It reads the ages in the history, so it waits for the history to be loaded.
    public func deleteOldAudio() async {
        let days = audioDays()
        guard days > 0 else { return }
        await load()
        let cutoff = now().addingTimeInterval(-Double(days) * 86_400)
        for entry in entries where entry.started < cutoff { removeAudio(of: entry.id) }
        scanAudio()
    }

    /// Deletes every audio file; every entry stays.
    public func deleteAllAudio() {
        for id in audioIDs { removeAudio(of: id) }
        scanAudio()
    }

    private func audioFile(_ id: UUID) -> URL { URL(fileURLWithPath: audioFolder).appending(path: id.uuidString + ".wav") }

    private func saveAudio(_ clip: AudioClip, of id: UUID) {
        do {
            try FileManager.default.createDirectory(atPath: audioFolder, withIntermediateDirectories: true)
            // the audio is private to the person's account, like the text
            guard FileManager.default.createFile(atPath: audioFile(id).path, contents: wavData(clip), attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } catch {
            FileHandle.standardError.write(Data("carrier: the audio of a dictation could not be written: \(error)\n".utf8))
            return
        }
        scanAudio()
    }

    private func removeAudio(of id: UUID) {
        guard audioIDs.contains(id) else { return }
        try? FileManager.default.removeItem(at: audioFile(id))
    }

    /// What is on disk now: the files named for an id, and their bytes.
    private func scanAudio() {
        let files = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: audioFolder), includingPropertiesForKeys: [.fileSizeKey])) ?? []
        var ids: Set<UUID> = []
        var bytes = 0
        for file in files where file.pathExtension == "wav" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) else { continue }
            ids.insert(id)
            bytes += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        audioIDs = ids
        audioBytes = bytes
    }

    private func count(_ entry: DictationEntry) {
        guard entry.outcome == .pasted || entry.outcome == .copied else { return }
        let day = dictationDayKey(entry.started, calendar: calendar)
        let hour = calendar.component(.hour, from: entry.started)
        if let index = counts.firstIndex(where: { $0.day == day && $0.hour == hour && $0.model == entry.model }) {
            counts[index].dictations += 1
            counts[index].words += entry.words
            counts[index].seconds += entry.audio
            counts[index].longest = max(counts[index].longest, entry.audio)
        } else {
            counts.append(DictationCount(day: day, hour: hour, model: entry.model, dictations: 1, words: entry.words, seconds: entry.audio, longest: entry.audio))
        }
        saveCounts()
    }

    /// Deletes every counter. The history stays as it is.
    public func resetStatistics() {
        counts = []
        saveCounts()
    }

    /// Replaces the file at `path` in one step, the new one readable by this account only (`.atomic` would give it the umask's mode).
    private static func writePrivately(_ data: Data, to path: String) throws {
        let temporary = path + ".tmp"
        guard FileManager.default.createFile(atPath: temporary, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(temporary, path) == 0 else {
            let cause = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            try? FileManager.default.removeItem(atPath: temporary)
            throw cause
        }
    }

    private func saveCounts() {
        do {
            try FileManager.default.createDirectory(atPath: (statisticsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try Self.writePrivately(JSONEncoder().encode(counts), to: statisticsPath)
        } catch {
            FileHandle.standardError.write(Data("carrier: dictation-statistics.json could not be written: \(error)\n".utf8))
        }
    }

    /// Deletes an entry, whatever the switch says. The file is written again without it, so the history has to be loaded first: written from a
    /// list that lacks it, the file would lose every other entry.
    public func delete(_ id: UUID) async {
        await load()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var rest = entries
        rest.remove(at: index)
        do {
            let lines = try rest.reversed().map { try Self.encoder.encode($0) + Data("\n".utf8) }
            try Self.writePrivately(Data(lines.joined()), to: path)
        } catch {
            FileHandle.standardError.write(Data("carrier: dictations.jsonl could not be written: \(error)\n".utf8))
            return
        }
        entries = rest
        removeAudio(of: id)
        scanAudio()
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

/// The entries whose text, cleaned text or destination hold `query` (any case), with the given outcome when one is chosen.
public func dictationEntries(_ entries: [DictationEntry], matching query: String, outcome: DictationOutcome?) -> [DictationEntry] {
    let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    return entries.filter { entry in
        (outcome == nil || entry.outcome == outcome)
            && (query.isEmpty || [entry.text, entry.cleaned ?? "", entry.destination].contains { $0.localizedCaseInsensitiveContains(query) })
    }
}

/// The entries of one day, newest first.
public struct DictationDay: Identifiable, Equatable, Sendable {
    public let day: Date
    public internal(set) var entries: [DictationEntry]
    public var id: Date { day }
}

/// `entries` (newest first) grouped by the day they started.
public func dictationDays(_ entries: [DictationEntry], calendar: Calendar = .current) -> [DictationDay] {
    var work = 0
    return dictationDays(entries, calendar: calendar, work: &work)
}

/// `work` adds up the entries written into the days, so a test tells copying a day for each entry from adding to it.
func dictationDays(_ entries: [DictationEntry], calendar: Calendar, work: inout Int) -> [DictationDay] {
    var days: [DictationDay] = []
    for entry in entries {
        let day = calendar.startOfDay(for: entry.started)
        work += 1
        if days.last?.day == day {
            days[days.count - 1].entries.append(entry)
        } else {
            days.append(DictationDay(day: day, entries: [entry]))
        }
    }
    return days
}

/// How many entries the History list draws before "Show more", and how many more each press adds.
public let dictationHistoryPage = 100

/// What the History list draws: the first `limit` entries that match, grouped by day, and how many match in all.
public func dictationHistory(
    _ entries: [DictationEntry], matching query: String, outcome: DictationOutcome?, limit: Int, calendar: Calendar = .current
) -> (days: [DictationDay], matched: Int) {
    let matched = dictationEntries(entries, matching: query, outcome: outcome)
    return (dictationDays(Array(matched.prefix(limit)), calendar: calendar), matched.count)
}

/// "Today", "Yesterday", or the weekday and date, as the day's heading.
public func dictationDayTitle(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
    if calendar.isDate(day, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
    let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone)
    return day.formatted(style.weekday(.wide).month(.abbreviated).day())
}
