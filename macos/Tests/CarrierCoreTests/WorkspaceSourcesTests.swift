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
