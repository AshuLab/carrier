import CarrierCore
import SwiftUI

/// The message held while the agent answers: when it goes, and what it says under it. Clicking the message puts it back in the box to
/// edit; Send now stops the turn and sends it (not offered when sending already stops the turn, which is what the setting says); the
/// cross drops it.
struct QueuedMessageCard: View {
    let text: String
    let interrupts: Bool
    let edit: () -> Void
    let sendNow: () -> Void
    let cancel: () -> Void

    var body: some View {
        NoticeCard(
            symbol: .clock, tint: .gray, title: interrupts ? "Sends when the agent stops" : "Sends when the agent finishes",
            detail: messagePreview(text), detailLines: 2, onTap: edit
        ) {
            if interrupts == false {
                Button("Send now", action: sendNow).buttonStyle(NoticeActionStyle()).help("Stop the agent and send it now")
            }
            Button(action: cancel) { Glyph(.close, size: 10) }
                .buttonStyle(NoticeActionStyle(quiet: true)).help("Cancel the queued message").accessibilityLabel("Cancel the queued message")
        }
        .help("Click the message to edit it")
    }
}

/// A problem the person is told of, as a notice like the others and not a plain coloured line: orange for what is theirs to solve (wait, interrupt, choose
/// again, a name that cannot be used), red for what failed. `init(text:)` is the host's own sentence under a title of ours, and `init(sentences:)` splits
/// one sentence into title and detail (`splitNotice`).
struct ProblemNotice: View {
    let title: String
    let detail: String?
    var failed = false
    var symbol = AppIcon.exclamation

    init(title: String, detail: String?, failed: Bool = false, symbol: AppIcon = .exclamation) {
        (self.title, self.detail, self.failed, self.symbol) = (title, detail, failed, symbol)
    }

    init(text: String, failed: Bool = false) {
        self.init(title: failed ? "Couldn't read this session" : "Couldn't do that", detail: text, failed: failed)
    }

    init(sentences text: String, failed: Bool = false) {
        let parts = splitNotice(text)
        self.init(title: parts.title, detail: parts.detail, failed: failed)
    }

    var body: some View {
        NoticeCard(symbol: symbol, tint: failed ? .red : .orange, title: title, detail: detail) {}
    }
}

/// An archived session is read only: a notice with Resume, which takes it out of the archive.
struct ArchivedSessionNotice: View {
    let resume: () -> Void

    var body: some View {
        // two lines at most: with no limit this detail made the whole window lay out taller than it is, the notice below its edge
        NoticeCard(symbol: .archive, tint: .gray, title: archivedSessionNotice.title, detail: archivedSessionNotice.detail, detailLines: 2) {
            Button("Resume", action: resume).buttonStyle(NoticeActionStyle())
        }
    }
}

/// An idle session whose folder was deleted with its project: it stays as history and cannot go on.
struct FolderGoneNotice: View {
    var body: some View {
        NoticeCard(symbol: .trash, tint: .gray, title: folderGoneNotice.title, detail: folderGoneNotice.detail) {}
    }
}

/// A session whose agent is not running: what it means and what a message does, above the box, in the colour of night.
struct ClosedSessionNotice: View {
    /// Whether the person already chose something that will apply when the session wakes.
    let chosen: Bool

    var body: some View {
        NoticeCard(symbol: .sleep, tint: .indigo, title: closedSessionNotice.title, detail: chosen ? closedSessionNotice.chosen : closedSessionNotice.detail) {}
    }
}
