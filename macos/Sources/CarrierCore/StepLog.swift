import Foundation

/// Appends one timestamped line per step to a file; the app's `--selftest` flag writes its progress through it.
public struct StepLog {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func append(_ step: String) throws {
        let line = Data("\(Date().timeIntervalSince1970) \(step)\n".utf8)
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: URL(fileURLWithPath: path))
        }
    }
}
