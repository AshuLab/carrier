import Foundation
import os

/// Where Instruments sees the app's work (os_signpost instrument, filter by the subsystem): what it does at launch, each request on a
/// socket, each rebuild of a feed and the views that recompute in `body`. A signpost costs next to nothing while nobody records.
/// Messages carry command names and counts only, never what a request or a session holds.
public enum Signposts {
    static let subsystem = Bundle.main.bundleIdentifier ?? "dev.ashulab.carrier"
    public static let launch = OSSignposter(subsystem: subsystem, category: "launch")
    public static let poll = OSSignposter(subsystem: subsystem, category: "poll")
    public static let feed = OSSignposter(subsystem: subsystem, category: "feed")
    public static let render = OSSignposter(subsystem: subsystem, category: "render")
}
