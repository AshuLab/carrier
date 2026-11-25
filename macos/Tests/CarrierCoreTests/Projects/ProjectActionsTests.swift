import Foundation
import Testing
@testable import CarrierCore

// The project actions' rules (docs/specs/projects.md, Scope 16; docs/adr/0039): what is a problem, what is written (omitting defaults),
// and a round trip through `projects.json` without reading anything from the repository.

private func temporaryFolder() throws -> String {
    let folder = NSTemporaryDirectory() + "carrier-project-actions-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    return folder
}

@Test func blankNameOrCommandIsAProblemAndValidActionHasNone() {
    let empty = ProjectAction(name: "", command: "", when: .newWorktree)
    #expect(projectActionProblems(empty) == [.name: "Name must not be blank", .command: "Command must not be blank"])

    let spaces = ProjectAction(name: "  \t ", command: "\n ", when: .afterClone)
    #expect(projectActionProblems(spaces) == [.name: "Name must not be blank", .command: "Command must not be blank"])

    let missingCommand = ProjectAction(name: "Install", command: " ", when: .newWorktree)
    #expect(projectActionProblems(missingCommand) == [.command: "Command must not be blank"])

    let missingName = ProjectAction(name: "", command: "pnpm install", when: .afterClone)
    #expect(projectActionProblems(missingName) == [.name: "Name must not be blank"])

    let valid = ProjectAction(name: "Install", command: "pnpm install", when: .newWorktree)
    #expect(projectActionProblems(valid).isEmpty)
}

@Test func encodingOmitsDefaultOnAndOnFailAndRefusesBlankFields() {
    let defaults = ProjectAction(name: "Install", command: "pnpm install", when: .newWorktree, on: true, onFail: .warn)
    let encodedDefault = encodedProjectAction(defaults)
    #expect(encodedDefault?["name"] as? String == "Install")
    #expect(encodedDefault?["command"] as? String == "pnpm install")
    #expect(encodedDefault?["when"] as? String == "newWorktree")
    #expect(encodedDefault?["on"] == nil)
    #expect(encodedDefault?["onFail"] == nil)

    let nonDefaults = ProjectAction(name: "Setup", command: "make setup", when: .afterClone, on: false, onFail: .stop)
    let encodedNonDefault = encodedProjectAction(nonDefaults)
    #expect(encodedNonDefault?["on"] as? Bool == false)
    #expect(encodedNonDefault?["onFail"] as? String == "stop")
    #expect(encodedNonDefault?["when"] as? String == "afterClone")

    #expect(encodedProjectAction(ProjectAction(name: " ", command: "make", when: .newWorktree)) == nil)
    #expect(encodedProjectAction(ProjectAction(name: "Build", command: "", when: .afterClone)) == nil)
}

@Test func mergedDraftsOmitUnsavedBlanksAndPreservePreviouslySavedActionsWhenCleared() {
    let savedAction = ProjectAction(name: "Install", command: "pnpm install", when: .newWorktree)
    let savedDraft = ProjectActionDraft(action: savedAction)
    let newBlankDraft = ProjectActionDraft(action: ProjectAction(name: "", command: "", when: .afterClone))
    let newValidDraft = ProjectActionDraft(action: ProjectAction(name: "Test", command: "pnpm test", when: .afterClone, on: false, onFail: .stop))

    // unsaved blank draft is omitted while valid drafts are kept
    let withNewBlank = mergedProjectActions(drafts: [savedDraft, newBlankDraft, newValidDraft], saved: [savedDraft.id: savedAction])
    #expect(withNewBlank == [savedAction, newValidDraft.action])

    // clearing the name of an already-saved action keeps its last saved version rather than deleting it
    var clearedSaved = savedDraft
    clearedSaved.action.name = "  "
    let whileEditing = mergedProjectActions(drafts: [clearedSaved, newValidDraft], saved: [savedDraft.id: savedAction])
    #expect(whileEditing == [savedAction, newValidDraft.action])
}

@Test func actionsSummaryMatchesSpecWording() {
    #expect(projectActionsSummary(0) == "None")
    #expect(projectActionsSummary(1) == "1 action")
    #expect(projectActionsSummary(2) == "2 actions")
    #expect(projectActionsSummary(5) == "5 actions")
}

@Test func actionsSurviveRoundTripThroughFileAndNeverReadFromRepository() throws {
    let home = try temporaryFolder()
    let repo = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: home)
        try? FileManager.default.removeItem(atPath: repo)
    }

    // place decoy files inside the repository folder: none of them may ever be read as actions
    try FileManager.default.createDirectory(atPath: repo + "/.carrier", withIntermediateDirectories: true)
    try Data(#"{"actions":[{"name":"Evil","command":"rm -rf /","when":"newWorktree"}]}"#.utf8)
        .write(to: URL(fileURLWithPath: repo + "/.carrier/actions.json"))
    try Data(#"{"scripts":{"postinstall":"echo pwned"}}"#.utf8)
        .write(to: URL(fileURLWithPath: repo + "/package.json"))

    let file = ProjectsFile(folder: home)
    try file.add(folder: repo)
    #expect(try file.read().first?.actions.isEmpty == true)

    let saved = [
        ProjectAction(name: "Install", command: "pnpm install", when: .newWorktree, on: true, onFail: .warn),
        ProjectAction(name: "Copy env", command: "cp \"$CARRIER_PROJECT/.env\" .env", when: .newWorktree, on: false, onFail: .stop),
        ProjectAction(name: "Bootstrap", command: "make bootstrap", when: .afterClone, on: true, onFail: .stop),
    ]
    #expect(applyProjectsChange(.setActions(path: repo, actions: saved), home: home).refusal == nil)

    let reloaded = try file.read()
    #expect(reloaded.count == 1)
    #expect(reloaded[0].actions == saved)

    // an invalid action is refused and leaves the file intact
    #expect(applyProjectsChange(.setActions(path: repo, actions: [ProjectAction(name: "", command: "x", when: .newWorktree)]), home: home).refusal != nil)
    #expect(try file.read()[0].actions == saved)
}

@MainActor @Test func modelSavesActionsAndUpdatesRows() async throws {
    let home = try temporaryFolder()
    let repo = try temporaryFolder()
    defer {
        try? FileManager.default.removeItem(atPath: home)
        try? FileManager.default.removeItem(atPath: repo)
    }

    let file = ProjectsFile(folder: home)
    let model = ProjectsModel(host: CloneHost(writing: file.folder), file: file) { _ in nil }
    #expect(await model.add(folder: repo) == .added(repo))
    #expect(model.rows.first?.actions == [])

    let actions = [
        ProjectAction(name: "Install", command: "pnpm i", when: .newWorktree),
        ProjectAction(name: "Setup", command: "make", when: .afterClone, on: false, onFail: .stop),
    ]
    #expect(await model.saveActions(path: repo, actions: actions) == true)
    #expect(model.rows.first?.actions == actions)

    // blank action is not written and keeps previous actions
    #expect(await model.saveActions(path: repo, actions: [ProjectAction(name: " ", command: "make", when: .afterClone)]) == false)
    #expect(model.rows.first?.actions == actions)
}
