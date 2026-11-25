import CarrierCore
import CarrierUI
import SwiftUI

private typealias ExtraRow = GridRow<TupleView<(Text, PullRequestChip)>>

/// The Cards of `CarrierUI/` in the states their catalog entries list.
struct PiecesGalleryCards: View {
    private let wide: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("NoticeCard") {
                GalleryState(.info) { notice(.blue, .info, detail: true).frame(width: wide) }
                GalleryState(.warning) { notice(.orange, .exclamation, detail: true).frame(width: wide) }
                GalleryState(.error) { notice(.red, .exclamation, detail: true).frame(width: wide) }
                GalleryState(.withoutDetail) { notice(.blue, .info, detail: false).frame(width: wide) }
                GalleryState(.withActions) {
                    NoticeCard(symbol: .exclamation, tint: .orange, title: sample(.title), detail: sample(.detail)) {
                        Button(sample(.cancel)) {}.buttonStyle(NoticeActionStyle(quiet: true))
                        Button(sample(.action)) {}.buttonStyle(NoticeActionStyle())
                    }
                    .frame(width: wide)
                }
                GalleryState(.disabled) {
                    NoticeCard(symbol: .exclamation, tint: .orange, title: sample(.title)) {
                        Button(sample(.action)) {}.buttonStyle(NoticeActionStyle()).disabled(true)
                    }
                    .frame(width: wide)
                }
            }
            GalleryEntry("OverviewCard", "OverviewTitle") {
                GalleryState(.normal) {
                    VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                        OverviewTitle(title: sample(.group))
                        overview(wide: false)
                    }
                    .frame(width: 320)
                }
                GalleryState(.withDetail) {
                    VStack(alignment: .leading, spacing: Tokens.Space.s6) {
                        OverviewTitle(title: sample(.group), detail: sample(.tag))
                        overview(wide: true)
                    }
                    .frame(width: 320)
                }
            }
            GalleryEntry("OverviewLinkRow") {
                GalleryState(.normal) { OverviewLinkRow(action: {}) { Text(sample(.row)); Spacer() }.frame(width: 260) }
                GalleryState(.plain) { OverviewLinkRow { Text(sample(.row)); Spacer() }.frame(width: 260) }
            }
            GalleryEntry("SettingsGroup", "SettingsTabCard") {
                GalleryState(.normal) { SettingsGroup(title: sample(.group)) { SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true) { Toggle(sample(.label), isOn: .constant(true)).labelsHidden() } }.frame(width: 420) }
                GalleryState(.withFooter) {
                    SettingsGroup(title: sample(.group), footer: sample(.groupFooter)) {
                        SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true) { Toggle(sample(.label), isOn: .constant(false)).labelsHidden() }
                    }
                    .frame(width: 420)
                }
                GalleryState(.withActions) {
                    SettingsGroup(title: sample(.group), accessory: { Button(sample(.cancel)) {}.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small) }) {
                        SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true) { EmptyView() }
                    }
                    .frame(width: 420)
                }
            }
            GalleryEntry("CardFactsGrid") {
                GalleryState(.normal) { CardFactsGrid(facts: facts).frame(width: 360) }
                GalleryState(.withActions) {
                    CardFactsGrid(facts: [CardFactsGrid<ExtraRow>.Fact(label: sample(.field), value: sample(.detail))]) {
                        GridRow { Text(sample(.tag)).foregroundStyle(.secondary); PullRequestChip(number: 1189, dot: .green, link: nil) }
                    }
                    .frame(width: 360)
                }
            }
            GalleryEntry("CodeBlockView") {
                GalleryState(.normal) { CodeBlockView(language: "swift", code: PiecesGalleryData.code).frame(width: 520) }
                GalleryState(.changes) { CodeBlockView(language: "diff", file: PiecesGalleryData.file, code: PiecesGalleryData.diff).frame(width: 520) }
                GalleryState(.folded) { CodeBlockView(language: "swift", code: PiecesGalleryData.longCode).frame(width: 520) }
            }
            GalleryEntry("HoverCard") {
                GalleryState(.normal) { Text(sample(.row)).padding(Tokens.Space.s8).background(Color.primary.opacity(0.07), in: Capsule()).hoverCard { Text(sample(.detail)).padding(Tokens.Space.s12).frame(width: 240) } }
            }
            GalleryEntry("WorkCard") {
                GalleryState(.normal) { Text(sample(.detail)).padding(Tokens.Space.s12).frame(width: 320, alignment: .leading).workCard() }
            }
        }
    }

    private func notice(_ tint: Color, _ symbol: AppIcon, detail: Bool) -> some View {
        NoticeCard(symbol: symbol, tint: tint, title: sample(.title), detail: detail ? sample(.detail) : nil) { EmptyView() }
    }

    private func overview(wide: Bool) -> some View {
        OverviewCard(fullWidthDividers: wide) {
            OverviewLinkRow(action: {}) { Text(sample(.row)); Spacer() }
            OverviewLinkRow { Text(sample(.rowDetail)); Spacer() }
        }
    }

    private var facts: [CardFactsGrid<EmptyView>.Fact] {
        [
            .init(label: sample(.tag), value: sample(.detail)),
            .init(label: sample(.field), value: PiecesGalleryData.path, kind: .path, detail: PiecesGalleryData.path),
            .init(label: sample(.field), value: PiecesGalleryData.branch, kind: .branch),
            .init(label: sample(.account), value: sample(.account), kind: .account(mark: AccountMark(initials: PiecesGalleryData.initials, tool: "claude", tint: .purple), name: sample(.account))),
        ]
    }
}
