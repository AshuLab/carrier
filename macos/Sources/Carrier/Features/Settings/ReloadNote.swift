import CarrierCore
import SwiftUI

/// What the engine answered to the last save when it did not apply it (`ReloadStatus`): the same on every page, until a save is applied or
/// Carrier stops. The page passes the words (`ReloadStatus.words`) and whether they are a problem; a problem is said to VoiceOver once, when the answer
/// comes (`answers` counts them, so two refusals in a row are two), not each time the person comes back to the page, and has a way out: Ask Carrier again.
struct ReloadNote: View {
    let words: String?
    let isProblem: Bool
    let pending: Bool
    let answers: Int
    let ask: () -> Void

    var body: some View {
        Group {
            if let words {
                HStack(spacing: Tokens.Space.s10) {
                    if isProblem {
                        ProblemLine(text: words, announces: false)
                        AskAgainButton(pending: pending, action: ask)
                    } else {
                        Label(words, icon: .info).scaledFont(12).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .announcesReloadProblems(answers: answers, isProblem: isProblem, words: words)
    }
}

extension ReloadNote {
    /// The note of what `status` last answered.
    init(_ status: ReloadStatus) {
        self.init(words: status.words, isProblem: status.isProblem, pending: status.pending, answers: status.answers, ask: { status.ask() })
    }
}

extension View {
    /// Says a problem answer of the engine to VoiceOver when it comes (`answers` changes), on the page that is open (a page that shows `ReloadNote` or the header).
    func announcesReloadProblems(answers: Int, isProblem: Bool, words: String?) -> some View {
        onChange(of: answers) {
            if isProblem, let words { AccessibilityNotification.Announcement(words).post() }
        }
    }
}
