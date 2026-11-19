import Foundation

/// Writes one of the system's reports on how the app ran into `folder` and drops the oldest past `limit`, so the folder never grows.
/// The names start with the time, so they sort as the reports came; `index` tells apart the several that arrive in the same second.
public func keepMetricsReport(_ json: Data, kind: String, index: Int = 0, in folder: URL, at moment: Date, keeping limit: Int = 30) throws {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try json.write(to: folder.appending(path: "\(Int(moment.timeIntervalSince1970))-\(index)-\(kind).json"))
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }
    for old in files.dropFirst(limit) { try? FileManager.default.removeItem(at: old) }
}
