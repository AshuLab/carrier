import CarrierCore
import CarrierUI
import SwiftUI

/// The Rows of `CarrierUI/` in the states their catalog entries list.
struct PiecesGalleryRows: View {
    @Environment(\.pieceTheme) private var theme
    private let wide: CGFloat = 420

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("HoverRow") {
                GalleryState(.normal) { HoverRow(action: {}) { _ in Text(sample(.row)).padding(Tokens.Space.s8) }.frame(width: 240) }
                GalleryState(.selected) { HoverRow(action: {}, fill: theme.accent.opacity(0.3)) { _ in Text(sample(.row)).padding(Tokens.Space.s8) }.frame(width: 240) }
                GalleryState(.disabled) { HoverRow(action: {}) { _ in Text(sample(.row)).padding(Tokens.Space.s8) }.frame(width: 240).disabled(true) }
            }
            GalleryEntry("MonoLines") {
                GalleryState(.normal) { MonoLines(lines: PiecesGalleryData.lines, monospace: MonospaceSettings()).codeFont(11.5).frame(width: 300) }
                GalleryState(.withDetail) { MonoLines(lines: PiecesGalleryData.lines, monospace: MonospaceSettings(wrapLongLines: false, lineNumbers: true)).codeFont(11.5).frame(width: 300) }
                GalleryState(.error) { MonoLines(lines: PiecesGalleryData.lines, redFirst: true, monospace: MonospaceSettings()).codeFont(11.5).frame(width: 300) }
            }
            GalleryEntry("NavigationRow") {
                GalleryState(.normal) { card { NavigationRow(title: sample(.row), detail: sample(.rowDetail), first: true, action: {}) { EmptyView() } } }
                GalleryState(.withIcon) {
                    card { NavigationRow(title: sample(.row), detail: sample(.rowDetail), leading: AccountMark(initials: PiecesGalleryData.initials, tint: .blue, size: 22), first: true, action: {}) { Text(sample(.label)).foregroundStyle(.secondary) } }
                }
            }
            GalleryEntry("SettingsTabRow") {
                GalleryState(.normal) { card { SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true) { Toggle(sample(.label), isOn: .constant(true)).labelsHidden() } } }
                GalleryState(.withDetail) {
                    card { SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true, note: PiecesGalleryData.path) { Toggle(sample(.label), isOn: .constant(false)).labelsHidden() } }
                }
                GalleryState(.withIcon) {
                    card { SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true, leading: AnyView(AccountMark(initials: PiecesGalleryData.initials, tint: .blue, size: 22))) { EmptyView() } }
                }
                GalleryState(.error) {
                    card { SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true, problem: sample(.problem)) { TextField(sample(.placeholder), text: .constant("")).settingsField(width: 120) } }
                }
                GalleryState(.disabled) { card { SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true) { Toggle(sample(.label), isOn: .constant(true)).labelsHidden() } }.disabled(true) }
            }
            GalleryEntry("SettingsStackedRow") {
                GalleryState(.normal) { card { SettingsStackedRow(title: sample(.row), detail: sample(.rowDetail), first: true) { TextField(sample(.placeholder), text: .constant("")).settingsField() } } }
            }
            GalleryEntry("SidebarSectionRow") {
                GalleryState(.normal) { SidebarSectionRow(title: sample(.group), icon: .archive, selected: false, action: {}).frame(width: 240) }
                GalleryState(.selected) { SidebarSectionRow(title: sample(.group), icon: .archive, selected: true, action: {}).frame(width: 240) }
                GalleryState(.withActions) {
                    SidebarSectionRow(
                        title: sample(.group), icon: .archive, selected: false, keepActions: true, action: {},
                        actions: { Text(PiecesGalleryData.count).foregroundStyle(.secondary) },
                        hoverActions: { IconButton(icon: .plus, name: sample(.label), action: {}) }
                    )
                    .frame(width: 240)
                }
            }
        }
    }

    private func card<Content: View>(@ViewBuilder _ row: () -> Content) -> some View {
        SettingsTabCard { row() }.frame(width: wide)
    }
}
