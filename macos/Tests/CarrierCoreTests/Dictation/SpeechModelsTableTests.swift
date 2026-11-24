import Foundation
import Testing
@testable import CarrierCore

private func entry(_ id: String, _ recognizer: RecognizerID, languages: Set<String> = ["en"], detects: Bool = false, partial: PartialText = .native, bytes: Int64? = 75_000_000) -> SpeechModel {
    SpeechModel(
        id: id, recognizer: recognizer, name: id, bytes: bytes, languages: languages, detectsLanguage: detects, partial: partial, licence: "MIT",
        card: URL(string: "https://huggingface.co/x")!
    )
}

@Test func theCatalogsInvariantsHoldForTheFixtureListAndAnAppleShapedEntry() {
    let models = [entry("apple.speech", .apple, languages: ["en", "es"], bytes: nil)] + FixtureRecognizer().models
    #expect(models.count > 5)
    #expect(SpeechModelCatalog.problems(in: models).isEmpty)
}

@Test func theCatalogsInvariantsReportWhatIsWrong() {
    let good = entry("whisper.tiny", .whisper)
    func bad(_ model: SpeechModel) -> [String] { SpeechModelCatalog.problems(in: [good, model]) }
    #expect(bad(good).count == 1, "a repeated id")
    #expect(bad(SpeechModel(id: "a", recognizer: .whisper, name: "A", bytes: 1, languages: ["en"], detectsLanguage: false, partial: .native, licence: "", card: good.card)).count == 1)
    #expect(bad(entry("b", .whisper, bytes: nil)).count == 1, "only Apple's has no size")
    #expect(bad(SpeechModel(id: "c", recognizer: .whisper, name: "C", bytes: 1, languages: ["en"], detectsLanguage: false, partial: .native, licence: "MIT", card: URL(string: "https://evil.example/x")!)).count == 1)
    #expect(bad(SpeechModel(id: "d", recognizer: .whisper, name: "D", bytes: 1, languages: ["en"], detectsLanguage: false, partial: .native, licence: "MIT", card: URL(string: "http://huggingface.co/x")!)).count == 1)
    #expect(bad(entry("e", .whisper, languages: ["en"], detects: true)).count == 1, "a model that detects the language must offer more than one")
}

private struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let filter: RecognizerID?
    let state: ModelState
    let inUse: String?
    let ids: [String]
    let action: SpeechModelRow.Action
    let radio: Bool?

    var testDescription: String { name }
}

private let apple = entry("apple.speech", .apple, languages: ["en", "es"], bytes: nil)
private let parakeet = entry("fluidaudio.parakeet", .fluidAudio, languages: ["de", "en", "es"], detects: true, partial: .chunked, bytes: 500_000_000)
private let tiny = entry("whisper.tiny", .whisper, partial: .atTheEnd)

@Test(arguments: [
    Case(name: "not downloaded offers Download with its size", filter: nil, state: .notDownloaded, inUse: apple.id, ids: [apple.id, parakeet.id, tiny.id], action: .download(size: "75 MB"), radio: nil),
    Case(name: "downloading shows its percentage", filter: nil, state: .downloading(0.42), inUse: apple.id, ids: [apple.id, parakeet.id, tiny.id], action: .downloading(percent: 42), radio: nil),
    Case(name: "failed says its cause", filter: nil, state: .failed("No connection"), inUse: apple.id, ids: [apple.id, parakeet.id, tiny.id], action: .failed(cause: "No connection"), radio: nil),
    Case(name: "downloaded has the trash and an empty radio", filter: nil, state: .downloaded, inUse: apple.id, ids: [apple.id, parakeet.id, tiny.id], action: .delete, radio: false),
    Case(name: "in use has a filled radio and no trash", filter: nil, state: .downloaded, inUse: "whisper.tiny", ids: [apple.id, parakeet.id, tiny.id], action: .none, radio: true),
    Case(name: "the filter narrows the list to a recognizer", filter: .whisper, state: .downloaded, inUse: apple.id, ids: [tiny.id], action: .delete, radio: false),
    Case(name: "Apple's filter shows Apple's alone", filter: .apple, state: .notDownloaded, inUse: apple.id, ids: [apple.id], action: .none, radio: true),
])
private func eachStateAndFilterGivesItsRowsAndWhatTheyOffer(c: Case) {
    let rows = speechModelRows(models: [apple, parakeet, tiny], filter: c.filter, state: { $0.id == "whisper.tiny" ? c.state : $0.bytes == nil ? .downloaded : c.state }, inUse: c.inUse)
    #expect(rows.map(\.id) == c.ids)
    let row = rows.last!
    // Apple's is managed by the system, so it is always downloaded and has no trash; the others follow the state
    if row.id == apple.id {
        #expect(row.action == .none && row.radio == true && row.size == "System")
    } else {
        #expect(row.action == c.action)
        #expect(row.radio == c.radio)
    }
}

@Test func aRowShowsWhatTheDesignDraws() {
    let rows = speechModelRows(models: [apple, parakeet, tiny], filter: nil, state: { $0.bytes == nil || $0.id == parakeet.id ? .downloaded : .notDownloaded }, inUse: parakeet.id)
    #expect(rows.map(\.size) == ["System", "500 MB", "75 MB"])
    #expect(rows.map(\.languages) == ["Your macOS languages", "3 languages", "English only"])
    #expect(rows.map(\.detectsLanguage) == [false, true, false])
    #expect(rows.map(\.text) == ["Live", "Live", "When you stop"])
    #expect(rows.map(\.live) == [true, true, false])
    #expect(rows.map(\.recognizer) == ["Apple", "FluidAudio", "Whisper"])
    #expect(rows[1].label == "fluidaudio.parakeet, FluidAudio, 500 MB, 3 languages, text appears live, in use")
    #expect(rows[2].label.hasSuffix("not downloaded"))
}

@Test func theProgressIsToldByTensToVoiceOver() {
    let rows = speechModelRows(models: [tiny], filter: nil, state: { _ in .downloading(0.47) }, inUse: nil)
    #expect(rows[0].label.hasSuffix("downloading, 40 percent"))
}

@Test func sizesAreDecimalWhateverTheLanguage() {
    #expect(formatModelSize(0) == "0 MB")
    #expect(formatModelSize(75_000_000) == "75 MB")
    #expect(formatModelSize(1_250_000_000) == "1.2 GB")
}

@Test func aSavedModelThatIsNotOnDiskShowsAppleInThePopupAndIsReported() {
    let onDisk: (SpeechModel) -> ModelState = { $0.bytes == nil || $0.id == parakeet.id ? .downloaded : .notDownloaded }
    let gone = speechModelChoice(models: [apple, parakeet, tiny], chosen: tiny, state: onDisk)
    #expect(gone.options.map(\.id) == [apple.id, parakeet.id])
    #expect(gone.shown?.id == apple.id && gone.missing?.id == tiny.id)
    let here = speechModelChoice(models: [apple, parakeet, tiny], chosen: parakeet, state: onDisk)
    #expect(here.shown?.id == parakeet.id && here.missing == nil)
}
