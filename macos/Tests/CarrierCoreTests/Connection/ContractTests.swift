import Foundation
import Testing
@testable import CarrierCore

// The two contracts with the engine that fail silently: a capability name the app does not know (the feature never shows)
// and a config default or rule that differs from the engine's. The TypeScript tests write the files
// (src/control/capabilities-contract.test.ts, src/config/engine-config-contract.test.ts); UPDATE_FIXTURES=1 rewrites them.

private let fixtures = testPaths().fixtures

private func golden(_ name: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(name))) as? [String: Any])
}

@Test func everyCapabilityAHostAnnouncesIsACaseTheAppKnows() throws {
    let file = try golden("capabilities.json")
    let announced = (file["engine"] as? [String] ?? []) + (file["chat"] as? [String] ?? [])
    #expect(announced.isEmpty == false)
    #expect(announced.filter { ControlClient.Capability(rawValue: $0) == nil } == [])
    #expect(ControlClient.Capability.allCases.filter { announced.contains($0.rawValue) == false } == [])
}

@Test func theFixtureServerAnnouncesOnlyNamesTheAppKnows() throws {
    let server = try FixtureServer(fixtures: fixtures.path)
    defer { server.stop() }
    for hello in [server.hello, server.chatHello] {
        let names = try #require(JSONSerialization.jsonObject(with: hello) as? [String: Any])["capabilities"] as? [String] ?? []
        #expect(names.isEmpty == false)
        #expect(names.filter { ControlClient.Capability(rawValue: $0) == nil } == [])
    }
}

