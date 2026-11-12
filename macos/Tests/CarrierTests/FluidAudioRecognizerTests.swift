import CarrierCore
import FluidAudio
import Foundation
import Testing
@testable import Carrier

private func parakeet(in root: URL) -> (recognizer: FluidAudioRecognizer, model: SpeechModel) {
    let recognizer = FluidAudioRecognizer(modelsRoot: root, preferredLanguages: ["es-ES"])
    return (recognizer, recognizer.models[0])
}

@Test func parakeetTDTv3IsListedWithWhatItsCardSays() {
    let model = parakeet(in: FileManager.default.temporaryDirectory).model
    #expect(SpeechModelCatalog.problems(in: [model]).isEmpty)
    #expect(model.id == "fluidaudio.parakeet-tdt-v3" && model.licence == "CC-BY-4.0" && model.languages.count == 25)
    #expect(model.detectsLanguage && model.partial == .atTheEnd)
    #expect(model.card.absoluteString == "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml")
}

@Test func theModelsFilesAreInsideItsFolderOfTheCarrierFolder() {
    let root = URL(fileURLWithPath: "/carrier/app/models")
    let (_, model) = parakeet(in: root)
    #expect(FluidAudioRecognizer.files(in: ModelStore.folder(in: root, for: model)).path == "/carrier/app/models/fluidaudio/parakeet-tdt-v3/parakeet-tdt-0.6b-v3")
}

@Test func theRecognizerTurnsFluidAudiosOfflineModeOn() {
    ModelHub.offlineMode = false
    _ = parakeet(in: FileManager.default.temporaryDirectory)
    #expect(ModelHub.offlineMode)
}

/// CARRIER_IT_DICTATION names a folder that holds the model, as the app keeps it: `<folder>/fluidaudio/parakeet-tdt-v3/parakeet-tdt-0.6b-v3`.
private func modelsRoot() throws -> URL {
    let root = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["CARRIER_IT_DICTATION"]))
    let (_, model) = parakeet(in: root)
    #expect(FileManager.default.fileExists(atPath: FluidAudioRecognizer.files(in: ModelStore.folder(in: root, for: model)).path), "the model is not in the folder")
    return root
}

@Test(dictationGate) func parakeetGivesTextForTheSpanishClip() async throws {
    let (recognizer, model) = parakeet(in: try modelsRoot())
    let started = ContinuousClock.now
    try await recognizer.prepare(model)
    print("parakeet prepare took \(ContinuousClock.now - started)")
    let (audio, input) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
    let events = recognizer.recognize(audio)
    for buffer in try spanishClip() { input.yield(buffer) }
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    print("parakeet heard: \(seen)")
    guard case .final(let heard)? = seen.last, seen.count == 1 else {
        Issue.record("expected one final, got \(seen)")
        return
    }
    #expect(heard.isEmpty == false)
}

@Test(dictationGate) func parakeetEndsInAnEmptyFinalWhenNothingIsSaid() async throws {
    let (recognizer, model) = parakeet(in: try modelsRoot())
    try await recognizer.prepare(model)
    let (audio, input) = AsyncStream<CarrierCore.AudioBuffer>.makeStream()
    let events = recognizer.recognize(audio)
    input.finish()
    var seen: [DictationEvent] = []
    for await event in events { seen.append(event) }
    #expect(seen == [.final("")])
}

@Test(dictationGate) func aDamagedFolderFailsWithItsCauseAndNothingIsFetched() async throws {
    // a copy, so the person's own folder is not touched
    let copy = FileManager.default.temporaryDirectory.appending(path: "carrier-866-damaged-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: copy) }
    let source = try modelsRoot()
    try FileManager.default.copyItem(at: source, to: copy)
    let (recognizer, model) = parakeet(in: copy)
    let files = FluidAudioRecognizer.files(in: ModelStore.folder(in: copy, for: model))
    let removed = files.appending(path: "JointDecisionv3.mlmodelc")
    try FileManager.default.removeItem(at: removed)

    ModelHub.offlineMode = true  // the network is refused; a fetch would throw `networkDisabled`, and the library's recovery would purge the folder
    let failure = await #expect(throws: DictationFailure.self) { try await recognizer.prepare(model) }
    print("damaged folder says: \(failure?.cause ?? "-")")
    #expect(failure?.cause.contains("JointDecisionv3.mlmodelc") == true, "the cause names the missing file")
    #expect(failure?.cause.contains("Parakeet TDT v3") == true)
    #expect(FileManager.default.fileExists(atPath: removed.path) == false, "it was not downloaded again")
    #expect(FileManager.default.fileExists(atPath: files.appending(path: "Encoder.mlmodelc").path), "the rest of the folder was not purged")
}
