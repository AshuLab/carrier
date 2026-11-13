import CarrierCore
import Foundation
import Testing
@testable import Carrier

private func recognizer(in root: URL) -> WhisperKitRecognizer { WhisperKitRecognizer(modelsRoot: root, preferredLanguages: ["es-ES"]) }

private func model(_ name: String) -> SpeechModel { WhisperKitRecognizer.entries.first { $0.model.id == "whisper.\(name)" }!.model }

@Test func theCatalogsInvariantsHoldForEveryEntryOfWhisper() {
    let models = WhisperKitRecognizer.entries.map(\.model)
    #expect(models.map(\.id) == ["whisper.tiny", "whisper.base", "whisper.small", "whisper.large-v3-turbo"])
    #expect(SpeechModelCatalog.problems(in: models).isEmpty)
    #expect(models.allSatisfy { $0.recognizer == .whisper && $0.licence == "MIT" && $0.detectsLanguage && $0.languages.count == 99 })
    #expect(models.allSatisfy { $0.languages.contains("es") && $0.languages.contains("en") && $0.languages.contains("yue") == false })
    #expect(models.allSatisfy { $0.card.absoluteString.hasPrefix("https://huggingface.co/argmaxinc/whisperkit-coreml/tree/main/openai_whisper-") })
}

/// The findings' rule: by chunks only for a model fast enough (real-time factor of one pass over 10 s of 0.05 or less) and steady enough (at most
/// 10% of the words shown rewritten far back). Tiny is fast (0.024 to 0.032) and not steady (14.8%), small (0.062 to 0.083) and large v3 turbo
/// (0.088 to 0.107) are slow, and base was not measured: all four give their text at the end.
@Test func noWhisperModelPassesTheRuleForPartialTextByChunksSoTheTableSaysWhenYouStopForEach() {
    let models = WhisperKitRecognizer.entries.map(\.model)
    #expect(models.allSatisfy { $0.partial == .atTheEnd })
    let rows = speechModelRows(models: models, filter: nil, state: { _ in .downloaded }, inUse: nil)
    #expect(rows.map(\.text) == Array(repeating: "When you stop", count: 4))
}

@Test func theModelsFilesAndItsTokenizerAreInsideItsFolderOfTheCarrierFolder() {
    let root = URL(fileURLWithPath: "/carrier/app/models")
    let entry = WhisperKitRecognizer.entries[3]
    let folder = ModelStore.folder(in: root, for: entry.model)
    #expect(folder.path == "/carrier/app/models/whisper/large-v3-turbo")
    #expect(WhisperKitRecognizer.files(entry, in: folder).path == folder.path + "/models/argmaxinc/whisperkit-coreml/openai_whisper-large-v3-v20240930_turbo_632MB")
    #expect(WhisperKitRecognizer.tokenizerFiles(entry, in: folder).path == folder.path + "/models/openai/whisper-large-v3")
}

