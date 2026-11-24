import Foundation

/// The app's own log of what stopped a dictation, `<Carrier folder>/app/logs/dictation.log`: one line per failure, with its cause and
/// nothing else, never the audio or the text. The person's home folder is written as `~` (a cause can carry the path of a model), and the file
/// never grows past `limit`: the next line starts a new one and the full one is kept as `dictation.log.1`.
public struct DictationLog: Sendable {
    public let path: String
    private let home: String
    private let limit: Int

    // ponytail: one backup and a fixed ceiling; a rotation by date or a setting only if someone needs to read further back
    public init(carrierFolder: String, home: String = NSHomeDirectory(), limit: Int = 1_000_000) {
        path = CarrierPlaces(folder: carrierFolder).dictationLog
        self.home = home
        self.limit = limit
    }

    public func append(_ failure: DictationFailure) {
        write(failure.cause.split(whereSeparator: \.isNewline).joined(separator: " "))
    }

    /// One line with where the time of a dictation went, in milliseconds (`timing capture=40 first-audio=45 model-ready=2300 first-word=3100 final=180`):
    /// a moment that did not happen is left out, and nothing of the dictation's text is ever in it.
    public func append(_ timings: DictationTimings) {
        let moments: [(String, Int?)] = [
            ("capture", timings.capture), ("first-audio", timings.firstAudio), ("model-ready", timings.modelReady), ("first-word", timings.firstWord),
            ("final", timings.finalText),
        ]
        write((["timing"] + moments.compactMap { name, ms in ms.map { "\(name)=\($0)" } }).joined(separator: " "))
    }

    private func write(_ text: String) {
        var line = text
        if home.count > 1 { line = line.replacingOccurrences(of: home, with: "~") }
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int, size >= limit {
                try? FileManager.default.removeItem(atPath: path + ".1")
                try FileManager.default.moveItem(atPath: path, toPath: path + ".1")
            }
            try StepLog(path: path).append(line)
        } catch {
            FileHandle.standardError.write(Data("carrier: dictation.log could not be written: \(error)\n".utf8))
        }
    }
}
