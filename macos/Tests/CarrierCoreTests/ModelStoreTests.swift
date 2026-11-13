import Foundation
import Testing
@testable import CarrierCore

private func entry(_ id: String, recognizer: RecognizerID = .fluidAudio, bytes: Int64? = 1_000_000) -> SpeechModel {
    SpeechModel(
        id: id, recognizer: recognizer, name: id, bytes: bytes, languages: ["en"], detectsLanguage: false, partial: .native, licence: "MIT",
        card: URL(string: "https://huggingface.co/x")!
    )
}

private let parakeet = entry("fluidaudio.parakeet")
private let tiny = entry("whisper.tiny", recognizer: .whisper)
private let apple = entry("apple.speech", recognizer: .apple, bytes: nil)

/// What a download does, step by step: writes a file, then waits for `release` (or for a cancel) and ends as scripted.
private actor Script {
    enum End { case succeeds, fails(Error) }
    var ends: [End]
    var reported: [Double] = []
    var released = false

    init(_ ends: [End]) { self.ends = ends }
    func release() { released = true }
    func next() -> End { ends.isEmpty ? .succeeds : ends.removeFirst() }
}

private struct FakeDownloader: ModelDownloader {
    let script: Script
    /// Waits for `release` after the first half; nil goes straight to its end.
    var holds = true

    func download(_ model: SpeechModel, into folder: URL, progress: @MainActor @Sendable (Double) -> Void) async throws {
        try Data(count: 1_000).write(to: folder.appending(path: "weights.bin"))
        await progress(0.5)
        while holds, await script.released == false {
            try await Task.sleep(for: .milliseconds(1))
        }
        let end = await script.next()
        await progress(1)
        if case .fails(let error) = end { throw error }
        try Data(count: 500).write(to: folder.appending(path: "tokenizer.json"))
    }
}

private func temporaryRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "carrier-models-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

@MainActor private func store(
    _ root: URL, _ script: Script, holds: Bool = true, inUse: String? = nil, log: @escaping @MainActor (DictationFailure) -> Void = { _ in },
    freeSpace: @escaping @MainActor (URL) -> Int64? = { _ in nil }
) -> ModelStore {
    ModelStore(
        root: root, models: { [apple, parakeet, tiny] }, downloader: FakeDownloader(script: script, holds: holds), inUse: { inUse }, log: log,
        freeSpace: freeSpace
    )
}

private func filesUnder(_ root: URL) -> [String] {
    ((FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? [])
        .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }.map { $0.resolvingSymlinksInPath().path.replacingOccurrences(of: root.resolvingSymlinksInPath().path + "/", with: "") }.sorted()
}

@MainActor private func waitForProgress(_ store: ModelStore, _ model: SpeechModel) async {
    for _ in 0..<2000 where store.state(of: model) != .downloading(0.5) { try? await Task.sleep(for: .milliseconds(1)) }
}

@MainActor @Test func aModelGoesFromNotDownloadedThroughItsProgressToDownloaded() async throws {
    let root = try temporaryRoot()
    let script = Script([.succeeds])
    let store = store(root, script)
    #expect(store.state(of: parakeet) == .notDownloaded)
    store.download(parakeet.id)
    #expect(store.state(of: parakeet) == .downloading(0))
    await waitForProgress(store, parakeet)
    #expect(store.state(of: parakeet) == .downloading(0.5))
    await script.release()
    await store.settled()
    #expect(store.state(of: parakeet) == .downloaded)
    #expect(filesUnder(root) == ["fluidaudio/parakeet/complete", "fluidaudio/parakeet/tokenizer.json", "fluidaudio/parakeet/weights.bin"])
}

@MainActor @Test func theModelsLiveUnderTheirRecognizerAndTheirName() throws {
    let store = store(try temporaryRoot(), Script([]))
    #expect(store.folder(for: parakeet) == store.root.appending(path: "fluidaudio/parakeet"))
    #expect(store.folder(for: tiny) == store.root.appending(path: "whisper/tiny"))
}

@MainActor @Test func aCancelLeavesNothingOnDisk() async throws {
    let root = try temporaryRoot()
    let store = store(root, Script([.succeeds]))
    store.download(parakeet.id)
    await waitForProgress(store, parakeet)
    #expect(filesUnder(root) == ["fluidaudio/parakeet/weights.bin"])
    store.cancel(parakeet.id)
    await store.settled()
    #expect(store.state(of: parakeet) == .notDownloaded)
    #expect(filesUnder(root).filter { $0.hasSuffix("weights.bin") || $0.hasSuffix("complete") }.isEmpty)
    #expect(store.usedBytes == 0)
}

