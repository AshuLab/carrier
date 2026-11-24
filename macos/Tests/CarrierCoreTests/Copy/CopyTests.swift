import Foundation
import Testing

@testable import CarrierCore

/// design/copy/fixtures.json is shared with the web's tests: a key, its arguments and the words each locale must get.
struct CopyTests {
    struct Case: Decodable {
        struct Args: Decodable {
            var count: Int?
            var tokens: Int?
            var state: String?
        }
        let key: String
        let args: Args
        let language: String
        let region: String
        let text: String
    }

    static let cases: [Case] = {
        let file = testPaths().root.appendingPathComponent("design/copy/fixtures.json")
        guard let data = try? Data(contentsOf: file), let cases = try? JSONDecoder().decode([Case].self, from: data) else {
            fatalError("cannot read \(file.path)")
        }
        return cases
    }()

    /// Runs a case through `Copy`; nil when `Copy` has no such key (or the case lacks an argument it needs).
    func render(_ fixture: Case) -> String? {
        let bundle = Copy.bundle(fixture.language)
        let locale = Locale(identifier: "\(fixture.language)_\(fixture.region)")
        let args = fixture.args
        switch fixture.key {
        case "emptyEpics":
            return Copy.emptyEpics(bundle: bundle, locale: locale)
        case "epicsWaiting":
            return args.count.map { Copy.epicsWaiting(count: $0, bundle: bundle, locale: locale) }
        case "tokensUsed":
            return args.tokens.map { Copy.tokensUsed(tokens: $0, bundle: bundle, locale: locale) }
        case "epicState":
            guard let state = args.state.flatMap(Copy.EpicState.init(fixture:)) else { return nil }
            return Copy.epicState(state: state, bundle: bundle, locale: locale)
        case "epicsByState":
            guard let count = args.count, let state = args.state.flatMap(Copy.EpicsByState.init(fixture:)) else { return nil }
            return Copy.epicsByState(state: state, count: count, bundle: bundle, locale: locale)
        default:
            return nil
        }
    }

    @Test("every case of fixtures.json says its words in its language and locale", arguments: cases)
    func fixture(_ fixture: Case) {
        #expect(render(fixture) == fixture.text, "\(fixture.key) \(fixture.language)-\(fixture.region)")
    }

    @Test func fixturesCoverEnglishSpanishAndArgentina() {
        let locales = Set(Self.cases.map { "\($0.language)-\($0.region)" })
        #expect(locales == ["en-US", "es-ES", "es-AR"])
        #expect(Self.cases.count >= 15)
    }

    @Test func aKeyCopyLacksFails() {
        let unknown = Case(key: "noSuchKey", args: .init(), language: "en", region: "US", text: "")
        #expect(render(unknown) == nil)
    }

    @Test func aLanguageWithNoCatalogFallsBackToCarrierResources() {
        #expect(Copy.bundle("fr") == carrierResources)
        #expect(Copy.bundle("es") != carrierResources)
    }
}

extension Copy.EpicState {
    init?(fixture: String) {
        switch fixture {
        case "running": self = .running
        case "paused": self = .paused
        case "other": self = .other
        default: return nil
        }
    }
}

extension Copy.EpicsByState {
    init?(fixture: String) {
        switch fixture {
        case "running": self = .running
        case "other": self = .other
        default: return nil
        }
    }
}
