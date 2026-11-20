import Foundation
import Testing
@testable import CarrierCore

// The worktree half of the new-session sentence as pure values over the `workspace` reply: golden replies of the fixture host
// (`Tests/Fixtures/chat-workspace.json`, `chat-fetch.json`, `chat-names.json`), decoded as the app decodes the host's answer.

private let fixtures = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fixtures")

private func golden(_ file: String) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(file))) as? [String: Any])
}

private func workspace(_ folder: String, in file: String = "chat-workspace.json") throws -> WorkspaceInfo {
    let reply = try #require(golden(file)[folder])
    return try JSONDecoder().decode(WorkspaceInfo.self, from: JSONSerialization.data(withJSONObject: reply))
}

private let carrier = "/Users/dev/carrier"  // git, on main, 3 uncommitted files, fetched
private let web = "/Users/dev/web"  // git, clean, detached HEAD, never fetched
private let notes = "/Users/dev/notes"  // not a git repository
private let bare = "/Users/dev/bare.git"

@Test func theGoldenWorkspaceRepliesDecodeAsTheHostSendsThem() throws {
    let info = try workspace(carrier)
    #expect(info.git && info.bare == false && info.branch == "main" && info.defaultBranch == "main" && info.dirty == 3)
    #expect(info.branches.map(\.name) == ["main", "feat/retry-sync", "origin/main", "origin/feat/retry-sync"])
    #expect(info.branches.map(\.remote) == [false, false, true, true] && info.fetchedAt == 1_792_000_000_000)
    let plain = try workspace(notes)
    #expect(plain.git == false && plain.branches.isEmpty && plain.dirty == 0 && plain.offersWorktree == false)
}

@Test func theSentenceSaysTheBranchOfTheBaseFolder() throws {
    #expect(workSentence(folder: carrier, workspace: try workspace(carrier)) == "Work in carrier on the base folder (main)")
    #expect(workSentence(folder: web, workspace: try workspace(web)) == "Work in web on the base folder (detached HEAD)")
}

@Test func aFolderThatIsNotARepositoryOrIsBareSaysWhyThereIsNoWorktree() throws {
    #expect(workSentence(folder: notes, workspace: try workspace(notes)) == "Work in notes in the folder (not a git repository: no worktree)")
    #expect(workSentence(folder: bare, workspace: try workspace(bare)) == "Work in bare.git in the folder (bare repository: no worktree)")
    #expect(try workspace(notes).offersWorktree == false)
    #expect(try workspace(bare).offersWorktree == false)
    #expect(try workspace(carrier).offersWorktree)
}

@Test func theSentenceInAWorktreeNamesTheBranchItIsCutFrom() throws {
    let info = try workspace(carrier)
    #expect(workSentence(folder: carrier, workspace: info, worktree: ("brave-marine-aiur", "main")) == "Work in carrier in a new worktree carrier/brave-marine-aiur from main")
    #expect(workSentence(folder: carrier, workspace: info, worktree: ("brave-marine-aiur", nil)) == "Work in carrier in a new worktree carrier/brave-marine-aiur from …")
    // a folder that offers no worktree never says one
    #expect(workSentence(folder: notes, workspace: try workspace(notes), worktree: ("x", "main")) == "Work in notes in the folder (not a git repository: no worktree)")
}

@Test func uncommittedChangesAreCountedAndAWorktreeIsOfferedAsAWayOut() throws {
    #expect(uncommittedWarning(try workspace(carrier)) == "3 uncommitted files in the folder. A worktree keeps them out of the agent's way.")
    #expect(uncommittedWarning(try workspace("/Users/dev/work/web")) == "1 uncommitted file in the folder. A worktree keeps them out of the agent's way.")
    #expect(uncommittedWarning(try workspace(web)) == nil)
    #expect(uncommittedWarning(try workspace(notes)) == nil)
}

