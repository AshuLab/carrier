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

@Test func theProjectsFolderIsChatJsonsOrUnderTheCarrierFolder() {
    let home = "/Users/x"
    func folder(_ json: String?) -> String { projectsFolder(chatJSON: json.map { Data($0.utf8) }, carrierFolder: "/Users/x/.carrier", home: home) }
    #expect(folder(nil) == "/Users/x/.carrier/chat/projects")
    #expect(folder("nope") == "/Users/x/.carrier/chat/projects")
    #expect(folder("{\"agents\":{}}") == "/Users/x/.carrier/chat/projects")
    #expect(folder("{\"projectsFolder\":\"~/Projects/carrier\"}") == "/Users/x/Projects/carrier")
    #expect(folder("{\"projectsFolder\":\"/srv/p\"}") == "/srv/p")
    #expect(folder("{\"projectsFolder\":\"\"}") == "/Users/x/.carrier/chat/projects")
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

@Test func changingTheProjectsFolderSetsOnlyThatKeyOfChatJsonAndMakesTheFileWhenItIsNotThere() throws {
    func change(_ json: String?) throws -> [String: Any] {
        let updated = try #require(applyingProjectsFolder("/Volumes/code", to: json.map { Data($0.utf8) }))
        return try #require(try JSONSerialization.jsonObject(with: updated) as? [String: Any])
    }
    let existing = try change(#"{"agents":{"a":{"harness":"claude"}},"projectsFolder":"~/old","logLevel":"debug"}"#)
    #expect(existing["projectsFolder"] as? String == "/Volumes/code" && existing["agents"] != nil && existing["logLevel"] as? String == "debug")
    #expect(try change(nil) as NSDictionary == ["projectsFolder": "/Volumes/code"])
    #expect(applyingProjectsFolder("/x", to: Data("[1]".utf8)) == nil && applyingProjectsFolder("/x", to: Data("nope".utf8)) == nil)
}

@Test func theProjectsFolderMayNotBeTheEngineOrTheChatsStateLogsOrWorktreesOrInsideThem() throws {
    func problem(_ folder: String) -> String? { projectsFolderRefusal(folder, carrierFolder: "/data/carrier") }
    for name in ["engine", "chat/state", "chat/logs", "chat/worktrees"] {
        #expect(problem("/data/carrier/\(name)")?.contains("Carrier's own \(name) folder") == true)
        #expect(problem("/data/carrier/\(name)/a/b") != nil)
    }
    for ok in ["/data/carrier", "/data/carrier/chat", "/data/carrier/chat/projects", "/data/carrier/engines", "/data/other/engine", "/Users/x/Projects"] { #expect(problem(ok) == nil, "\(ok)") }
    #expect(problem("projects") == "The projects folder must be an absolute path")
    // a symlink into the engine's folder is refused too
    let base = NSTemporaryDirectory() + "link-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: base) }
    try FileManager.default.createDirectory(atPath: base + "/carrier/engine/worktrees", withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: base + "/alias", withDestinationPath: base + "/carrier/engine/worktrees")
    #expect(projectsFolderRefusal(base + "/alias", carrierFolder: base + "/carrier") != nil)
}

@Test func withGhMissingOrSignedOutOnlyTheSourcesThatNeedItAreOffAndSayWhy() {
    let needGh: [WorkspaceSource] = [.githubURL, .githubRepos]
    let noGh: [WorkspaceSource] = [.localFolder, .newProject]
    for gh in [ToolState.missing, .signedOut] {
        for source in needGh { #expect(workspaceSourceReason(source, gh: gh) != nil, "\(source) \(gh)") }
        for source in noGh { #expect(workspaceSourceReason(source, gh: gh) == nil, "\(source) \(gh)") }
    }
    #expect(workspaceSourceReason(.githubURL, gh: .missing)?.contains("not installed") == true)
    #expect(workspaceSourceReason(.githubRepos, gh: .signedOut)?.contains("signed out") == true)
    // ready, unknown and a host that did not report the health leave every source on
    for gh in [ToolState.ready, .unknown, nil] {
        for source in needGh + noGh { #expect(workspaceSourceReason(source, gh: gh) == nil, "\(source) \(String(describing: gh))") }
    }
}
