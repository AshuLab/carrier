import Foundation
import Testing
@testable import CarrierCore

// What the workspace popover needs without a model: the URL step's text, the projects folder and what is in it.

@Test func theUrlStepAcceptsOneRepositoryInTheFormsTheSpecListsAndNothingElse() {
    for text in [
        "AshuLab/carrier", "  AshuLab/carrier  ", "AshuLab/carrier.git", "https://github.com/AshuLab/carrier",
        "https://github.com/AshuLab/carrier.git", "https://github.com/AshuLab/carrier/", "github.com/AshuLab/carrier",
    ] {
        #expect(repoReference(text) == "AshuLab/carrier", "\(text)")
    }
    for text in [
        "", "AshuLab", "a/b/c", "../x", "AshuLab/..", "https://github.com/AshuLab/carrier/tree/main", "https://gitlab.com/a/b", "git@github.com:a/b.git",
        "./x", "AshuLab/.", "AshuLab/", "/carrier", "AshuLab carrier/x", "Ashu Lab/carrier", "http://github.com/a/b", "https://github.com/a",
    ] {
        #expect(repoReference(text) == nil, "\(text)")
    }
}

@Test func theProjectsFolderIsTheConfigsOrUnderTheRoot() {
    let home = "/Users/x"
    func folder(_ json: String?) -> String { projectsFolder(configJSON: json.map { Data($0.utf8) }, home: home) }
    #expect(folder(nil) == "/Users/x/.solve/chat/projects")
    #expect(folder("{\"root\":\"/data/solve\"}") == "/data/solve/chat/projects")
    #expect(folder("{\"root\":\"~/solve\",\"chat\":{\"agents\":{}}}") == "/Users/x/solve/chat/projects")
    #expect(folder("{\"chat\":{\"projectsFolder\":\"~/Projects/carrier\"}}") == "/Users/x/Projects/carrier")
    #expect(folder("{\"chat\":{\"projectsFolder\":\"/srv/p\"},\"root\":\"/data\"}") == "/srv/p")
    #expect(folder("{\"chat\":{\"projectsFolder\":\"\"}}") == "/Users/x/.solve/chat/projects")
}

@Test func theProjectsFoldersAreTheOwnerAndRepoFoldersOnDiskByName() throws {
    let root = NSTemporaryDirectory() + "projects-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: root) }
    for path in ["vemec/blog", "AshuLab/carrier", "local/my-idea", ".hidden/x", "AshuLab/.cache"] {
        try FileManager.default.createDirectory(atPath: root + "/" + path, withIntermediateDirectories: true)
    }
    FileManager.default.createFile(atPath: root + "/AshuLab/notes.txt", contents: Data())
    #expect(projectFolders(in: root) == [
        ProjectFolder(name: "AshuLab/carrier", path: root + "/AshuLab/carrier"),
        ProjectFolder(name: "local/my-idea", path: root + "/local/my-idea"),
        ProjectFolder(name: "vemec/blog", path: root + "/vemec/blog"),
    ])
    #expect(projectFolders(in: root + "/nowhere").isEmpty)
}

@Test func aProjectNameIsOnePlainFolderNameOfAtMostAHundredCharacters() {
    for name in ["a", "my-app", "my_app.2", "A1", "_x", "a.", String(repeating: "a", count: 100)] { #expect(projectNameProblem(name) == nil, "\(name)") }
    for name in ["", ".", "..", ".hidden", "-x", "a/b", "../x", "a b", "a\n", "é", "ñandú", String(repeating: "a", count: 101)] { #expect(projectNameProblem(name) != nil, "\(name)") }
}

@Test func changingTheProjectsFolderSetsOnlyThatKeyKeepingTheChatBlockAndTheKeysTheAppDoesNotKnow() throws {
    func change(_ json: String) throws -> [String: Any] {
        let updated = try #require(applyingProjectsFolder("/Volumes/code", to: Data(json.utf8)))
        return try #require(try JSONSerialization.jsonObject(with: updated) as? [String: Any])
    }
    let withChat = try change(#"{"root":"~/work","future":{"x":[1,2]},"chat":{"agents":{"a":{"harness":"claude"}},"projectsFolder":"~/old","extra":true},"repos":[{"name":"a/b"}]}"#)
    let chat = try #require(withChat["chat"] as? [String: Any])
    #expect(chat["projectsFolder"] as? String == "/Volumes/code" && chat["extra"] as? Bool == true && chat["agents"] != nil)
    #expect(withChat["root"] as? String == "~/work" && withChat["future"] != nil && (withChat["repos"] as? [[String: Any]])?.count == 1)
    let noChat = try change(#"{"repos":[{"name":"a/b"}],"unknown":1}"#)
    #expect((noChat["chat"] as? [String: Any])?["projectsFolder"] as? String == "/Volumes/code" && noChat["unknown"] as? Int == 1)
    #expect(applyingProjectsFolder("/x", to: Data("[1]".utf8)) == nil && applyingProjectsFolder("/x", to: Data("nope".utf8)) == nil)
}

@Test func theProjectsFolderMayNotBeTheEnginesReposWorktreesOrOrchestratorOrInsideThem() throws {
    let config = Data(#"{"root":"/data/solve"}"#.utf8)
    func problem(_ folder: String) -> String? { projectsFolderRefusal(folder, configJSON: config, home: "/Users/x") }
    for name in ["repos", "worktrees", "orchestrator"] {
        #expect(problem("/data/solve/\(name)")?.contains("Carrier's own \(name) folder") == true)
        #expect(problem("/data/solve/\(name)/a/b") != nil)
    }
    for ok in ["/data/solve", "/data/solve/chat/projects", "/data/solve/reposx", "/data/other/repos", "/Users/x/Projects"] { #expect(problem(ok) == nil, "\(ok)") }
    #expect(problem("projects") == "The projects folder must be an absolute path")
    #expect(projectsFolderRefusal("/Users/x/.solve/repos", configJSON: nil, home: "/Users/x") != nil)
    // a symlink into an engine folder is refused too
    let base = NSTemporaryDirectory() + "link-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: base) }
    try FileManager.default.createDirectory(atPath: base + "/root/worktrees", withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: base + "/alias", withDestinationPath: base + "/root/worktrees")
    #expect(projectsFolderRefusal(base + "/alias", configJSON: Data(#"{"root":"\#(base)/root"}"#.utf8), home: "/Users/x") != nil)
}
