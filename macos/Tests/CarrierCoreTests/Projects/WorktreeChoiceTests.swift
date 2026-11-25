import Foundation
import Testing
@testable import CarrierCore

// The worktree half of the new-session sentence as pure values over the `workspace` reply: golden replies of the fixture host
// (`Tests/Fixtures/chat-workspace.json`, `chat-fetch.json`, `chat-names.json`), decoded as the app decodes the host's answer.

private let fixtures = testPaths().fixtures

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
    #expect(info.branches.map(\.name) == ["main", "feat/retry-sync", "wip/spike", "origin/main", "origin/feat/retry-sync"])
    #expect(info.branches.map(\.remote) == [false, false, false, true, true] && info.fetchedAt == 1_792_000_000_000)
    #expect(info.repo == .init(owner: "AshuLab", name: "carrier") && info.hasOrigin)
    let plain = try workspace(notes)
    #expect(plain.git == false && plain.branches.isEmpty && plain.dirty == 0 && plain.offersWorktree == false)
}

@Test func theSentenceSaysTheBranchOfTheBaseFolder() throws {
    #expect(workSentence(folder: carrier, workspace: try workspace(carrier), bundle: english.bundle, locale: english.locale) == "Work in carrier on the base folder (main)")
    #expect(workSentence(folder: web, workspace: try workspace(web), bundle: english.bundle, locale: english.locale) == "Work in web on the base folder (detached HEAD)")
}

@Test func aFolderThatIsNotARepositoryOrIsBareSaysWhyThereIsNoWorktree() throws {
    #expect(workSentence(folder: notes, workspace: try workspace(notes), bundle: english.bundle, locale: english.locale) == "Work in notes in the folder (not a git repository: no worktree)")
    #expect(workSentence(folder: bare, workspace: try workspace(bare), bundle: english.bundle, locale: english.locale) == "Work in bare.git in the folder (bare repository: no worktree)")
    #expect(try workspace(notes).offersWorktree == false)
    #expect(try workspace(bare).offersWorktree == false)
    #expect(try workspace(carrier).offersWorktree)
}

@Test func theSentenceInAWorktreeNamesTheBranchItIsCutFrom() throws {
    let info = try workspace(carrier)
    #expect(workSentence(folder: carrier, workspace: info, worktree: ("brave-marine-aiur", "main"), bundle: english.bundle, locale: english.locale) == "Work in carrier in a new worktree carrier/brave-marine-aiur from main")
    #expect(workSentence(folder: carrier, workspace: info, worktree: ("brave-marine-aiur", nil), bundle: english.bundle, locale: english.locale) == "Work in carrier in a new worktree carrier/brave-marine-aiur from …")
    // a folder that offers no worktree never says one
    #expect(workSentence(folder: notes, workspace: try workspace(notes), worktree: ("x", "main"), bundle: english.bundle, locale: english.locale) == "Work in notes in the folder (not a git repository: no worktree)")
}

@Test func uncommittedChangesAreCountedAndAWorktreeIsOfferedAsAWayOut() throws {
    #expect(uncommittedWarning(try workspace(carrier), bundle: english.bundle, locale: english.locale) == "3 uncommitted files in the folder. A worktree keeps them out of the agent's way.")
    #expect(uncommittedWarning(try workspace("/Users/dev/work/web"), bundle: english.bundle, locale: english.locale) == "1 uncommitted file in the folder. A worktree keeps them out of the agent's way.")
    #expect(uncommittedWarning(try workspace(web), bundle: english.bundle, locale: english.locale) == nil)
    #expect(uncommittedWarning(try workspace(notes), bundle: english.bundle, locale: english.locale) == nil)
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
    let picker = branchPicker(try workspace(carrier), now: Date(timeIntervalSince1970: 1_792_000_300), bundle: english.bundle, locale: english.locale)
    #expect(picker.local == [
        BranchRow(name: "main", checkedOut: true, isDefault: true, behind: 2), BranchRow(name: "feat/retry-sync", checkedOut: false, isDefault: false, ahead: 1),
        BranchRow(name: "wip/spike", checkedOut: false, isDefault: false, localOnly: true),
    ])
    #expect(picker.remote == [BranchRow(name: "origin/main", checkedOut: false, isDefault: true), BranchRow(name: "origin/feat/retry-sync", checkedOut: false, isDefault: false)])
    #expect(picker.fetched == "Fetched 5 minutes ago")
}

@Test func theSearchNarrowsBothSectionsIgnoringCase() throws {
    let picker = branchPicker(try workspace(carrier), query: " RETRY ", bundle: english.bundle, locale: english.locale)
    #expect(picker.local.map(\.name) == ["feat/retry-sync"] && picker.remote.map(\.name) == ["origin/feat/retry-sync"])
    #expect(branchPicker(try workspace(carrier), query: "zzz", bundle: english.bundle, locale: english.locale).local.isEmpty)
    // a detached HEAD checks nothing out
    #expect(branchPicker(try workspace(web), bundle: english.bundle, locale: english.locale).local.map(\.checkedOut) == [false])
}

