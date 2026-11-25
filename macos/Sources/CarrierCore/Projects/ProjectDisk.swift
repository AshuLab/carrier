import Foundation

// What a project takes on disk (docs/specs/projects.md, Scope 13 and Decisions "Size"): the host measures in the background and keeps the figures; the app shows the
// last known one and asks again.

/// One project's figure as the host last measured it: its main clone and its worktrees together, and each folder's part by path.
public struct ProjectDiskFigure: Decodable, Equatable, Sendable {
    public let folder: String
    /// Nil until the host has measured the project.
    public let bytes: Int?
    /// Milliseconds since the epoch.
    public let measuredAt: Double?
    public let parts: [String: Int]

    public init(folder: String, bytes: Int?, measuredAt: Double? = nil, parts: [String: Int] = [:]) {
        self.folder = folder
        self.bytes = bytes
        self.measuredAt = measuredAt
        self.parts = parts
    }
}

/// The reply of `projectDisk`: a figure for each folder the host would measure, and which of them are queued or being measured.
public struct ProjectDiskReply: Decodable, Equatable, Sendable {
    public let projects: [ProjectDiskFigure]
    public let measuring: [String]

    public init(projects: [ProjectDiskFigure], measuring: [String] = []) {
        self.projects = projects
        self.measuring = measuring
    }
}

/// What a `projectDisk` ask makes the host measure: nothing (`read`), the projects never measured or measured a day ago or more (`stale`), or all of them (`now`).
public enum ProjectDiskRefresh: String, Sendable {
    case read, stale, now
}

/// "1.2 GB", "75 MB", "310 KB": decimal, whatever the language of the Mac, so a column of sizes lines up.
public func formatDiskSize(_ bytes: Int) -> String {
    bytes >= 1_000_000 ? formatModelSize(Int64(bytes)) : "\(bytes / 1000) KB"
}

/// `rows` with `diskBytes` set from the host's figures, found by the project's folder (written with `~` or not); nil for a project never measured and always for
/// one whose folder is gone, which the host is not asked about.
public func projectsWithDisk(_ rows: [ProjectRow], figures: [String: ProjectDiskFigure]) -> [ProjectRow] {
    rows.map { row in
        var row = row
        row.diskBytes = row.status == .ready ? figures[(row.path as NSString).expandingTildeInPath]?.bytes : nil
        return row
    }
}

/// How much of the bar one folder fills.
public struct DiskShare: Equatable, Identifiable, Sendable {
    public let id: String
    public let fraction: Double
}

/// The bar of a project's page: one share for each row that has a size, the main clone first, in the order of the rows; a row with no size or an empty one has none.
public func diskShares(_ rows: [WorktreeRow]) -> [DiskShare] {
    let total = rows.reduce(0) { $0 + ($1.bytes ?? 0) }
    guard total > 0 else { return [] }
    return rows.compactMap { row in
        guard let bytes = row.bytes, bytes > 0 else { return nil }
        return DiskShare(id: row.id, fraction: Double(bytes) / Double(total))
    }
}

/// What the total of a project's page says under it: that it is being measured, when the figure on show was taken, or that there is none yet.
public func diskTotalWords(
    _ figure: ProjectDiskFigure?, measuring: Bool, now: Date, format: TimeFormat = .stored(), bundle: Bundle? = nil, locale: Locale = .current
) -> String {
    if measuring { return Copy.projectsDiskMeasuring(bundle: bundle, locale: locale) }
    guard let taken = figure?.measuredAt else { return Copy.projectsDiskNotMeasured(bundle: bundle, locale: locale) }
    let age = timeText(Date(timeIntervalSince1970: taken / 1000), now: now, format: format)
    return age == "now" ? Copy.projectsDiskMeasuredNow(bundle: bundle, locale: locale) : Copy.projectsDiskMeasuredAgo(age: age, bundle: bundle, locale: locale)
}
