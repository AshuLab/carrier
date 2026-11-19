import Foundation
@testable import CarrierCore

// MARK: fixtures for the measurements

/// `count` dictations, newest first, `perDay` to a day going back from `newest` and a second apart inside a day, with ids that do not change
/// between runs. Measures how the history groups and draws a long list.
func longDictationEntries(count: Int, perDay: Int, newest: Date) -> [DictationEntry] {
    let day: TimeInterval = 86_400
    return (0..<count).map { index in
        DictationEntry(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012ld", index))!,
            started: newest.addingTimeInterval(-day * Double(index / perDay) - Double(index % perDay)),
            text: "Dictation number \(index): please look at the module and tell me what to change.", model: "apple", transcription: 0.4, audio: 5,
            destination: index % 3 == 0 ? DictationEntry.carrier : "Slack", outcome: index % 5 == 0 ? .copied : .pasted)
    }
}

/// A `files` reply of `paths` distinct files in cards of 500 (the engine's per-card cap), rotating ten extensions that have an icon.
/// Measures how long the Files changed tab takes to build its rows.
func largeFilesReply(paths: Int) -> FilesReply {
    let extensions = ["ts", "tsx", "swift", "json", "md", "yml", "css", "go", "py", "lock"]
    let perSection = 500
    let sections = stride(from: 0, to: paths, by: perSection).enumerated().map { number, start in
        FilesReply.Section(
            id: "lane-\(number + 1)", kind: "lane", title: "Lane \(number + 1)", added: 0, removed: 0,
            files: (start..<min(start + perSection, paths)).map { index in
                FilesReply.File(path: "src/area\(index / 50)/file\(index).\(extensions[index % extensions.count])", added: index % 40, removed: index % 7, alsoIn: [])
            })
    }
    return FilesReply(sections: sections)
}

/// The reply to `fileDiff` for a file of `rows` rows: a hunk header every 50 rows, the rest context, removed and added in turn.
/// The engine stops at 1,000 rows and says so.
func longFileDiff(rows: Int) -> FileDiffReply {
    let signs = [" ", "-", "+"]
    let lines = (0..<rows).map { index in
        index % 50 == 0
            ? ExecEvent.DiffLine(sign: "@", text: "@@ -\(index + 1),50 +\(index + 1),50 @@")
            : ExecEvent.DiffLine(sign: signs[index % 3], text: "let value\(index) = compute(\(index))")
    }
    return FileDiffReply(rows: lines, truncated: rows >= 1_000, note: nil)
}
