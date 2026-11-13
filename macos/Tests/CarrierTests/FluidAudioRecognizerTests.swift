import CarrierCore
import FluidAudio
import Foundation
import Testing
@testable import Carrier

private func recognizer(in root: URL) -> FluidAudioRecognizer { FluidAudioRecognizer(modelsRoot: root, preferredLanguages: ["es-ES"]) }

private func model(_ name: String) -> SpeechModel { FluidAudioRecognizer.entries.first { $0.model.id == "fluidaudio.\(name)" }!.model }

private let parakeet = model("parakeet-tdt-v3")

@Test func theCatalogsInvariantsHoldForEveryEntryOfFluidAudio() {
    let models = FluidAudioRecognizer.entries.map(\.model)
    #expect(models.count == 6)
    #expect(SpeechModelCatalog.problems(in: models).isEmpty)
    #expect(models.allSatisfy { $0.recognizer == .fluidAudio })
}

@Test func eachEntryIsListedWithWhatItsCardSays() {
    #expect(parakeet.licence == "CC-BY-4.0" && parakeet.languages.count == 25 && parakeet.detectsLanguage && parakeet.partial == .chunked)
    #expect(parakeet.card.absoluteString == "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")
    let ultra = model("parakeet-ultra")
    #expect(ultra.licence == "CC-BY-4.0" && ultra.languages == parakeet.languages && ultra.detectsLanguage && ultra.partial == .atTheEnd)
    let eou = model("parakeet-eou-120m")
    #expect(eou.licence == "NVIDIA Open Model License" && eou.languages == ["en"] && eou.detectsLanguage == false && eou.partial == .native)
    let english = model("nemotron-streaming-en")
    #expect(english.licence == "NVIDIA Open Model License" && english.languages == ["en"] && english.detectsLanguage == false && english.partial == .native)
    let multilingual = model("nemotron-3.5-multilingual")
    #expect(multilingual.licence == "OpenMDW-1.1" && multilingual.detectsLanguage && multilingual.partial == .native)
    #expect(multilingual.languages == ["de", "en", "es", "fr", "it", "ja", "pt", "zh"])
    let unified = model("parakeet-unified-0.6b")
    #expect(unified.licence == "NVIDIA Open Model License" && unified.languages == ["en"] && unified.partial == .native)
}

@Test func parakeetTDTv3TakesThePartialTextOfTheCoreAndTheTableSaysLiveWhileUltraIsNotMeasuredAndSaysWhenYouStop() {
    let rows = speechModelRows(models: [parakeet, model("parakeet-ultra")], filter: nil, state: { _ in .downloaded }, inUse: nil)
    #expect(rows.map(\.text) == ["Live", "When you stop"])
}

@Test func anEnglishOnlyModelOffersEnglishAndTheMultilingualOneOffersAutomaticAndItsEightLanguages() {
    let english = languageChoices(for: model("nemotron-streaming-en"), macOSLanguages: ["es-ES"], saved: nil)
    #expect(english.offered == ["en"] && english.selected == "en")
    let multilingual = languageChoices(for: model("nemotron-3.5-multilingual"), macOSLanguages: ["es-ES"], saved: nil)
    #expect(multilingual.offered == [automaticLanguage, "es", "de", "en", "fr", "it", "ja", "pt", "zh"] && multilingual.selected == automaticLanguage)
}

@Test func theModelsFilesAreInsideItsFolderOfTheCarrierFolder() {
    let root = URL(fileURLWithPath: "/carrier/app/models")
    func files(_ name: String) -> String {
        let (model, engine) = FluidAudioRecognizer.entries.first { $0.model.id == "fluidaudio.\(name)" }!
        return FluidAudioRecognizer.files(engine, in: ModelStore.folder(in: root, for: model)).path
    }
    #expect(files("parakeet-tdt-v3") == "/carrier/app/models/fluidaudio/parakeet-tdt-v3/parakeet-tdt-0.6b-v3")
    #expect(files("nemotron-3.5-multilingual").hasSuffix("/fluidaudio/nemotron-3.5-multilingual/\(Repo.nemotronMultilingual.folderName)/multilingual/1120ms"))
}

@Test func theRecognizerTurnsFluidAudiosOfflineModeOn() {
    ModelHub.offlineMode = false
    _ = recognizer(in: FileManager.default.temporaryDirectory)
    #expect(ModelHub.offlineMode)
}

