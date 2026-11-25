import Foundation

// When the speech model is loaded and when it is let go (docs/specs/dictation-live-and-fast.md): the rule, as a pure function of the switches, the
// minutes and the clock, and the slot a recognizer keeps its loaded model in. `DictationController` runs the rule and its timer.

/// The choices of Release the model after: minutes without dictating, and 0 for Never.
public let dictationReleaseChoices = [5, 15, 30, 60, 0].map(DictationReleaseChoice.init(minutes:))

public struct DictationReleaseChoice: Equatable, Sendable {
    public let minutes: Int

    /// "15 minutes", or "Never" for 0.
    public func title(bundle: Bundle? = nil, locale: Locale = .current) -> String { Copy.dictationReleaseAfter(minutes: minutes, bundle: bundle, locale: locale) }
}

public enum SpeechModelStep: Equatable, Sendable { case load, release, none }

/// What to do with the model now. It is released with Dictation off and after `minutes` without dictating (counted from `idleSince`, the end of the last dictation
/// or the moment it was asked to load), whatever Keep the speech model ready says; it is loaded in the background only with Dictation and Keep it ready on.
public func speechModelStep(dictation: Bool, keepReady: Bool, releaseAfter minutes: Int, loaded: Bool, idleSince: Date, now: Date) -> SpeechModelStep {
    let unused = minutes > 0 && now.timeIntervalSince(idleSince) >= Double(minutes) * 60
    if dictation == false || unused { return loaded ? .release : .none }
    return keepReady && loaded == false ? .load : .none
}

/// Where a recognizer keeps the model it loaded: one load of an id at a time (a dictation that asks while the background load runs waits for it
/// instead of loading it twice), and `release` drops what is held, which a load that was still running does not put back.
public final class ModelSlot<Model: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var held: (id: String, model: Model)?
    private var loading: (id: String, task: Task<Model, Error>)?

    public init() {}

    public var current: (id: String, model: Model)? { lock.withLock { held } }

    public func load(_ id: String, using make: @escaping @Sendable () async throws -> Model) async throws {
        let task = lock.withLock { () -> Task<Model, Error>? in
            if held?.id == id { return nil }
            if let loading, loading.id == id { return loading.task }
            let task = Task { try await make() }
            loading = (id, task)
            return task
        }
        guard let task else { return }
        do {
            let model = try await task.value
            lock.withLock {
                guard loading?.id == id else { return }
                held = (id, model)
                loading = nil
            }
        } catch {
            lock.withLock { if loading?.id == id { loading = nil } }
            throw error
        }
    }

    public func release() {
        lock.withLock {
            loading?.task.cancel()
            loading = nil
            held = nil
        }
    }
}
