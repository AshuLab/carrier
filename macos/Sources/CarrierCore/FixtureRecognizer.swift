import Foundation

/// The recognizer of `--fixture` builds: a click gets a canned Spanish phrase, word by word as partial text and then a final, so every
/// state of the box can be seen with no microphone and no model. Real recognizers are registered in real builds.
public struct FixtureRecognizer: Recognizer {
    public enum Mode: Sendable, Equatable {
        /// Partial text word by word, then the final.
        case live
        /// Nothing while it listens; the whole phrase some seconds after the click that stops.
        case atTheEnd
        /// `prepare` fails with a cause.
        case failsToStart
    }

    public static let phrase = "Hola, necesito que revises los cambios de esta rama antes de enviarlos."

    // It stands in for Apple's: a fixture build registers no other.
    public let id = RecognizerID.apple
    public let mode: Mode
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(mode: Mode = .live, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.mode = mode
        self.sleep = sleep
    }

    public var models: [SpeechModel] {
        [
            SpeechModel(
                id: "fixture.canned-phrase", recognizer: id, name: "Fixture phrase", bytes: nil, languages: ["es"], detectsLanguage: false,
                partial: mode == .atTheEnd ? .atTheEnd : .native, licence: "None", card: URL(string: "https://github.com/AshuLab/carrier")!
            )
        ]
    }

    public func prepare(_ model: SpeechModel) async throws {
        try await sleep(.seconds(1.2))
        if mode == .failsToStart { throw DictationFailure("No microphone is available: the fixture is set to fail.") }
    }

    public func recognize(_ audio: AsyncStream<AudioBuffer>) -> AsyncStream<DictationEvent> {
        let (mode, sleep) = (mode, sleep)
        let (events, out) = AsyncStream<DictationEvent>.makeStream()
        let speaking = Task { () -> (heard: String, done: Bool) in
            guard mode == .live else { return ("", false) }
            var heard = ""
            for word in Self.phrase.split(separator: " ") {
                do { try await sleep(.milliseconds(350)) } catch { return (heard, false) }
                heard += heard.isEmpty ? word : " " + word
                out.yield(.partial(heard))
            }
            out.yield(.final(heard))
            return (heard, true)
        }
        Task {
            for await _ in audio {}
            speaking.cancel()
            let spoke = await speaking.value
            if mode == .atTheEnd {
                try? await sleep(.seconds(1.5))
                out.yield(.final(Self.phrase))
            } else if spoke.done == false {
                out.yield(.final(spoke.heard))
            }
            out.finish()
        }
        return events
    }
}