@Test func onlyALostConnectionIsToldAsNoConnectionAndABadResponseKeepsItsDescription() {
    #expect(FluidAudioDownloader.failure(URLError(.notConnectedToInternet)) == .noConnection)
    #expect(FluidAudioDownloader.failure(DownloadError.downloadFailed(path: "x", underlying: URLError(.timedOut))) == .noConnection)
    #expect(FluidAudioDownloader.failure(URLError(.badServerResponse)) == nil)
    #expect(FluidAudioDownloader.failure(DownloadError.downloadFailed(path: "x", underlying: URLError(.fileDoesNotExist))) == nil)
    #expect(FluidAudioDownloader.failure(DownloadError.invalidArtifact(path: "x", reason: "size")) == .didNotCheck)
    #expect(FluidAudioDownloader.failure(CocoaError(.fileWriteOutOfSpace)) == .noSpace)
}

/// CARRIER_IT_DICTATION names a folder that holds the models, as the app keeps them: `<folder>/fluidaudio/<model>/<repository>`.
private func modelsRoot(for model: SpeechModel) throws -> URL {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CARRIER_IT_DICTATION"]))
    let engine = try #require(FluidAudioRecognizer.engine(of: model))
    #expect(FileManager.default.fileExists(atPath: FluidAudioRecognizer.files(engine, in: ModelStore.folder(in: root, for: model)).path), "\(model.name) is not in the folder")
    return root
}

/// A clip given at the pace of a person speaking when `paced`, since the core's chunking works on the audio's own timeline.
private func hear(
    _ clip: [CarrierCore.AudioBuffer], with recognizer: FluidAudioRecognizer, _ model: SpeechModel, paced: Bool = false
) async throws -> [DictationEvent] {
    let started = ContinuousClock.now
    try await recognizer.prepare(model)
    print("\(model.name) prepare took \(ContinuousClock.now - started)")
    let (audio, input) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
    let events = recognizer.recognize(audio)
    for buffer in clip {
        input.yield(buffer)
        if paced { try await Task.sleep(for: .seconds(Double(buffer.samples.count) / buffer.sampleRate)) }
    }
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    print("\(model.name) heard: \(seen)")
    return seen
}

/// The Spanish clip, or an English one made with `say` where the model only understands English.
@Test(dictationGate, arguments: FluidAudioRecognizer.entries.map(\.model))
func eachModelLoadsAndGivesTextForTheClip(model: SpeechModel) async throws {
    let clip = model.languages.contains("es") ? try spanishClip() : try englishClip()
    let loaded = recognizer(in: try modelsRoot(for: model))
    let seen = try await hear(clip, with: loaded, model, paced: model.partial == .chunked)
    guard case .final(let heard)? = seen.last else {
        Issue.record("expected a final at the end, got \(seen)")
        return
    }
    #expect(heard.isEmpty == false)
    let partials = seen.dropLast()
    #expect(partials.allSatisfy { if case .partial = $0 { true } else { false } })
    switch model.partial {
    case .native: #expect(partials.isEmpty == false, "a native model shows words before the final")
    case .chunked: #expect(partials.isEmpty == false, "a model with the core's chunking shows words before the final")
    case .atTheEnd: #expect(partials.isEmpty)
    }
    // the loaded model serves the next dictation as the first: nothing of the one before is left in it
    #expect(try await hear(clip, with: loaded, model).last == .final(heard))
}

@Test(dictationGate, arguments: FluidAudioRecognizer.entries.map(\.model))
func eachModelEndsInAnEmptyFinalWhenNothingIsSaid(model: SpeechModel) async throws {
    let seen = try await hear([], with: recognizer(in: try modelsRoot(for: model)), model)
    #expect(seen == [.final("")])
}

@Test(dictationGate) func aDamagedFolderFailsWithItsCauseAndNothingIsFetched() async throws {
    // a copy, so the person's own folder is not touched
    let copy = FileManager.default.temporaryDirectory.appending(path: "carrier-866-damaged-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: copy) }
    let source = try modelsRoot(for: parakeet)
    try FileManager.default.copyItem(at: source, to: copy)
    let files = FluidAudioRecognizer.files(.batch(.v3, .parakeetV3), in: ModelStore.folder(in: copy, for: parakeet))
    let removed = files.appending(path: "JointDecisionv3.mlmodelc")
    try FileManager.default.removeItem(at: removed)

    ModelHub.offlineMode = true  // the network is refused; a fetch would throw `networkDisabled`, and the library's recovery would purge the folder
    let failure = await #expect(throws: DictationFailure.self) { try await recognizer(in: copy).prepare(parakeet) }
    print("damaged folder says: \(failure?.cause ?? "-")")
    #expect(failure?.cause.contains("JointDecisionv3.mlmodelc") == true, "the cause names the missing file")
    #expect(failure?.cause.contains("Parakeet TDT v3") == true)
    #expect(FileManager.default.fileExists(atPath: removed.path) == false, "it was not downloaded again")
    #expect(FileManager.default.fileExists(atPath: files.appending(path: "Encoder.mlmodelc").path), "the rest of the folder was not purged")
}