@Test func theStartingBranchIsTheCheckedOutOneThenTheDefaultOneThenNilToAsk() throws {
    #expect(defaultStartBranch(try workspace(carrier)) == "main")
    #expect(defaultStartBranch(try workspace("/Users/dev/work/web")) == "develop")
    // detached: the repository's default branch, as the host lists it
    #expect(defaultStartBranch(try workspace(web)) == "main")
    let remoteOnly = WorkspaceInfo(folder: "/w", defaultBranch: "trunk", branches: [.init(name: "origin/trunk", remote: true)])
    #expect(defaultStartBranch(remoteOnly) == "origin/trunk")
    // detached with no default branch, or one the host did not list: the person is asked
    #expect(defaultStartBranch(WorkspaceInfo(folder: "/w", branches: [.init(name: "x", remote: false)])) == nil)
    #expect(defaultStartBranch(WorkspaceInfo(folder: "/w", defaultBranch: "main", branches: [.init(name: "x", remote: false)])) == nil)
}

@Test func thePickerHasTwoSectionsAndMarksTheCheckedOutBranchAndTagsTheDefault() throws {
    let picker = branchPicker(try workspace(carrier), now: Date(timeIntervalSince1970: 1_792_000_300))
    #expect(picker.local == [BranchRow(name: "main", checkedOut: true, isDefault: true), BranchRow(name: "feat/retry-sync", checkedOut: false, isDefault: false)])
    #expect(picker.remote == [BranchRow(name: "origin/main", checkedOut: false, isDefault: true), BranchRow(name: "origin/feat/retry-sync", checkedOut: false, isDefault: false)])
    #expect(picker.fetched == "Fetched 5 minutes ago")
}

@Test func theSearchNarrowsBothSectionsIgnoringCase() throws {
    let picker = branchPicker(try workspace(carrier), query: " RETRY ")
    #expect(picker.local.map(\.name) == ["feat/retry-sync"] && picker.remote.map(\.name) == ["origin/feat/retry-sync"])
    #expect(branchPicker(try workspace(carrier), query: "zzz").local.isEmpty)
    // a detached HEAD checks nothing out
    #expect(branchPicker(try workspace(web)).local.map(\.checkedOut) == [false])
}

@Test func theFetchLineSaysHowLongAgoOrThatItNeverHappened() {
    let now = Date(timeIntervalSince1970: 1_792_100_000)
    func line(_ago seconds: Int) -> String { fetchedLine((1_792_100_000 - seconds) * 1000, now: now) }
    #expect(line(_ago: 10) == "Fetched just now" && line(_ago: 60) == "Fetched 1 minute ago" && line(_ago: 7200) == "Fetched 2 hours ago")
    #expect(line(_ago: 86_400) == "Fetched 1 day ago" && line(_ago: 86_400 * 9) == "Fetched 9 days ago")
    #expect(fetchedLine(nil, now: now) == "Never fetched")
    // a clock a little behind the host's is still "just now"
    #expect(fetchedLine(1_792_100_005_000, now: now) == "Fetched just now")
}

@Test func theGoldenFetchHasMoreBranchesAndALaterTime() throws {
    let before = try workspace(carrier), after = try workspace(carrier, in: "chat-fetch.json")
    #expect(after.branches.count == before.branches.count + 1 && (after.fetchedAt ?? 0) > (before.fetchedAt ?? 0))
}

