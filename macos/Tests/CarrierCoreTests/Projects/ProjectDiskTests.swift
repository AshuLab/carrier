import Foundation
import Testing
@testable import CarrierCore

// What a project takes on disk (docs/specs/projects.md, Scope 13): the words of a size, the Disk column and its sort, the bar and the model that asks the host again.

private let format = TimeFormat(style: .relative, hours: .h24, timeZone: TimeZone(identifier: "UTC")!)
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func aSizeIsDecimalWithItsUnitAndAFolderUnderAMegabyteIsInKilobytes() {
    #expect(formatDiskSize(6_420_000_000) == "6.4 GB")
    #expect(formatDiskSize(1_830_000_000) == "1.8 GB")
    #expect(formatDiskSize(75_000_000) == "75 MB")
    #expect(formatDiskSize(310_000) == "310 KB")
    #expect(formatDiskSize(0) == "0 KB")
}

@Test func theDiskColumnTakesTheHostsFigureByFolderAndAProjectNeverMeasuredOrNotFoundHasNone() {
    let rows = [
        ProjectRow(path: "/p/app", name: "app", repo: nil),
        ProjectRow(path: "/p/new", name: "new", repo: nil),
        ProjectRow(path: "/p/gone", name: "gone", repo: nil, status: .notFound),
        ProjectRow(path: "~/tilde", name: "tilde", repo: nil),
    ]
    let figures = [
        "/p/app": ProjectDiskFigure(folder: "/p/app", bytes: 5_000),
        "/p/gone": ProjectDiskFigure(folder: "/p/gone", bytes: 9_000),
        (("~/tilde") as NSString).expandingTildeInPath: ProjectDiskFigure(folder: "tilde", bytes: 7_000),
    ]
    #expect(projectsWithDisk(rows, figures: figures).map(\.diskBytes) == [5_000, nil, nil, 7_000])
}

@Test func theListSortsByDiskBiggestFirstPinnedFirstAndNeverMeasuredLastEitherWay() {
    func row(_ name: String, _ bytes: Int?, pinned: Bool = false) -> ProjectRow {
        var row = ProjectRow(path: "/p/\(name)", name: name, repo: nil, pinned: pinned)
        row.diskBytes = bytes
        return row
    }
    let table = [row("beta", 50), row("alpha", nil), row("gamma", 900), row("delta", 10, pinned: true), row("eps", nil, pinned: true), row("zeta", 50)]
    func names(_ order: ProjectOrder) -> [String] { projectList(table, order: order).flatMap(\.rows).map(\.name) }
    // a tie on size falls back to the name
    #expect(names(ProjectOrder(key: .disk, ascending: false)) == ["delta", "eps", "gamma", "beta", "zeta", "alpha"])
    #expect(names(ProjectOrder(key: .disk, ascending: true)) == ["delta", "eps", "beta", "zeta", "gamma", "alpha"])
    // the first click on the title is the biggest first, the second reverses, and a click on another title leaves it
    var order = ProjectOrder().clicked(.disk)
    #expect(order == ProjectOrder(key: .disk, ascending: false))
    order = order.clicked(.disk)
    #expect(order == ProjectOrder(key: .disk, ascending: true))
    #expect(order.clicked(.name) == ProjectOrder(key: .name, ascending: true))
}

@Test func theWorktreeRowsCarryTheSizeOfEachFolderAndADashForOneNotMeasured() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: "main"), worktrees: [
        .init(path: "/w/a", branch: "carrier/a", session: .init(id: "1", title: "Add retry"), lastActiveAt: 0, state: .clean),
        .init(path: "/w/new", branch: "carrier/new", session: nil, lastActiveAt: 0, state: .clean),
    ])
    let rows = worktreeRows(reply, sizes: ["/p/app": 1_830_000_000, "/w/a": 310_000], now: now, format: format, bundle: english.bundle, locale: english.locale)
    #expect(rows.map(\.size) == ["1.8 GB", "310 KB", "—"])
    #expect(rows.map(\.bytes) == [1_830_000_000, 310_000, nil])
    // with no figures at all, every row says so
    #expect(worktreeRows(reply, now: now, format: format, bundle: english.bundle, locale: english.locale).map(\.size) == ["—", "—", "—"])
}

@Test func theBarGivesEachFolderItsShareInTheOrderOfTheRowsAndLeavesOutWhatHasNoSize() {
    let reply = ProjectWorktrees(main: .init(path: "/p/app", branch: "main"), worktrees: [
        .init(path: "/w/a", branch: nil, session: nil, lastActiveAt: 0, state: .clean),
        .init(path: "/w/empty", branch: nil, session: nil, lastActiveAt: 0, state: .clean),
        .init(path: "/w/new", branch: nil, session: nil, lastActiveAt: 0, state: .clean),
    ])
    let shares = diskShares(worktreeRows(reply, sizes: ["/p/app": 750, "/w/a": 250, "/w/empty": 0], now: now, format: format, bundle: english.bundle, locale: english.locale))
    #expect(shares == [DiskShare(id: "/p/app", fraction: 0.75), DiskShare(id: "/w/a", fraction: 0.25)])
    #expect(diskShares(worktreeRows(reply, now: now, format: format, bundle: english.bundle, locale: english.locale)).isEmpty)
}