/// The library fetches a tokenizer from the Hub when its own load of the local one fails, so a damaged one is caught before it: no model in the
/// folder, so any load of the kit would fail some other way, and nothing is written, so nothing was fetched.
@Test func aDamagedTokenizerFailsWithItsCauseBeforeTheLibraryCouldFetchAnother() async throws {
    let tiny = model("tiny")
    let entry = try #require(WhisperKitRecognizer.entry(of: tiny))
    let root = FileManager.default.temporaryDirectory.appending(path: "carrier-tokenizer-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let files = WhisperKitRecognizer.tokenizerFiles(entry, in: ModelStore.folder(in: root, for: tiny))
    try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
    try Data(#"{"model": {"vocab": {"a": 0"#.utf8).write(to: files.appending(path: "tokenizer.json"))  // cut short
    try Data("{}".utf8).write(to: files.appending(path: "tokenizer_config.json"))
    let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()

    let failure = await #expect(throws: DictationFailure.self) { try await recognizer(in: root).prepare(tiny) }
    #expect(failure?.cause.contains("Whisper Tiny") == true)
    #expect(failure?.cause.contains("tokenizer.json") == true, "the cause names the file: \(failure?.cause ?? "-")")
    #expect(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() == before, "nothing was fetched")
}

/// CARRIER_IT_DICTATION names a folder that holds the models, as the app keeps them: `<folder>/whisper/<model>/models/<repository>/<folder>`.
private func modelsRoot(for model: SpeechModel) throws -> URL {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CARRIER_IT_DICTATION"]))
    let entry = try #require(WhisperKitRecognizer.entry(of: model))
    #expect(FileManager.default.fileExists(atPath: WhisperKitRecognizer.files(entry, in: ModelStore.folder(in: root, for: model)).path), "\(model.name) is not in the folder")
    return root
}

private func hear(_ clip: [CarrierCore.AudioBuffer], with recognizer: WhisperKitRecognizer, _ model: SpeechModel) async throws -> [DictationEvent] {
    let started = ContinuousClock.now
    try await recognizer.prepare(model)
    print("\(model.name) prepare took \(ContinuousClock.now - started)")
    let (audio, input) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
    let events = recognizer.recognize(audio)
    for buffer in clip { input.yield(buffer) }
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    print("\(model.name) heard: \(seen)")
    return seen
}

/// The Spanish clip with half a second of silence in front: `say` starts the voice at the first sample, and Whisper tiny and base, which
/// hear a microphone's room tone before the first word, give an empty text or a sentence that misses its first words for it as it is.
private func withRoomTone(_ clip: [CarrierCore.AudioBuffer]) -> [CarrierCore.AudioBuffer] {
    [CarrierCore.AudioBuffer(samples: [Float](repeating: 0, count: 8000), sampleRate: 16_000)] + clip
}

@Test(dictationGate, arguments: WhisperKitRecognizer.entries.map(\.model))
func eachWhisperModelLoadsAndGivesTextForTheSpanishClip(model: SpeechModel) async throws {
    let loaded = recognizer(in: try modelsRoot(for: model))
    let clip = withRoomTone(try spanishClip())
    let seen = try await hear(clip, with: loaded, model)
    // at the end: no partial text before the final
    guard case .final(let heard)? = seen.last, seen.count == 1 else {
        Issue.record("expected only a final, got \(seen)")
        return
    }
    #expect(heard.isEmpty == false)
    // the loaded model serves the next dictation as the first (Whisper's decoding is not deterministic: the words can differ)
    guard case .final(let again)? = try await hear(clip, with: loaded, model).last else {
        Issue.record("expected a final the second time")
        return
    }
    #expect(again.isEmpty == false)
}

@Test(dictationGate, arguments: WhisperKitRecognizer.entries.map(\.model))
func eachWhisperModelEndsInAnEmptyFinalWhenNothingIsSaid(model: SpeechModel) async throws {
    let seen = try await hear([], with: recognizer(in: try modelsRoot(for: model)), model)
    #expect(seen == [.final("")])
}

/// Whisper's library has no offline switch: the load is given the folder and told not to download, and the tokenizer, which it would fetch from
/// the Hub if it did not find it, is checked for first. Run this one with the network refused to see that nothing is fetched.
@Test(dictationGate) func aFolderWithAFileRemovedFailsWithItsCauseAndNothingIsFetched() async throws {
    let tiny = model("tiny")
    let entry = try #require(WhisperKitRecognizer.entry(of: tiny))
    // a copy, so the person's own folder is not touched
    let copy = FileManager.default.temporaryDirectory.appending(path: "carrier-869-damaged-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: copy) }
    try FileManager.default.copyItem(at: try modelsRoot(for: tiny), to: copy)
    let folder = ModelStore.folder(in: copy, for: tiny)

    let removed = WhisperKitRecognizer.files(entry, in: folder).appending(path: "TextDecoder.mlmodelc")
    try FileManager.default.removeItem(at: removed)
    let failure = await #expect(throws: DictationFailure.self) { try await recognizer(in: copy).prepare(tiny) }
    print("damaged folder says: \(failure?.cause ?? "-")")
    #expect(failure?.cause.contains("TextDecoder.mlmodelc") == true, "the cause names the missing file")
    #expect(failure?.cause.contains("Whisper Tiny") == true)
    #expect(FileManager.default.fileExists(atPath: removed.path) == false, "it was not downloaded again")
    #expect(FileManager.default.fileExists(atPath: WhisperKitRecognizer.files(entry, in: folder).appending(path: "AudioEncoder.mlmodelc").path), "the rest of the folder was not purged")

    // the tokenizer, which the library would fetch if it did not find it
    let tokenizer = WhisperKitRecognizer.tokenizerFiles(entry, in: folder).appending(path: "tokenizer.json")
    try FileManager.default.removeItem(at: tokenizer)
    let noTokenizer = await #expect(throws: DictationFailure.self) { try await recognizer(in: copy).prepare(tiny) }
    #expect(noTokenizer?.cause.contains("tokenizer.json") == true)
    #expect(FileManager.default.fileExists(atPath: tokenizer.path) == false, "it was not downloaded again")
}
