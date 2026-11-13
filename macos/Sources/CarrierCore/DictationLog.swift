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
        path = carrierFolder + "/app/logs/dictation.log"
        self.home = home
        self.limit = limit
    }

    public func append(_ failure: DictationFailure) {
        var line = failure.cause.split(whereSeparator: \.isNewline).joined(separator: " ")
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
