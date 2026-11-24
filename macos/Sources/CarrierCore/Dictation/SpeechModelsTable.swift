import Foundation

// The speech models table of the Dictation page (docs/specs/dictation-in-the-app.md, stories 8 to 10): the rules the fixed list must keep and
// what each row shows and offers, apart from its views.

public extension RecognizerID {
    var title: String {
        switch self {
        case .apple: "Apple"
        case .fluidAudio: "FluidAudio"
        case .whisper: "Whisper"
        }
    }
}

/// The list of speech models is fixed in the app's code, each recognizer bringing its own entries; this is what every entry must keep.
public enum SpeechModelCatalog {
    /// The hosts a model's card may be on.
    public static let allowedCardHosts: Set<String> = ["huggingface.co", "github.com", "developer.apple.com"]

    /// What is wrong with the list, one line each; empty when it is fine.
    public static func problems(in models: [SpeechModel]) -> [String] {
        var problems: [String] = []
        var seen: Set<String> = []
        for model in models {
            if seen.insert(model.id).inserted == false { problems.append("\(model.id): the id is not unique") }
            if model.licence.isEmpty { problems.append("\(model.id): no licence") }
            if model.bytes == nil, model.recognizer != .apple { problems.append("\(model.id): no size, and only Apple's is managed by the system") }
            if model.card.scheme != "https" || allowedCardHosts.contains(model.card.host() ?? "") == false {
                problems.append("\(model.id): the card is not an https link on an allowed host")
            }
            if model.detectsLanguage, model.languages.count < 2 { problems.append("\(model.id): detects the language but offers fewer than two") }
        }
        return problems
    }

    /// What a fixture build adds to its recognizer's list so every state of the table can be seen. Invented: nothing here can be downloaded
    /// from anywhere.
    public static let fixtureEntries: [SpeechModel] = [
        fixture("fixture.parakeet-tdt-v3", .fluidAudio, "Parakeet TDT v3", 500, ["de", "en", "es", "fr", "it", "pt"], true, .chunked, "CC-BY-4.0"),
        fixture("fixture.nemotron-streaming-en", .fluidAudio, "Nemotron Streaming EN", 630, ["en"], false, .native, "NVIDIA Open Model License"),
        fixture("fixture.whisper-tiny", .whisper, "Whisper Tiny", 75, ["de", "en", "es", "fr", "it", "pt"], true, .chunked, "MIT"),
        fixture(FixtureModelDownloader.failingID, .whisper, "Whisper Large v3 Turbo", 630, ["de", "en", "es", "fr", "it", "pt"], true, .atTheEnd, "MIT"),
    ]

    private static func fixture(
        _ id: String, _ recognizer: RecognizerID, _ name: String, _ megabytes: Int64, _ languages: Set<String>, _ detects: Bool,
        _ partial: PartialText, _ licence: String
    ) -> SpeechModel {
        SpeechModel(
            id: id, recognizer: recognizer, name: name, bytes: megabytes * 1_000_000, languages: languages, detectsLanguage: detects,
            partial: partial, licence: licence, card: URL(string: "https://huggingface.co/AshuLab/carrier-fixture")!
        )
    }
}

/// "75 MB", "1.2 GB": decimal, whatever the language of the Mac, so a column of sizes lines up.
public func formatModelSize(_ bytes: Int64) -> String {
    bytes >= 1_000_000_000 ? String(format: "%.1f GB", Double(bytes) / 1_000_000_000) : "\(bytes / 1_000_000) MB"
}

/// One row of the table: what it shows and what it offers.
public struct SpeechModelRow: Equatable, Identifiable, Sendable {
    public enum Action: Hashable, Sendable {
        /// "Download · 500 MB".
        case download(size: String)
        /// A bar with the percentage and Cancel.
        case downloading(percent: Int)
        /// The cause, in red, and Retry.
        case failed(cause: String)
        /// The trash.
        case delete
        /// Apple's and the model in use have none.
        case none
    }

    public let id: String
    public let name: String
    public let recognizer: String
    public let licence: String
    public let card: URL
    /// "System" for Apple's.
    public let size: String
    public let languages: String
    public let detectsLanguage: Bool
    /// "Live" or "When you stop".
    public let text: String
    /// Whether the text appears as the person speaks (`text` is "Live"): the chip's tint follows this, not the words.
    public let live: Bool
    /// A downloaded row has a radio, filled when it is the model in use; the others have none.
    public let radio: Bool?
    public let action: Action
    public let label: String
}

/// The rows to draw: the models of the filter (all of them when nil), each with what its state shows and offers.
public func speechModelRows(models: [SpeechModel], filter: RecognizerID?, state: (SpeechModel) -> ModelState, inUse: String?) -> [SpeechModelRow] {
    models.filter { filter == nil || $0.recognizer == filter }.map { model in
        let state = state(model)
        let size = model.bytes.map(formatModelSize) ?? "System"
        let live = model.partial != .atTheEnd
        let text = live ? "Live" : "When you stop"
        let languages = languagesText(model)
        let action: SpeechModelRow.Action
        let status: String
        switch state {
        case .notDownloaded: (action, status) = (.download(size: size), "not downloaded")
        case .downloading(let fraction):
            let percent = Int((fraction * 100).rounded())
            // VoiceOver hears it by tens, so it does not talk over the person
            (action, status) = (.downloading(percent: percent), "downloading, \(percent / 10 * 10) percent")
        case .failed(let cause): (action, status) = (.failed(cause: cause), "download failed, \(cause)")
        case .downloaded:
            let used = model.id == inUse
            (action, status) = (used || model.bytes == nil ? .none : .delete, used ? "in use" : "downloaded")
        }
        return SpeechModelRow(
            id: model.id, name: model.name, recognizer: model.recognizer.title, licence: model.licence, card: model.card, size: size, languages: languages,
            detectsLanguage: model.detectsLanguage, text: text, live: live, radio: state == .downloaded ? model.id == inUse : nil, action: action,
            label: "\(model.name), \(model.recognizer.title), \(size), \(languages), text appears \(text.lowercased()), \(status)"
        )
    }
}

/// What the Speech model popup offers and shows: the models on disk, and the one drawn as chosen. A saved model that is no longer on disk (the person
/// deleted its folder) is `missing`, and the popup shows Apple's, which is always there, instead of whichever entry happens to be first.
public struct SpeechModelChoice {
    public let options: [SpeechModel]
    public let shown: SpeechModel?
    public let missing: SpeechModel?
}

public func speechModelChoice(models: [SpeechModel], chosen: SpeechModel?, state: (SpeechModel) -> ModelState) -> SpeechModelChoice {
    let options = models.filter { state($0) == .downloaded }
    let onDisk = chosen.map { chosen in options.contains { $0.id == chosen.id } } ?? false
    return SpeechModelChoice(
        options: options, shown: onDisk ? chosen : options.first { $0.recognizer == .apple }, missing: onDisk ? nil : chosen
    )
}

private func languagesText(_ model: SpeechModel) -> String {
    if model.recognizer == .apple { return "Your macOS languages" }
    guard model.languages.count == 1, let code = model.languages.first else { return "\(model.languages.count) languages" }
    return code == "en" ? "English only" : "\((Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code)) only"
}
