import Foundation
import Testing
@testable import CarrierCore

// Every text code of the app, and every one it answers or decides by, is in the pattern and the golden list (docs/adr/0055).

// the pattern of `textCode` in src/chat/runner.ts
private let codePattern = #"[a-z][a-zA-Z]*(\.[a-z][a-zA-Z]*)+"#
private func isTextCode(_ text: String) -> Bool { text.range(of: "^\(codePattern)$", options: .regularExpression) != nil }

private func goldenCodes() throws -> Set<String> {
    let data = try Data(contentsOf: testPaths().fixtures.appendingPathComponent("text-codes.json"))
    return Set(try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
}

/// The code-shaped string literals of the Swift files of `folder` (under Sources/CarrierCore), by file.
private func literals(in folder: String) throws -> [String: Set<String>] {
    let root = testPaths().sources.appendingPathComponent("CarrierCore").appendingPathComponent(folder)
    var found: [String: Set<String>] = [:]
    for case let file as URL in try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)) where file.pathExtension == "swift" {
        let text = try String(contentsOf: file, encoding: .utf8)
        let quoted = try NSRegularExpression(pattern: "\"(\(codePattern))\"")
        found[file.lastPathComponent] = Set(quoted.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { Range($0.range(at: 1), in: text).map { String(text[$0]) } })
    }
    return found
}

@Test func theAppsOwnRefusalsEachHaveACodeOfTheirOwnThatMatchesThePattern() throws {
    let own: [Refusal] = [
        .hostLacks("stopTask"), .projectsNeedNewerHost, .usageNeedsNewerHost, .folderGone, .hostNotRunning, .hostNotAnswering, .hostTookTooLong, .hostNotUnderstood,
        .folderUnusable, .sessionIdInvalid, .rangeInvalid, .fileInvalid, .epicInvalid, .executionInvalid, .projectNameEmpty, .projectNameTooLong, .projectNameBadStart,
        .projectNameBadCharacters, .carrierOlder, .appOlder,
    ]
    let codes = own.compactMap(\.code)
    #expect(codes.count == own.count && Set(codes).count == own.count)
    for code in codes {
        #expect(isTextCode(code) && code.hasPrefix("app."), "\(code)")
    }
    // none is left out of the list: every `app.` code written in the sources is one of these
    let written = try literals(in: "").values.reduce(into: Set<String>()) { $0.formUnion($1.filter { $0.hasPrefix("app.") }) }
    #expect(written == Set(codes))
}

@Test func everyCodeTheAppDecidesByOrTheFixtureHostAnswersIsInTheGoldenList() throws {
    let golden = try goldenCodes()
    // the codes of Node written in the sources of the app: the ones it decides by and the ones the fixture host answers
    // a literal that starts as one of the golden codes does (`github.`, `doctor.`) is one, unless it is a host name or an icon
    let families = Set(golden.map { String($0.split(separator: ".")[0]) })
    let notCodes: Set = ["github.com", "folder.badge.plus", "folder.badge.gearshape"]
    for (file, codes) in try literals(in: "") {
        for code in codes where code.hasPrefix("app.") == false && notCodes.contains(code) == false && families.contains(String(code.split(separator: ".")[0])) {
            #expect(golden.contains(code), "\(code) in \(file) is not in text-codes.json")
        }
    }
    // the codes chat-names.json answers for a worktree name
    let names = try JSONSerialization.jsonObject(with: Data(contentsOf: testPaths().fixtures.appendingPathComponent("chat-names.json"))) as? [String: Any]
    for check in (names?["checks"] as? [String: [String: Any]] ?? [:]).values {
        #expect(golden.contains(try #require(check["code"] as? String)))
    }
}
