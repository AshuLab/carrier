import Foundation

// Every save of `config.json` or `providers.json` ends by asking the running engine to apply it (docs/specs/settings-apply-without-restart.md).

/// What came of asking the engine to read its settings again.
public enum ReloadOutcome: Equatable, Sendable {
    /// the engine read the files and runs on them
    case applied
    /// there was no one to ask (Carrier is stopped): it reads the files when it starts
    case nobody
    /// the engine is running and does not list `reload` (an older one): it reads the files when it restarts
    case unsupported
    /// the engine kept its settings; its problem, the key named
    case refused(String)
    /// an engine that was there did not answer (a timeout, a socket error): the file is written, and the engine may or may not have applied it
    case noAnswer
    /// the ask was handed to `ReloadStatus`, which keeps the answer when it comes
    case asked
}

extension ReloadOutcome {
    /// Something went wrong in asking (the engine refused, or did not answer), as against a plain fact like "it reads it when it starts".
    public var isProblem: Bool {
        switch self {
        case .refused, .noAnswer: true
        case .applied, .nobody, .unsupported, .asked: false
        }
    }
}

/// What a writer calls after its own successful write, and only then: asks the running engine to read its settings again.
public typealias Reload = () -> ReloadOutcome

/// `Reload` for the engine at `socketPath`. Blocks until the engine has answered (3 s to connect, 3 s to reply at most): a page runs it
/// through `reloadInBackground`, a model that already waits (`await reloadOffMain`) runs it on its own.
public func reloadEngine(socketPath: String = controlSocketPath()) -> ReloadOutcome {
    guard let client = ControlClient.connect(path: socketPath, timeout: 3) else { return .nobody }
    defer { client.close() }
    do {
        _ = try client.hello()
        return try client.reload() ? .applied : .unsupported
    } catch ControlError.remote(let problem) {
        return .refused(problem)
    } catch {
        FileHandle.standardError.write(Data("carrier: reload: \(error)\n".utf8))
        return .noAnswer
    }
}

/// The calls that wait on the engine (up to 6 s each) run here and not on a thread of the cooperative pool, which they would hold.
private let reloadQueue = DispatchQueue(label: "carrier.reload", qos: .userInitiated, attributes: .concurrent)

/// `reload` off the main thread, for whoever awaits it.
public func reloadOffMain(_ reload: @escaping Reload) async -> ReloadOutcome {
    await withCheckedContinuation { answer in reloadQueue.async { answer.resume(returning: reload()) } }
}

/// The last answer of the engine to a save of the settings, for every page that saves them: one answer outlives the tab that asked, and
/// an answer to an older ask is dropped when a newer one was made.
@MainActor @Observable public final class ReloadStatus {
    public static let shared = ReloadStatus()
    /// What the engine answered to the last ask; nil before any
    public private(set) var outcome: ReloadOutcome?
    /// An ask has not been answered yet
    public private(set) var pending = false

    @ObservationIgnored private var asks = 0
    @ObservationIgnored private let reload: Reload

    public init(reload: @escaping Reload = { reloadEngine() }) { self.reload = reload }

    /// What the page says when the engine did not apply what was saved; nil when it did, or there was no one to ask.
    public var words: String? { outcome.flatMap(reloadWords) }

    /// `words` is a problem (the engine refused or did not answer), not a plain fact.
    public var isProblem: Bool { outcome?.isProblem ?? false }

    /// Asks the engine off the main thread. The returned task ends when the answer is in (or was dropped).
    @discardableResult public func ask() -> Task<Void, Never> {
        let mine = begin()
        return Task { _ = await run(mine, nil) }
    }

    /// Asks `custom` (the engine by default) off the main thread and gives back what it answered; that answer is kept unless a newer ask was made.
    public func answer(_ custom: Reload? = nil) async -> ReloadOutcome {
        await run(begin(), custom)
    }

    private func begin() -> Int {
        asks += 1
        pending = true
        return asks
    }

    private func run(_ mine: Int, _ custom: Reload?) async -> ReloadOutcome {
        let answer = await reloadOffMain(custom ?? reload)
        if mine == asks {
            outcome = answer
            pending = false
        }
        return answer
    }

    /// Forgets the answer and drops those on their way: what the engine said belongs to the engine that said it, and a stopped or restarted
    /// Carrier is another one.
    public func reset() {
        asks += 1
        outcome = nil
        pending = false
    }
}

/// The `Reload` of the pages: hands the ask to `ReloadStatus.shared` at once and says `.asked`, so a save never waits for the engine. For the
/// main actor, where the pages save.
public func reloadInBackground() -> ReloadOutcome {
    MainActor.assumeIsolated { ReloadStatus.shared.ask() }
    return .asked
}

/// What the page says when the file is saved and the engine did not apply it: nil when it did, there was no one to ask, or the answer is on its way.
public func reloadWords(_ outcome: ReloadOutcome) -> String? {
    switch outcome {
    case .applied, .nobody, .asked: nil
    case .refused(let problem): "Saved, but Carrier kept its settings: \(problem)"
    case .noAnswer: "Saved, but Carrier did not answer: it may not have applied it."
    case .unsupported: "Saved. This Carrier does not apply it while it runs: it will read the file when it starts."
    }
}

/// What the Behavior and Repos tabs save with: `edit` rewrites the file at `path`, read just now so a save of another tab in between is not
/// lost; `unusable` is what to say when it cannot be read or `edit` gives nothing. A written file is followed by `reload`.
public func saveConfig(path: String, unusable: String, edit: (Data) -> Data?, reload: Reload = reloadInBackground) -> RoleSave {
    let url = URL(fileURLWithPath: path)
    guard let current = try? Data(contentsOf: url), let updated = edit(current) else { return .failed(unusable) }
    do {
        try updated.write(to: url, options: .atomic)
        return written(reload)
    } catch {
        FileHandle.standardError.write(Data("carrier: saving \(path) failed: \(error)\n".utf8))
        return .failed("Could not save the config file: \(error.localizedDescription)")
    }
}