@MainActor @Test(arguments: [ModelDownloadFailure.noConnection, .noSpace, .didNotCheck])
func aFailureSaysItsCauseAndLeavesNothingBehind(failure: ModelDownloadFailure) async throws {
    let root = try temporaryRoot()
    var logged: [String] = []
    let script = Script([.fails(failure)])
    let store = store(root, script, log: { logged.append($0.cause) })
    store.download(parakeet.id)
    await script.release()
    await store.settled()
    #expect(store.state(of: parakeet) == .failed(failure.cause))
    #expect(filesUnder(root).filter { $0.hasSuffix(".bin") || $0.hasSuffix("complete") }.isEmpty)
    #expect(store.usedBytes == 0)
    #expect(logged == ["Downloading fluidaudio.parakeet failed: \(failure.cause)"])
}

@MainActor @Test func anUnexpectedFailureCarriesItsDescription() async throws {
    let script = Script([.fails(DictationFailure("boom"))])
    let store = store(try temporaryRoot(), script, holds: false)
    store.download(parakeet.id)
    await store.settled()
    guard case .failed(let cause) = store.state(of: parakeet) else { Issue.record("not failed"); return }
    #expect(cause.hasPrefix("Download failed:"))
}

@MainActor @Test func aRetryAfterAFailureSucceeds() async throws {
    let root = try temporaryRoot()
    let script = Script([.fails(ModelDownloadFailure.noConnection), .succeeds])
    let store = store(root, script)
    store.download(parakeet.id)
    await script.release()
    await store.settled()
    #expect(store.state(of: parakeet) == .failed("No connection"))
    store.download(parakeet.id)
    await store.settled()
    #expect(store.state(of: parakeet) == .downloaded)
}

@MainActor @Test func aDeleteFreesTheSpace() async throws {
    let root = try temporaryRoot()
    let store = store(root, Script([.succeeds]), holds: false)
    store.download(parakeet.id)
    await store.settled()
    #expect(store.usedBytes == 1_500)
    #expect(store.delete(parakeet.id))
    #expect(store.state(of: parakeet) == .notDownloaded)
    #expect(store.usedBytes == 0)
    #expect(filesUnder(root).contains { $0.hasPrefix("fluidaudio/parakeet/") } == false)
}

@MainActor @Test func theModelInUseApplesAndTheOnesNotDownloadedHaveNoDelete() async throws {
    let root = try temporaryRoot()
    let store = store(root, Script([.succeeds]), holds: false, inUse: parakeet.id)
    store.download(parakeet.id)
    await store.settled()
    #expect(store.delete(parakeet.id) == false)
    #expect(store.state(of: parakeet) == .downloaded)
    #expect(store.delete(tiny.id) == false)
    #expect(store.state(of: apple) == .downloaded)
    #expect(store.delete(apple.id) == false)
}

@MainActor @Test func nothingOutsideTheListOrAlreadyDownloadedIsDownloaded() async throws {
    let root = try temporaryRoot()
    let store = store(root, Script([.succeeds, .succeeds]), holds: false)
    store.download("fluidaudio.not-listed")
    store.download(apple.id)
    store.download(parakeet.id)
    await store.settled()
    store.download(parakeet.id)
    #expect(store.state(of: parakeet) == .downloaded)
    #expect(filesUnder(root).allSatisfy { $0.hasPrefix("fluidaudio/parakeet/") })
}

@MainActor @Test func aPartialDownloadLeftByAQuitAppIsRemovedAtLaunch() async throws {
    let root = try temporaryRoot()
    let first = store(root, Script([.succeeds]), holds: false)
    first.download(parakeet.id)
    await first.settled()
    let partial = root.appending(path: "whisper/tiny")
    try FileManager.default.createDirectory(at: partial, withIntermediateDirectories: true)
    try Data(count: 700).write(to: partial.appending(path: "weights.bin"))

    let relaunched = store(root, Script([]))
    #expect(FileManager.default.fileExists(atPath: partial.path) == false)
    #expect(relaunched.state(of: tiny) == .notDownloaded)
    #expect(relaunched.state(of: parakeet) == .downloaded)
    #expect(relaunched.usedBytes == 1_500)
}

@MainActor @Test func storageIsTheSizeOfTheFilesUnderTheFolder() async throws {
    let root = try temporaryRoot()
    let store = store(root, Script([.succeeds, .succeeds]), holds: false)
    store.download(parakeet.id)
    store.download(tiny.id)
    await store.settled()
    let onDisk = filesUnder(root).reduce(Int64(0)) { $0 + Int64((try? Data(contentsOf: root.appending(path: $1)).count) ?? 0) }
    #expect(onDisk == 3_000)
    #expect(store.usedBytes == onDisk)
}