@Test func theTotalSaysItIsBeingMeasuredWhenTheFigureWasTakenOrThatThereIsNone() {
    let taken = ProjectDiskFigure(folder: "/p/app", bytes: 1, measuredAt: (now.timeIntervalSince1970 - 3 * 3_600) * 1000)
    #expect(diskTotalWords(taken, measuring: true, now: now, format: format, bundle: english.bundle, locale: english.locale) == "Measuring now")
    #expect(diskTotalWords(taken, measuring: false, now: now, format: format, bundle: english.bundle, locale: english.locale) == "Measured 3h ago")
    #expect(diskTotalWords(ProjectDiskFigure(folder: "/p/app", bytes: 1, measuredAt: now.timeIntervalSince1970 * 1000), measuring: false, now: now, format: format, bundle: english.bundle, locale: english.locale) == "Measured just now")
    #expect(diskTotalWords(nil, measuring: false, now: now, format: format, bundle: english.bundle, locale: english.locale) == "Not measured yet")
    #expect(diskTotalWords(ProjectDiskFigure(folder: "/p/app", bytes: nil), measuring: false, now: now, format: format, bundle: english.bundle, locale: english.locale) == "Not measured yet")
}

private func temporaryProjects(_ paths: [String]) throws -> (folder: String, file: ProjectsFile) {
    let folder = NSTemporaryDirectory() + "carrier-disk-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    let file = ProjectsFile(folder: folder)
    for path in paths { try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }
    for path in paths { try file.add(folder: path) }
    return (folder, file)
}

@MainActor @Test func theListAsksForTheStaleOnesOnceAndThenPollsOnlyWhatTheHostIsMeasuringUntilItHasTheFigure() async throws {
    let base = NSTemporaryDirectory() + "carrier-disk-projects-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: base) }
    let (folder, file) = try temporaryProjects([base + "/app", base + "/notes"])
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost()
    // a first answer says app is being measured and notes has a figure; later reads find app's
    host.diskAnswer = { folders, refresh in
        if refresh == .stale { return ProjectDiskReply(projects: [.init(folder: folders[0], bytes: nil), .init(folder: folders[1], bytes: 2_000, measuredAt: 5)], measuring: [folders[0]]) }
        return ProjectDiskReply(projects: folders.map { .init(folder: $0, bytes: 9_000_000, measuredAt: 6) })
    }
    let model = ProjectsModel(host: host, file: file) { _ in nil }
    let following = Task { await model.follow(every: .milliseconds(10)) }
    defer { following.cancel() }
    for _ in 0..<300 where model.disk[model.rows.first?.path ?? ""]?.bytes != 9_000_000 { try? await Task.sleep(for: .milliseconds(10)) }
    let paths = model.rows.map(\.path)
    #expect(paths.count == 2 && model.disk[paths[0]]?.bytes == 9_000_000 && model.disk[paths[1]]?.bytes == 2_000)
    #expect(model.measuring.isEmpty)
    // the stale ask went once, for every project; the reads that followed were for the one being measured and nothing else
    let asked = host.diskAsked
    #expect(asked.filter { $0.refresh == .stale }.count == 1 && asked[0].folders == paths)
    #expect(asked.dropFirst().allSatisfy { $0.refresh == .read && $0.folders == [paths[0]] })
}

@MainActor @Test func openingAProjectAsksForAFreshFigureOfThatOneFolderAndAHostThatCannotAnswerLeavesTheDashes() async throws {
    let base = NSTemporaryDirectory() + "carrier-disk-projects-\(UUID().uuidString)"
    defer { try? FileManager.default.removeItem(atPath: base) }
    let (folder, file) = try temporaryProjects([base + "/app"])
    defer { try? FileManager.default.removeItem(atPath: folder) }
    let host = CloneHost()
    host.diskAnswer = { folders, _ in ProjectDiskReply(projects: folders.map { .init(folder: $0, bytes: 4_000, measuredAt: 1, parts: [$0: 4_000]) }, measuring: folders) }
    let model = ProjectsModel(host: host, file: file) { _ in nil }
    model.reload()
    let path = model.rows[0].path
    await model.refreshDisk(.now, of: [path])
    #expect(host.diskAsked.map(\.refresh) == [.now] && host.diskAsked[0].folders == [path])
    #expect(model.measuring == [path] && model.disk[path]?.parts == [path: 4_000])

    // an older host refuses (the real one says to restart it): nothing is known and nothing is shown but a dash
    let older = CloneHost()
    older.failure = ControlError.remote(.projectsNeedNewerHost)
    let dashes = ProjectsModel(host: older, file: file) { _ in nil }
    dashes.reload()
    await dashes.refreshDisk(.stale)
    #expect(dashes.disk.isEmpty && dashes.measuring.isEmpty && projectsWithDisk(dashes.rows, figures: dashes.disk).allSatisfy { $0.diskBytes == nil })
}