@Test func theFetchLineSaysHowLongAgoOrThatItNeverHappened() {
    let now = Date(timeIntervalSince1970: 1_792_100_000)
    func line(_ago seconds: Int) -> String { fetchedLine((1_792_100_000 - seconds) * 1000, now: now, bundle: english.bundle, locale: english.locale) }
    #expect(line(_ago: 10) == "Fetched just now" && line(_ago: 60) == "Fetched 1 minute ago" && line(_ago: 7200) == "Fetched 2 hours ago")
    #expect(line(_ago: 86_400) == "Fetched 1 day ago" && line(_ago: 86_400 * 9) == "Fetched 9 days ago")
    #expect(fetchedLine(nil, now: now, bundle: english.bundle, locale: english.locale) == "Never fetched")
    // a clock a little behind the host's is still "just now"
    #expect(fetchedLine(1_792_100_005_000, now: now, bundle: english.bundle, locale: english.locale) == "Fetched just now")
}

@Test func theGoldenFetchHasMoreBranchesAndALaterTime() throws {
    let before = try workspace(carrier), after = try workspace(carrier, in: "chat-fetch.json")
    #expect(after.branches.count == before.branches.count + 1 && (after.fetchedAt ?? 0) > (before.fetchedAt ?? 0))
}

@Test func aNameIsFreeOnlyWhenValidAndFreeAndOtherwiseCarriesTheHostsReason() throws {
    #expect(stateOfName(NameCheck(valid: true, free: true), bundle: english.bundle, locale: english.locale) == .free)
    let checks = try #require(golden("chat-names.json")["checks"] as? [String: Any])
    func state(_ name: String) throws -> NameState {
        stateOfName(try JSONDecoder().decode(NameCheck.self, from: JSONSerialization.data(withJSONObject: try #require(checks[name]))), bundle: english.bundle, locale: english.locale)
    }
    #expect(try state("fix-login") == .problem("A branch called carrier/fix-login already exists"))
    #expect(try state("Big_Name") == .problem("The name must start with a lowercase letter or a digit"))
    #expect(stateOfName(NameCheck(valid: false, free: false), bundle: english.bundle, locale: english.locale) == .problem("That name cannot be used"))
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
    let picker = branchPicker(sides, bundle: english.bundle, locale: english.locale)
    #expect(picker.rows(.remote).map(\.name) == ["origin/main", "origin/remote-only", "origin/feat/retry-sync"])
    #expect(picker.rows(.local).map(\.name) == ["main", "local-only", "feat/retry-sync"])
    let names = picker.rows(.remote).map(\.name) + picker.rows(.local).map(\.name)
    #expect(Set(names).count == names.count)
}

@Test func aLocalBranchWithNoCounterpartOnOriginIsMarkedAndNothingElseIs() {
    let picker = branchPicker(sides, bundle: english.bundle, locale: english.locale)
    #expect(picker.rows(.local).map(\.localOnly) == [false, true, false])
    #expect(picker.rows(.remote).allSatisfy { $0.localOnly == false })
    // a search keeps the mark: it depends on the whole list, not on what matched
    #expect(branchPicker(sides, query: "local", bundle: english.bundle, locale: english.locale).rows(.local).map(\.localOnly) == [true])
}

@Test func theSearchHasNoMatchInOneTabAndSomeInTheOther() {
    let picker = branchPicker(sides, query: "remote-only", bundle: english.bundle, locale: english.locale)
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
    let picker = branchPicker(sides, bundle: english.bundle, locale: english.locale)
    #expect(picker.rows(.remote).map { point.chooses($0, on: .remote) } == [true, false, false])
    #expect(picker.rows(.local).map { point.chooses($0, on: .local) } == [false, false, false])
    #expect(StartPoint(branch: "local-only", side: .local).chooses(picker.rows(.local)[1], on: .local))
    #expect(StartPoint(branch: "main", side: nil).chooses(picker.rows(.local)[0], on: .local) == false)
}

// Behind and not pushed: the counts of a local branch that has a counterpart on origin, and what the picker says of them.

@Test func aLocalBranchCarriesTheHostsCountsOnlyWhenItHasACounterpartOnOrigin() throws {
    let branches = try workspace(carrier).branches
    func branch(_ name: String) -> WorkspaceInfo.Branch? { branches.first { $0.name == name } }
    #expect(branch("main")?.behind == 2 && branch("main")?.ahead == 0)
    #expect(branch("feat/retry-sync")?.ahead == 1 && branch("feat/retry-sync")?.behind == 0)
    #expect(branch("wip/spike")?.ahead == nil && branch("wip/spike")?.behind == nil, "no counterpart, no counts")
    #expect(branch("origin/main")?.ahead == nil)
    // a host that does not count says nothing and the app reads the reply all the same
    let old = #"{"folder":"/w","git":true,"bare":false,"linkedWorktree":false,"repo":null,"branch":"main","defaultBranch":"main","dirty":0,"branches":[{"name":"main","remote":false}],"fetchedAt":null}"#
    let info = try JSONDecoder().decode(WorkspaceInfo.self, from: Data(old.utf8))
    #expect(info.branches.first?.behind == nil && branchPicker(info, bundle: english.bundle, locale: english.locale).local.first?.behindText(bundle: english.bundle, locale: english.locale) == nil)
}

@Test func theBadgesSayHowFarBehindAndHowManyAreNotPushedOnlyWhenNotZero() throws {
    let rows = branchPicker(try workspace(carrier), bundle: english.bundle, locale: english.locale).local
    #expect(rows[0].behindText(bundle: english.bundle, locale: english.locale) == "2 behind origin" && rows[0].notPushedText(bundle: english.bundle, locale: english.locale) == nil)
    #expect(rows[1].notPushedText(bundle: english.bundle, locale: english.locale) == "1 not pushed" && rows[1].behindText(bundle: english.bundle, locale: english.locale) == nil)
    #expect(rows[2].behindText(bundle: english.bundle, locale: english.locale) == nil && rows[2].notPushedText(bundle: english.bundle, locale: english.locale) == nil && rows[2].localOnly, "one on neither shows only that it is not on origin")
    #expect(branchPicker(try workspace(web), bundle: english.bundle, locale: english.locale).local.map { [$0.behindText(bundle: english.bundle, locale: english.locale), $0.notPushedText(bundle: english.bundle, locale: english.locale)] } == [[nil, nil]], "a branch level with origin shows nothing")
    #expect(branchPicker(try workspace(carrier, in: "chat-fetch.json"), bundle: english.bundle, locale: english.locale).local.first?.behindText(bundle: english.bundle, locale: english.locale) == "12 behind origin")
}

@Test func theFooterSaysItCouldNotReachOriginOnlyWhenTheFetchOnChoosingFailed() throws {
    let now = Date(timeIntervalSince1970: 1_792_000_300)
    #expect(branchPicker(try workspace(carrier), now: now, bundle: english.bundle, locale: english.locale).unreachable == nil)
    let picker = branchPicker(try workspace(carrier), now: now, unreachable: true, bundle: english.bundle, locale: english.locale)
    #expect(picker.unreachable == "Could not reach origin" && picker.fetched == "Fetched 5 minutes ago")
    #expect(branchPicker(try workspace(web), unreachable: true, bundle: english.bundle, locale: english.locale).fetched == "Never fetched")
}

@Test func theSummaryWarnsOfALocalBranchBehindOnlyWithLocalAndOfCommitsNotPushedOnlyWithRemote() throws {
    let info = try workspace(carrier)
    #expect(startWarning(StartPoint(branch: "main", side: .local), in: info, bundle: english.bundle, locale: english.locale) == "main is 2 commits behind origin/main, so the worktree starts without them.")
    #expect(startWarning(StartPoint(branch: "main", side: .remote), in: info, bundle: english.bundle, locale: english.locale) == nil, "Remote starts from the fresh branch: being behind is no problem")
    #expect(startWarning(StartPoint(branch: "feat/retry-sync", side: .remote), in: info, bundle: english.bundle, locale: english.locale) == "feat/retry-sync has 1 commit not pushed to origin/feat/retry-sync, so the worktree will not have it.")
    #expect(startWarning(StartPoint(branch: "feat/retry-sync", side: .local), in: info, bundle: english.bundle, locale: english.locale) == nil, "Local has the commits")
    #expect(startWarning(StartPoint(branch: "wip/spike", side: .local), in: info, bundle: english.bundle, locale: english.locale) == nil, "on neither: nothing to compare")
    #expect(startWarning(StartPoint(branch: "main", side: nil), in: info, bundle: english.bundle, locale: english.locale) == nil && startWarning(nil, in: info, bundle: english.bundle, locale: english.locale) == nil && startWarning(StartPoint(branch: "main", side: .local), in: nil, bundle: english.bundle, locale: english.locale) == nil)
    #expect(startWarning(StartPoint(branch: "main", side: .local), in: WorkspaceInfo(folder: "/w", branches: [.init(name: "main", remote: false, ahead: 0, behind: 1)]), bundle: english.bundle, locale: english.locale)?.hasPrefix("main is 1 commit behind") == true)
}

@Test func onlyAFolderWithAnOriginIsFetchedOnChoosing() throws {
    #expect(try workspace(carrier).hasOrigin && workspace(web).hasOrigin)
    #expect(try workspace(notes).hasOrigin == false && workspace(bare).hasOrigin == false)
    // a remote that is not GitHub's still counts once its branches are on disk; a repository with none has nothing to fetch yet
    #expect(WorkspaceInfo(folder: "/w", branches: [.init(name: "origin/main", remote: true)]).hasOrigin)
    #expect(WorkspaceInfo(folder: "/w", branches: [.init(name: "main", remote: false)]).hasOrigin == false)
}
