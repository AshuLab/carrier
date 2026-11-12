import Foundation

/// The app's own log of what stopped a dictation, `<Carrier folder>/app/logs/dictation.log`: one line per failure, with its cause and
/// nothing else, never the audio or the text.
public struct DictationLog: Sendable {
    public let path: String

    public init(carrierFolder: String) { path = carrierFolder + "/app/logs/dictation.log" }

    public func append(_ failure: DictationFailure) {
        let line = failure.cause.split(whereSeparator: \.isNewline).joined(separator: " ")
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try StepLog(path: path).append(line)
        } catch {
            FileHandle.standardError.write(Data("carrier: dictation.log could not be written: \(error)\n".utf8))
        }
    }
}