@MainActor @Test func theFixtureDownloaderEndsAndOneEntryFailsWithNoConnection() async throws {
    let root = try temporaryRoot()
    let models = SpeechModelCatalog.fixtureEntries
    let store = ModelStore(root: root, models: { models }, downloader: FixtureModelDownloader(sleep: { _ in }), inUse: { nil })
    let failing = try #require(models.first { $0.id == FixtureModelDownloader.failingID })
    let working = try #require(models.first { $0.id != FixtureModelDownloader.failingID })
    store.download(failing.id)
    store.download(working.id)
    await store.settled()
    #expect(store.state(of: failing) == .failed("No connection"))
    #expect(store.state(of: working) == .downloaded)
    #expect(store.usedBytes == (working.bytes ?? 0) / 1000)
}

/// The app makes the store before FluidAudio and Whisper register, so a model that is already on disk joins the list after the store looked.
@MainActor @Test func aModelOnDiskThatJoinsTheListLaterIsDownloadedAndNeverDownloadedOverItself() async throws {
    let root = try temporaryRoot()
    let first = store(root, Script([.succeeds]), holds: false)
    first.download(parakeet.id)
    await first.settled()

    var listed: [SpeechModel] = []
    let script = Script([.fails(DictationFailure("boom"))])
    let late = ModelStore(root: root, models: { listed }, downloader: FakeDownloader(script: script, holds: false), inUse: { nil })
    listed = [apple, parakeet, tiny]
    #expect(late.state(of: parakeet) == .downloaded)
    #expect(late.usedBytes == 1_500)
    late.download(parakeet.id)
    await late.settled()
    #expect(late.state(of: parakeet) == .downloaded)
    #expect(await script.ends.count == 1, "the downloader was not called")
    #expect(filesUnder(root) == ["fluidaudio/parakeet/complete", "fluidaudio/parakeet/tokenizer.json", "fluidaudio/parakeet/weights.bin"])
    #expect(late.delete(parakeet.id))
}

@MainActor @Test func aFailedOrCancelledRunNeverRemovesAFolderThatHoldsTheMarker() async throws {
    for failing in [true, false] {
        let root = try temporaryRoot()
        let script = Script([.fails(DictationFailure("boom"))])
        let store = store(root, script)
        store.download(parakeet.id)
        await waitForProgress(store, parakeet)
        // another copy of the app finished the same model while this one ran
        try Data().write(to: store.folder(for: parakeet).appending(path: ModelStore.marker))
        if failing { await script.release() } else { store.cancel(parakeet.id) }
        await store.settled()
        #expect(filesUnder(root).contains("fluidaudio/parakeet/complete"))
        #expect(store.state(of: parakeet) == .downloaded)
    }
}

@MainActor @Test func aDownloadThatDoesNotFitFailsWithNoSpaceAndStartsNothing() async throws {
    let root = try temporaryRoot()
    var logged: [String] = []
    let script = Script([.succeeds])
    let tight = store(root, script, log: { logged.append($0.cause) }, freeSpace: { _ in parakeet.bytes! - 1 })
    tight.download(parakeet.id)
    await tight.settled()
    #expect(tight.state(of: parakeet) == .failed("No space on the disk"))
    #expect(logged == ["Downloading fluidaudio.parakeet failed: No space on the disk"])
    #expect(await script.ends.count == 1)
    #expect(filesUnder(root).isEmpty)

    let fits = store(root, Script([.succeeds]), holds: false, freeSpace: { _ in parakeet.bytes! })
    fits.download(parakeet.id)
    await fits.settled()
    #expect(fits.state(of: parakeet) == .downloaded)
}

@Test func onlyTheCausesThePersonCanFixAreToldAsTheirOwn() {
    #expect(ModelDownloadFailure(URLError(.notConnectedToInternet)) == .noConnection)
    #expect(ModelDownloadFailure(URLError(.networkConnectionLost)) == .noConnection)
    #expect(ModelDownloadFailure(URLError(.timedOut)) == .noConnection)
    #expect(ModelDownloadFailure(URLError(.badServerResponse)) == nil)
    #expect(ModelDownloadFailure(URLError(.fileDoesNotExist)) == nil)
    #expect(ModelDownloadFailure(URLError(.cancelled)) == nil)
    #expect(ModelDownloadFailure(CocoaError(.fileWriteOutOfSpace)) == .noSpace)
    #expect(ModelDownloadFailure(POSIXError(.ENOSPC)) == .noSpace)
    #expect(ModelDownloadFailure(DictationFailure("boom")) == nil)
}

@Test func theFreeSpaceIsReadFromTheNearestFolderThatExists() throws {
    let missing = FileManager.default.temporaryDirectory.appending(path: "carrier-nothing-\(UUID().uuidString)/app/models")
    #expect(try #require(ModelStore.availableBytes(at: missing)) > 0)
}