@Test func aNameIsFreeOnlyWhenValidAndFreeAndOtherwiseCarriesTheHostsReason() throws {
    #expect(stateOfName(NameCheck(valid: true, free: true)) == .free)
    let checks = try #require(golden("chat-names.json")["checks"] as? [String: Any])
    func state(_ name: String) throws -> NameState {
        stateOfName(try JSONDecoder().decode(NameCheck.self, from: JSONSerialization.data(withJSONObject: try #require(checks[name]))))
    }
    #expect(try state("fix-login") == .problem("A branch called carrier/fix-login already exists"))
    #expect(try state("Big_Name") == .problem("The name must start with a lowercase letter or a digit"))
    #expect(stateOfName(NameCheck(valid: false, free: false)) == .problem("That name cannot be used"))
}

// The start of a worktree: the branch by its bare name and the side of it (Remote is `origin/<name>`, Local is `<name>`).

/// main on both sides, `local-only` never pushed, `remote-only` not checked out here, and `feat/retry-sync` on both.
private let sides = WorkspaceInfo(
    folder: "/w", branch: "main", defaultBranch: "main",
    branches: [
        .init(name: "main", remote: false), .init(name: "local-only", remote: false), .init(name: "feat/retry-sync", remote: false),
        .init(name: "origin/main", remote: true), .init(name: "origin/remote-only", remote: true), .init(name: "origin/feat/retry-sync", remote: true),
    ]
)

@Test func eachTabListsItsOwnSideSoABranchIsNeverOfferedTwice() {
    let picker = branchPicker(sides)
    #expect(picker.rows(.remote).map(\.name) == ["origin/main", "origin/remote-only", "origin/feat/retry-sync"])
    #expect(picker.rows(.local).map(\.name) == ["main", "local-only", "feat/retry-sync"])
    let names = picker.rows(.remote).map(\.name) + picker.rows(.local).map(\.name)
    #expect(Set(names).count == names.count)
}

@Test func aLocalBranchWithNoCounterpartOnOriginIsMarkedAndNothingElseIs() {
    let picker = branchPicker(sides)
    #expect(picker.rows(.local).map(\.localOnly) == [false, true, false])
    #expect(picker.rows(.remote).allSatisfy { $0.localOnly == false })
    // a search keeps the mark: it depends on the whole list, not on what matched
    #expect(branchPicker(sides, query: "local").rows(.local).map(\.localOnly) == [true])
}

@Test func theSearchHasNoMatchInOneTabAndSomeInTheOther() {
    let picker = branchPicker(sides, query: "remote-only")
    #expect(picker.rows(.local).isEmpty && picker.rows(.remote).map(\.name) == ["origin/remote-only"])
}

@Test func theSettingDecidesTheSideOfABranchOnBothSidesAndTheTabLeftOnWinsOverIt() {
    #expect(startPoint(picked: nil, in: sides, choice: nil, setting: .remote) == StartPoint(branch: "main", side: .remote))
    #expect(startPoint(picked: nil, in: sides, choice: nil, setting: .local) == StartPoint(branch: "main", side: .local))
    #expect(startPoint(picked: nil, in: sides, choice: .local, setting: .remote) == StartPoint(branch: "main", side: .local))
    #expect(startPoint(picked: "feat/retry-sync", in: sides, choice: .remote, setting: .local)?.ref == "origin/feat/retry-sync")
}

@Test func aBranchOnOneSideOnlyIsCutFromThatSideWhateverTheSettingAndTheTabSay() {
    #expect(startPoint(picked: "local-only", in: sides, choice: .remote, setting: .remote) == StartPoint(branch: "local-only", side: .local))
    #expect(startPoint(picked: "remote-only", in: sides, choice: .local, setting: .local) == StartPoint(branch: "remote-only", side: .remote))
    #expect(StartPoint(branch: "remote-only", side: .remote).ref == "origin/remote-only" && StartPoint(branch: "local-only", side: .local).ref == "local-only")
}

@Test func aBranchNamedAsOriginSlashNameIsItsRemoteSideUntilATabIsChosen() {
    #expect(startPoint(picked: "origin/main", in: sides, choice: nil, setting: .local) == StartPoint(branch: "main", side: .remote))
    #expect(startPoint(picked: "origin/main", in: sides, choice: .local, setting: .local) == StartPoint(branch: "main", side: .local))
}

@Test func aRepositoryToCloneHasNoSideAndTheBranchIsItsOwnRef() {
    let github = WorkspaceInfo(folder: "/p", branch: "main", defaultBranch: "main", branches: [.init(name: "main", remote: false), .init(name: "feat/x", remote: false)])
    #expect(startPoint(picked: "feat/x", in: github, choice: .remote, setting: .remote, cloned: true) == StartPoint(branch: "feat/x", side: nil))
    #expect(StartPoint(branch: "feat/x", side: nil).ref == "feat/x")
}

@Test func theChosenRowIsTheOneOfTheSideTheWorktreeIsCutFromAndOnlyInThatTab() {
    let point = StartPoint(branch: "main", side: .remote)
    let picker = branchPicker(sides)
    #expect(picker.rows(.remote).map { point.chooses($0, on: .remote) } == [true, false, false])
    #expect(picker.rows(.local).map { point.chooses($0, on: .local) } == [false, false, false])
    #expect(StartPoint(branch: "local-only", side: .local).chooses(picker.rows(.local)[1], on: .local))
    #expect(StartPoint(branch: "main", side: nil).chooses(picker.rows(.local)[0], on: .local) == false)
}
