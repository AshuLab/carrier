import Foundation
import Testing
@testable import CarrierCore

// The persona and the failover steps of a global role, written to a temporary config.json: what is saved, what is refused before writing, and that
// every other key stays.

private let accounts = ["claude", "codex", "agy"]
private let base = #"""
{"keep": {"deep": [1, 2]}, "orchestratorProfile": "acme-author",
 "profiles": {"acme-author": {"kind": "forge", "agent": "acme-author"}},
 "agents": {"author": {"profile": "acme-author", "provider": "claude", "model": "m", "extra": true},
            "reviewer": {"profile": "acme-author", "provider": "codex", "model": "g", "persona": {"name": "Rex", "prompt": "Be kind"}}},
 "failover": {"triggers": ["usage_limit"], "roles": {"reviewer": [{"provider": "claude"}, {"provider": "agy", "model": "x"}, {"provider": "claude", "model": "z"}]}},
 "repos": [{"name": "a/b"}]}
"""#

private func temporaryConfig() throws -> String {
    let path = NSTemporaryDirectory() + "carrier-role-details-\(UUID().uuidString).json"
    try base.write(toFile: path, atomically: true, encoding: .utf8)
    return path
}

private func file(_ path: String) throws -> NSDictionary {
    NSDictionary(dictionary: try #require(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]))
}

private func value(_ path: String, _ keys: String...) throws -> Any? {
    var node: Any? = try file(path)
    for key in keys { node = (node as? [String: Any])?[key] }
    return node
}

private func step(_ provider: String, _ model: String? = nil) -> FailoverStep { FailoverStep(provider: provider, model: model) }

private func persona(name: String?, prompt: String?, role: AgentRole = .author, path: String) -> RoleSave {
    saveGlobalPersona(name: name, prompt: prompt, role: role, path: path)
}

private func failover(_ first: FailoverStep?, _ second: FailoverStep? = nil, role: AgentRole = .author, path: String) -> RoleSave {
    saveGlobalFailover(first: first, second: second, role: role, path: path, accounts: accounts)
}

@Test func aRolesPersonaWithOnlyANameOrOnlyAPromptIsWrittenAsSuch() throws {
    let path = try temporaryConfig()
    #expect(persona(name: "  Ada  ", prompt: nil, path: path) == .saved)
    #expect(try value(path, "agents", "author", "persona") as? NSDictionary == ["name": "Ada"])
    #expect(persona(name: nil, prompt: "Be brief\nand kind ", path: path) == .saved)
    #expect(try value(path, "agents", "author", "persona") as? NSDictionary == ["prompt": "Be brief\nand kind"])
    #expect(persona(name: "Ada", prompt: "Be brief", path: path) == .saved)
    #expect(try value(path, "agents", "author", "persona") as? NSDictionary == ["name": "Ada", "prompt": "Be brief"])
}

@Test func aRolesPersonaOutOfItsLimitsIsRefusedBeforeWriting() throws {
    let path = try temporaryConfig()
    let before = try file(path)
    for refused in [
        persona(name: String(repeating: "x", count: 41), prompt: nil, path: path),
        persona(name: "Ada\nLovelace", prompt: nil, path: path),
        persona(name: "Ada", prompt: "   ", path: path),
        persona(name: nil, prompt: "", path: path),
        persona(name: "", prompt: "ok", path: path),
        persona(name: nil, prompt: String(repeating: "x", count: 4001), path: path),
    ] {
        guard case .refused = refused else { Issue.record("expected a refusal, got \(refused)"); continue }
    }
    #expect(try file(path) == before)
    // forty characters is the limit itself
    #expect(persona(name: String(repeating: "x", count: 40), prompt: nil, path: path) == .saved)
}

@Test func clearingARolesPersonaRemovesItAndKeepsTheRestOfTheFile() throws {
    let path = try temporaryConfig()
    #expect(persona(name: nil, prompt: nil, role: .reviewer, path: path) == .saved)
    #expect(try value(path, "agents", "reviewer", "persona") == nil)
    #expect(try value(path, "agents", "reviewer", "model") as? String == "g")
    #expect(try value(path, "keep", "deep") as? [Int] == [1, 2])
}

@Test func aFirstStepWritesAOneStepListAndASecondWritesTwo() throws {
    let path = try temporaryConfig()
    #expect(failover(step("codex"), path: path) == .saved)
    #expect(try value(path, "failover", "roles", "author") as? NSArray == [["provider": "codex"]])
    #expect(failover(step("codex", " gpt-5 "), step("agy"), path: path) == .saved)
    #expect(try value(path, "failover", "roles", "author") as? NSArray == [["provider": "codex", "model": "gpt-5"], ["provider": "agy"]])
}

@Test func switchingOffRemovesTheListAndLeavesTheOtherKeys() throws {
    let path = try temporaryConfig()
    #expect(failover(nil, role: .reviewer, path: path) == .saved)
    #expect(try value(path, "failover", "roles", "reviewer") == nil)
    #expect(try value(path, "failover", "triggers") as? [String] == ["usage_limit"])
    #expect(failover(step("codex"), path: path) == .saved)
    #expect(failover(nil, path: path) == .saved)
    #expect(try value(path, "failover", "roles") == nil)
}

@Test func theStepsAfterTheFirstTwoAreKeptWhenThoseAreEdited() throws {
    let path = try temporaryConfig()
    #expect(failover(step("agy"), step("codex", "new"), role: .reviewer, path: path) == .saved)
    #expect(try value(path, "failover", "roles", "reviewer") as? NSArray
        == [["provider": "agy"], ["provider": "codex", "model": "new"], ["provider": "claude", "model": "z"]])
}

@Test func everyOtherKeyIsAsItWasAfterAFailoverOrPersonaWrite() throws {
    let path = try temporaryConfig()
    let before = try file(path)
    #expect(failover(step("codex"), path: path) == .saved)
    #expect(persona(name: "Ada", prompt: nil, path: path) == .saved)
    var expected = before as! [String: Any]
    var agents = expected["agents"] as! [String: Any]
    var author = agents["author"] as! [String: Any]
    author["persona"] = ["name": "Ada"]
    agents["author"] = author
    expected["agents"] = agents
    var lists = (expected["failover"] as! [String: Any])
    var roles = lists["roles"] as! [String: Any]
    roles["author"] = [["provider": "codex"]]
    lists["roles"] = roles
    expected["failover"] = lists
    #expect(try file(path) == NSDictionary(dictionary: expected))
}

@Test func aStepNeedsADeclaredProviderAndAFirstBeforeASecond() throws {
    let path = try temporaryConfig()
    let before = try file(path)
    for refused in [failover(step("nope"), path: path), failover(step("codex"), step(""), path: path), failover(nil, step("codex"), path: path)] {
        guard case .refused = refused else { Issue.record("expected a refusal, got \(refused)"); continue }
    }
    #expect(try file(path) == before)
}

@Test func aStepEqualToTheRolesOwnOrToTheOtherStepIsRefusedWithTheReason() throws {
    let path = try temporaryConfig()
    let before = try file(path)
    // the author runs on claude · m
    guard case .refused(let own) = failover(step("codex"), step("claude", "m"), path: path) else { Issue.record("own step accepted"); return }
    #expect(own.hasPrefix("Then") && own.contains("own provider and model"))
    guard case .refused(let twice) = failover(step("codex", "g"), step("codex", "g"), path: path) else { Issue.record("repeated step accepted"); return }
    #expect(twice.hasPrefix("Then") && twice.contains("repeats"))
    #expect(try file(path) == before)
    // the same provider on another model, or on the account's own model, is a different step
    #expect(failover(step("claude"), step("claude", "other"), path: path) == .saved)
}
