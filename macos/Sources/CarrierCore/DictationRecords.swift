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
    /// Every entry, newest first.
    public private(set) var entries: [DictationEntry] = []
    /// What was dictated per day, hour and model, in the order it was first counted.
    public private(set) var counts: [DictationCount] = []
    @ObservationIgnored private let keep: () -> Bool
    @ObservationIgnored private let calendar: Calendar

    /// `keep` says whether the text is kept right now (the Keep the text switch); `calendar` says which day and hour a dictation belongs to.
    public init(carrierFolder: String, keep: @escaping () -> Bool, calendar: Calendar = .current) {
        path = carrierFolder + "/app/dictations.jsonl"
        statisticsPath = carrierFolder + "/app/dictation-statistics.json"
        self.keep = keep
        self.calendar = calendar
        if let data = FileManager.default.contents(atPath: statisticsPath) { counts = (try? JSONDecoder().decode([DictationCount].self, from: data)) ?? [] }
        guard let file = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let decoder = Self.decoder
        // a line that does not read (the last one, cut by a crash) is left out, and goes when the next delete rewrites the file
        let kept = file.split(separator: "\n").compactMap { try? decoder.decode(DictationEntry.self, from: Data($0.utf8)) }
        entries = kept.reversed().sorted { $0.started > $1.started }
    }

    /// Counts a dictation that had words and ended pasted or copied, whatever the switch says, and adds its entry at the top when the text is kept.
    /// Says whether it added the entry.
    @discardableResult
    public func record(_ entry: DictationEntry) -> Bool {
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
        return true
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

    private func saveCounts() {
        do {
            try FileManager.default.createDirectory(atPath: (statisticsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try JSONEncoder().encode(counts).write(to: URL(fileURLWithPath: statisticsPath), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("carrier: dictation-statistics.json could not be written: \(error)\n".utf8))
        }
    }

    /// Deletes an entry, whatever the switch says. The file is written again without it.
    public func delete(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var rest = entries
        rest.remove(at: index)
        do {
            let lines = try rest.reversed().map { try Self.encoder.encode($0) + Data("\n".utf8) }
            try Data(lines.joined()).write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("carrier: dictations.jsonl could not be written: \(error)\n".utf8))
            return
        }
        entries = rest
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
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
    public let entries: [DictationEntry]
    public var id: Date { day }
}

/// `entries` (newest first) grouped by the day they started.
public func dictationDays(_ entries: [DictationEntry], calendar: Calendar = .current) -> [DictationDay] {
    var days: [DictationDay] = []
    for entry in entries {
        let day = calendar.startOfDay(for: entry.started)
        if let last = days.last, last.day == day {
            days[days.count - 1] = DictationDay(day: day, entries: last.entries + [entry])
        } else {
            days.append(DictationDay(day: day, entries: [entry]))
        }
    }
    return days
}

/// "Today", "Yesterday", or the weekday and date, as the day's heading.
public func dictationDayTitle(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
    if calendar.isDate(day, inSameDayAs: now) { return "Today" }
    if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) { return "Yesterday" }
    let style = Date.FormatStyle(locale: Locale(identifier: "en_US"), calendar: calendar, timeZone: calendar.timeZone)
    return day.formatted(style.weekday(.wide).month(.abbreviated).day())
}
