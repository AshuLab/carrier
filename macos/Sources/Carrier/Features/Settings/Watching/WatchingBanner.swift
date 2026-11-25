import CarrierCore
import SwiftUI

/// What Watching says when the engine read the saved file and refused it, in the card the screen puts it in: the words (`refusalBanner`), the engine's own kept
/// folded, and the way to mend it. The mark is orange, as the page's other problems are.
struct RefusalBannerView: View {
    let banner: RefusalBanner
    let fix: (SettingsPage) -> Void
    @State private var showingRaw = false
    private let reloaded = ReloadStatus.shared

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Glyph(.warningFilled, size: 16).foregroundStyle(.orange).padding(.top, 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(banner.title).font(.scaled(13).weight(.semibold))
                Text([banner.detail, RefusalBanner.consequence].compactMap { $0 }.joined(separator: " ")).font(.scaled(12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("What Carrier said", isExpanded: $showingRaw) {
                    Text(banner.raw).font(.scaled(11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                }
                .font(.scaled(11.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let page = banner.fix, let title = banner.fixTitle { Button(title) { fix(page) }.controlSize(.small) }
                    AskAgainButton(pending: reloaded.pending) { reloaded.ask() }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
        .announcesReloadProblems(answers: reloaded.answers, isProblem: reloaded.isProblem, words: reloaded.words)
        .accessibilityElement(children: .contain)
    }
}
