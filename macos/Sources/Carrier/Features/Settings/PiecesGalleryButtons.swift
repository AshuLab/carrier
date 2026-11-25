import CarrierCore
import SwiftUI

/// The Buttons of `Carrier/UI/` in the states their catalog entries list.
struct PiecesGalleryButtons: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("IconButton") {
                GalleryState(.normal) { IconButton(icon: .refresh, name: sample(.label), action: {}) }
                GalleryState(.open) { IconButton(icon: .refresh, name: sample(.label), pressed: true, action: {}) }
                GalleryState(.disabled) { IconButton(icon: .refresh, name: sample(.label), enabled: false, why: sample(.hint), action: {}) }
            }
            GalleryEntry("HoverFillButtonStyle") {
                GalleryState(.normal) { fill(open: false) }
                GalleryState(.open) { fill(open: true) }
                GalleryState(.disabled) { fill(open: false).disabled(true) }
            }
            GalleryEntry("HoverTextButtonStyle") {
                GalleryState(.normal) { text(tint: nil, danger: false) }
                GalleryState(.tinted) { text(tint: .green, danger: false) }
                GalleryState(.danger) { text(tint: nil, danger: true) }
                GalleryState(.disabled) { text(tint: nil, danger: false).disabled(true) }
            }
            GalleryEntry("PrimaryCapsuleButtonStyle") {
                GalleryState(.normal) { Button(sample(.action)) {}.buttonStyle(PrimaryCapsuleButtonStyle()) }
                GalleryState(.small) { Button(sample(.action)) {}.buttonStyle(PrimaryCapsuleButtonStyle()).controlSize(.small) }
                GalleryState(.large) { Button(sample(.action)) {}.buttonStyle(PrimaryCapsuleButtonStyle(large: true)) }
                GalleryState(.disabled) { Button(sample(.action)) {}.buttonStyle(PrimaryCapsuleButtonStyle()).disabled(true) }
            }
            GalleryEntry("SecondaryCapsuleButtonStyle") {
                GalleryState(.normal) { Button(sample(.cancel)) {}.buttonStyle(SecondaryCapsuleButtonStyle()) }
                GalleryState(.small) { Button(sample(.cancel)) {}.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small) }
                GalleryState(.disabled) { Button(sample(.cancel)) {}.buttonStyle(SecondaryCapsuleButtonStyle()).disabled(true) }
            }
            GalleryEntry("NoticeActionStyle") {
                GalleryState(.normal) { Button(sample(.action)) {}.buttonStyle(NoticeActionStyle()).environment(\.noticeTint, .orange) }
                GalleryState(.quiet) { Button(sample(.cancel)) {}.buttonStyle(NoticeActionStyle(quiet: true)).environment(\.noticeTint, .orange) }
                GalleryState(.disabled) { Button(sample(.action)) {}.buttonStyle(NoticeActionStyle()).environment(\.noticeTint, .orange).disabled(true) }
            }
            GalleryEntry("CheckButton") {
                GalleryState(.idle) { CheckButton(title: sample(.action), phase: .idle, action: {}) }
                GalleryState(.checking) { CheckButton(title: sample(.action), phase: .checking, action: {}) }
                GalleryState(.done) { CheckButton(title: sample(.action), phase: .done, action: {}) }
                GalleryState(.failed) { CheckButton(title: sample(.action), phase: .failed, action: {}) }
                GalleryState(.quiet) { CheckButton(skin: .text, title: sample(.action), phase: .idle, action: {}) }
            }
            GalleryEntry("ToolbarPillButton") {
                GalleryState(.normal) { ToolbarPillButton(title: sample(.label), icon: .refresh, action: {}).pill() }
                GalleryState(.withBadge) { ToolbarPillButton(title: sample(.label), icon: .refresh, badge: 3, action: {}).pill() }
                GalleryState(.working) { ToolbarPillButton(title: sample(.label), icon: .refresh, spinning: true, action: {}).pill() }
                GalleryState(.disabled) { ToolbarPillButton(title: sample(.label), icon: .refresh, action: {}).pill().disabled(true) }
            }
            GalleryEntry("AccentGlassPillButton") {
                GalleryState(.normal) { AccentGlassPillButton(title: sample(.action), action: {}) }
                GalleryState(.withIcon) { AccentGlassPillButton(title: sample(.action), icon: .plus, action: {}) }
                GalleryState(.disabled) { AccentGlassPillButton(title: sample(.action), icon: .plus, action: {}).disabled(true) }
            }
            GalleryEntry("ToolbarGlassIconButton") {
                GalleryState(.normal) { ToolbarGlassIconButton(icon: .search, name: sample(.label), action: {}).pill() }
                GalleryState(.selected) { ToolbarGlassIconButton(icon: .search, active: true, name: sample(.label), action: {}).pill() }
                GalleryState(.disabled) { ToolbarGlassIconButton(icon: .search, name: sample(.label), action: {}).pill().disabled(true) }
            }
            GalleryEntry("ToolbarSearchField") {
                GalleryState(.closed) { SearchSample(open: false) }
                GalleryState(.open) { SearchSample(open: true) }
            }
        }
    }

    private func fill(open: Bool) -> some View {
        Button {} label: { Glyph(.search, size: 14).frame(width: 24, height: 24).contentShape(Rectangle()) }
            .buttonStyle(HoverFillButtonStyle(open: open)).accessibilityLabel(sample(.label))
    }

    private func text(tint: Color?, danger: Bool) -> some View {
        Button(sample(.action)) {}.buttonStyle(HoverTextButtonStyle(tint: tint, danger: danger))
    }
}

private extension View {
    /// A pill of the toolbar sits on glass the caller puts on it.
    func pill() -> some View { glassEffect(.regular, in: .capsule) }
}

/// `ToolbarSearchField` asks for a query and a focus the caller owns.
private struct SearchSample: View {
    let open: Bool
    @State private var query: String?
    @FocusState private var focused: Bool

    var body: some View {
        ToolbarSearchField(query: $query, placeholder: sample(.placeholder), focused: $focused).glassEffect(.regular, in: .capsule)
            .onAppear { query = open ? "" : nil }
    }
}
