import Foundation
import Observation

// The speech models a person has on disk (docs/specs/dictation-in-the-app.md, stories 9 and 10): their states, the download with its progress,
// the cancel, the retry and the delete, behind a downloader port. The real downloaders arrive with their recognizers; a fixture build
// uses `FixtureModelDownloader`.

/// Why a download failed, in words for the person: what they caused or can fix, not a bug.
public enum ModelDownloadFailure: Error, Equatable, Sendable {
    case noConnection, noSpace, didNotCheck

    public var cause: String {
        switch self {
        case .noConnection: "No connection"
        case .noSpace: "No space on the disk"
        case .didNotCheck: "The file did not check"
        }
    }
}

/// Fetches one model into the folder it is given, reporting its progress as a fraction. It stops by throwing when its task is cancelled and
/// throws a `ModelDownloadFailure` for a cause the person can be told; anything else is told as a failure with its description.
public protocol ModelDownloader: Sendable {
    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws
}

public enum ModelState: Equatable, Sendable {
    case notDownloaded
    /// A fraction, `0...1`.
    case downloading(Double)
    case failed(String)
    case downloaded
}

/// Owns the states of the models the app lists. A model lives in `<root>/<recognizer>/<model>/` and counts as downloaded when its folder holds
/// `complete`, which is written last: a folder without it is a partial download, removed when the store starts, when a download is cancelled
/// and when it fails. Nothing outside `models` can be downloaded. Apple's has no download: the system manages it, so it is always downloaded.
@MainActor @Observable public final class ModelStore {
    static let marker = "complete"

    public let root: URL
    /// The size of the files under `root`.
    public private(set) var usedBytes: Int64 = 0
    private var inFlight: [String: ModelState] = [:]
    private var onDisk: Set<String> = []
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let models: @MainActor () -> [SpeechModel]
    @ObservationIgnored private let downloader: any ModelDownloader
    @ObservationIgnored private let inUse: @MainActor () -> String?
    @ObservationIgnored private let log: @MainActor (DictationFailure) -> Void
    @ObservationIgnored private let announce: @MainActor (String) -> Void

    /// `models` is the list on offer (it may grow as recognizers register), `inUse` the id of the model dictation uses, which has no delete.
    public init(
        root: URL, models: @escaping @MainActor () -> [SpeechModel], downloader: any ModelDownloader, inUse: @escaping @MainActor () -> String?,
        log: @escaping @MainActor (DictationFailure) -> Void = { _ in }, announce: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.root = root
        self.models = models
        self.downloader = downloader
        self.inUse = inUse
        self.log = log
        self.announce = announce
        removePartials()
        refresh()
    }

    /// `<root>/<recognizer>/<model>`, the model being the id without its recognizer's prefix.
    public func folder(for model: SpeechModel) -> URL { Self.folder(in: root, for: model) }

    /// The same folder for whoever loads the model: a recognizer reads from where the store downloaded to.
    public nonisolated static func folder(in root: URL, for model: SpeechModel) -> URL {
        let name = model.id.split(separator: ".", maxSplits: 1).last.map(String.init) ?? model.id
        return root.appending(path: model.recognizer.rawValue.lowercased()).appending(path: name)
    }

    public func state(of model: SpeechModel) -> ModelState {
        guard model.bytes != nil else { return .downloaded }
        return inFlight[model.id] ?? (onDisk.contains(model.id) ? .downloaded : .notDownloaded)
    }

    /// Starts the download of a listed model that is not downloaded (a failed one is tried again): only the person's action calls this.
    public func download(_ id: String) {
        guard let model = models().first(where: { $0.id == id }), model.bytes != nil else { return }
        switch state(of: model) {
        case .notDownloaded, .failed: break
        case .downloading, .downloaded: return
        }
        inFlight[id] = .downloading(0)
        tasks[id] = Task { await run(model) }
    }

    /// Stops a download; its row goes back to Download once nothing of it is left on disk.
    public func cancel(_ id: String) { tasks[id]?.cancel() }

    /// Deletes a downloaded model and frees its space. Refused, with false, for the model in use, Apple's and one that is not downloaded.
    @discardableResult
    public func delete(_ id: String) -> Bool {
        guard let model = models().first(where: { $0.id == id }), state(of: model) == .downloaded, model.bytes != nil, inUse() != id else { return false }
        do {
            try FileManager.default.removeItem(at: folder(for: model))
        } catch {
            log(DictationFailure("Deleting \(model.name) failed: \(error.localizedDescription)"))
            return false
        }
        refresh()
        return true
    }

    /// Waits for the downloads that run.
    func settled() async {
        for task in Array(tasks.values) { await task.value }
    }

    private func run(_ model: SpeechModel) async {
        let folder = folder(for: model)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await downloader.download(model, into: folder) { [weak self] fraction in self?.progressed(model.id, fraction) }
            try Task.checkCancellation()
            try Data().write(to: folder.appending(path: Self.marker))
            inFlight[model.id] = nil
            announce("Downloaded \(model.name)")
        } catch {
            try? FileManager.default.removeItem(at: folder)
            if Task.isCancelled || error is CancellationError {
                inFlight[model.id] = nil
            } else {
                let cause = (error as? ModelDownloadFailure)?.cause ?? "Download failed: \(error.localizedDescription)"
                inFlight[model.id] = .failed(cause)
                log(DictationFailure("Downloading \(model.name) failed: \(cause)"))
            }
        }
        tasks[model.id] = nil
        refresh()
    }

    private func progressed(_ id: String, _ fraction: Double) {
        if case .downloading = inFlight[id] { inFlight[id] = .downloading(min(1, max(0, fraction))) }
    }

    /// A folder with no marker is a partial download: a quit app left it.
    private func removePartials() {
        let fileManager = FileManager.default
        for recognizer in (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for model in (try? fileManager.contentsOfDirectory(at: recognizer, includingPropertiesForKeys: nil)) ?? []
            where fileManager.fileExists(atPath: model.appending(path: Self.marker).path) == false {
                try? fileManager.removeItem(at: model)
            }
        }
    }

    private func refresh() {
        let fileManager = FileManager.default
        onDisk = Set(models().filter { fileManager.fileExists(atPath: folder(for: $0).appending(path: Self.marker).path) }.map(\.id))
        let files = fileManager.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        usedBytes = (files?.allObjects as? [URL] ?? []).reduce(0) { total, file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            return total + (values?.isRegularFile == true ? Int64(values?.fileSize ?? 0) : 0)
        }
    }
}

/// The downloader of `--fixture` builds: ten steps of progress and a file a thousandth of the model's size, so Storage moves; the entry named
/// `failingID` fails with no connection part way, so Retry can be seen. Nothing goes over the network.
public struct FixtureModelDownloader: ModelDownloader {
    public static let failingID = "fixture.whisper-large-v3-turbo"

    private let sleep: @Sendable (Duration) async throws -> Void

    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) { self.sleep = sleep }

    public func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        try Data(count: Int((model.bytes ?? 0) / 1000)).write(to: folder.appending(path: "weights.bin"))
        for step in 1...10 {
            try await sleep(.milliseconds(250))
            await progress(Double(step) / 10)
            if model.id == Self.failingID, step == 4 { throw ModelDownloadFailure.noConnection }
        }
    }
}
