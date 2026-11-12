import Foundation
@testable import CarrierCore

/// A fake engine for the writers: records what the file held when it was asked to reload, and answers `problem` (nil: it reloaded).
final class FakeReload {
    var problem: String?
    /// What the file at `path` held at each ask: a reload after the write sees the new file.
    private(set) var seen: [Data?] = []
    private let path: String

    init(file path: String, problem: String? = nil) {
        self.path = path
        self.problem = problem
    }

    var calls: Int { seen.count }

    /// The file as it is now.
    var now: Data? { try? Data(contentsOf: URL(fileURLWithPath: path)) }

    var reload: Reload {
        { [self] in
            seen.append(try? Data(contentsOf: URL(fileURLWithPath: path)))
            return problem
        }
    }
}