@Test func theAppHasTheEnginesConfigDefaults() throws {
    let defaults = try JSONSerialization.data(withJSONObject: try #require(try golden("engine-config.json")["defaults"]))
    #expect(EngineConfig(json: defaults) == EngineConfig())
}

@Test func theAppRefusesWhatTheEngineRefuses() throws {
    let cases = try #require(try golden("engine-config.json")["cases"] as? [[String: Any]])
    #expect(cases.isEmpty == false)
    for item in cases {
        let field = try #require(item["field"] as? String), valid = try #require(item["valid"] as? Bool)
        let path = field.split(separator: ".").map(String.init)
        let file: [String: Any] = path.count == 1 ? [path[0]: item["value"]!] : [path[0]: [path[1]: item["value"]!]]
        let config = EngineConfig(json: try JSONSerialization.data(withJSONObject: file))
        #expect((config.problems[path.last!] == nil) == valid, "\(field) = \(item["value"]!)")
    }
}

// projects.json: src/config/projects.test.ts writes the files and what the engine side reads from each (entries) or refuses in each (the fields).
@Test func theAppReadsTheEntriesTheHostReadsFromEveryValidProjectsFile() throws {
    let cases = try #require(try golden("projects.json")["valid"] as? [[String: Any]])
    #expect(cases.isEmpty == false)
    for item in cases {
        let name = try #require(item["name"] as? String)
        let entries = try #require(item["entries"] as? [[String: Any]])
        let read = try readProjects(JSONSerialization.data(withJSONObject: try #require(item["file"])))
        #expect(read == entries.map(ProjectEntry.init(json:)), "\(name)")
    }
}

@Test func theAppRefusesEveryProjectsFileTheHostRefusesNamingTheSameFields() throws {
    let cases = try #require(try golden("projects.json")["invalid"] as? [[String: Any]])
    #expect(cases.isEmpty == false)
    for item in cases {
        let name = try #require(item["name"] as? String), fields = try #require(item["fields"] as? [String])
        let data = try JSONSerialization.data(withJSONObject: try #require(item["file"]))
        do {
            _ = try readProjects(data)
            Issue.record("\(name) was accepted")
        } catch let error as ProjectsFileError {
            guard case .invalid(let found) = error else { Issue.record("\(name): \(error)"); continue }
            #expect(found.map(\.path) == fields, "\(name)")
        }
    }
}

// The requests that change a config file (ADR 0053): `config-requests.json` lists those of the two sockets (src/control/config-requests.test.ts, which also checks that each has a golden its
// schema accepts), and each one the app builds is encoded as its golden says. A request in the list that the app does not build, or one it builds without a golden, fails here.
@Test func everyConfigRequestOfBothSocketsIsEncodedAsItsGoldenSays() throws {
    var rows: [(file: String, key: String?, request: Data)] = projectsGoldenChanges.map { ("chat-edit-projects.json", $0.name, $0.change.request) }
    rows += providersGoldenTable.map { ($0.golden + ".json", nil, $0.request.request) }
    rows.append(("chat-edit-settings.json", nil, goldenChatSettings.request))
    rows += ([("engine-set-watched-repos.json", goldenRepos), ("engine-edit-behavior.json", EngineConfigChange.behavior(goldenBehavior()))] + goldenRoleChanges).map { ($0.0, nil, $0.1.request) }
    var built: Set<String> = []
    for row in rows {
        let file = try golden(row.file)
        let entry = try #require(row.key.map { file[$0] as? [String: Any] } ?? file)
        let request = try #require(entry["request"] as? [String: Any])
        let encoded = try #require(JSONSerialization.jsonObject(with: row.request) as? NSDictionary)
        #expect(encoded == request as NSDictionary, Comment(rawValue: "\(row.file) \(row.key ?? "")"))
        built.insert(try #require(request["cmd"] as? String))
    }
    let listed = try golden("config-requests.json")
    let all = Set((listed["chat"] as? [String] ?? []) + (listed["engine"] as? [String] ?? []))
    #expect(all.isEmpty == false && built == all, "built \(built.subtracting(all).sorted()), not built \(all.subtracting(built).sorted())")
}

// The words of every text code (ADR 0055, ADR 0054): `text.<code>` in the generated catalog, in English and in Spanish.
// The codes of Node are the golden list; the ones the app raises itself are `appRefusals`. A code with no key in either language fails here.
// What the key takes as arguments, and the plural forms, are checked on the source of the copy (design/generate.test.ts).

/// The catalog's strings, by key: the languages each one has words in.
private func catalogLanguages() throws -> [String: [String: String]] {
    let file = testPaths().sources.appendingPathComponent("CarrierCore/Resources/Localizable.xcstrings")
    let catalog = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: [String: Any]])
    return strings.mapValues { entry in
        let languages = entry["localizations"] as? [String: [String: Any]] ?? [:]
        return languages.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String }
    }
}

/// The catalog keys that hold the words of `code`: `text.<code>` and its arguments, or one key per branch of a select, `text.<code>.<branch>` and its arguments.
private func keys(of code: String, in catalog: [String: [String: String]]) -> [String] {
    catalog.keys.filter { key in
        let name = key.split(separator: " ", maxSplits: 1)[0]
        return name == "text.\(code)" || name.hasPrefix("text.\(code).")
    }
}

private func expectWords(forCodes codes: [String]) throws {
    let catalog = try catalogLanguages()
    for code in codes {
        let found = keys(of: code, in: catalog)
        #expect(found.isEmpty == false, "text.\(code) is not in the catalog")
        for key in found {
            for language in ["en", "es"] {
                #expect(catalog[key]?[language]?.isEmpty == false, "\(key) has no words in \(language)")
            }
        }
    }
}

@Test func everyCodeOfNodeHasItsWordsInEnglishAndSpanish() throws {
    let codes = try golden("text-codes.json").keys.sorted()
    #expect(codes.count > 100)
    try expectWords(forCodes: codes)
}

@Test func everyCodeTheAppRaisesItselfHasItsWordsInEnglishAndSpanish() throws {
    let codes = appRefusals.compactMap(\.code)
    #expect(codes.count == appRefusals.count)
    try expectWords(forCodes: codes)
}

@Test func aCodeWithNoKeyInTheCatalogIsFound() throws {
    let catalog = try catalogLanguages()
    #expect(keys(of: "session.noSuchCode", in: catalog).isEmpty)
    // a branch of a select is a key of the code, a longer code that starts the same is not
    #expect(keys(of: "session.busy", in: catalog).allSatisfy { $0.hasPrefix("text.session.busy.") })
    #expect(keys(of: "session.busy", in: catalog).isEmpty == false)
    #expect(keys(of: "session.bus", in: catalog).isEmpty)
}
