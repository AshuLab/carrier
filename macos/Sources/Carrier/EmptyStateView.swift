import AppKit
import CarrierCore
import SwiftUI

enum EmptyStateActionStyle {
    case secondary
    case accentGlass
}

/// Icon, title and one line, centred in the space it is given; neutral colours.
struct EmptyStateView: View {
    let icon: AppIcon
    let title: String
    let line: String
    /// An optional button under the line, for a state the person can get out of by themselves.
    let action: (title: String, run: () -> Void)?
    /// The icon before the button's words.
    let actionIcon: AppIcon?
    let actionStyle: EmptyStateActionStyle

    init(
        state: EmptyState,
        action: (title: String, run: () -> Void)? = nil,
        actionIcon: AppIcon? = nil,
        actionStyle: EmptyStateActionStyle = .secondary
    ) {
        self.init(icon: state.icon, title: state.title, line: state.line, action: action, actionIcon: actionIcon, actionStyle: actionStyle)
    }

    init(
        icon: AppIcon,
        title: String,
        line: String,
        action: (title: String, run: () -> Void)? = nil,
        actionIcon: AppIcon? = nil,
        actionStyle: EmptyStateActionStyle = .secondary
    ) {
        self.icon = icon
        self.title = title
        self.line = line
        self.action = action
        self.actionIcon = actionIcon
        self.actionStyle = actionStyle
    }

    var body: some View {
        VStack(spacing: 5) {
            Glyph(icon, size: 26)
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
                .padding(.bottom, 9)
            Text(title).font(.headline)
            // wraps to as many lines as it needs, whatever height it is given; never narrower than 200, or the window's smallest size
            // (asked with no width) would be one word a line
            Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(minWidth: 200, maxWidth: 280)
            if let action {
                switch actionStyle {
                case .secondary:
                    Button(action: action.run) {
                        if let actionIcon { Label(action.title, icon: actionIcon).labelStyle(.titleAndIcon) } else { Text(action.title) }
                    }
                    .buttonStyle(SecondaryCapsuleButtonStyle())
                    .padding(.top, 8)
                case .accentGlass:
                    AccentGlassPillButton(title: action.title, icon: actionIcon, action: action.run)
                        .padding(.top, 8)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// An empty state's shape (the tile, a title, a line) while what it will show is still on its way: the spinner takes the symbol's
/// place. It appears after a quarter of a second, so a load that is quick never flashes it.
struct LoadingStateView: View {
    let title: String
    let line: String
    @State private var shown = false

    var body: some View {
        VStack(spacing: 5) {
            ProgressView().controlSize(.regular)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
                .padding(.bottom, 9)
            Text(title).font(.headline)
            Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 280)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(shown ? 1 : 0)
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            withAnimation(.easeIn(duration: 0.2)) { shown = true }
        }
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// An empty state that is the whole page, in a scroll view that has nothing to scroll. With nothing scrolling under it the system draws the
    /// toolbar's own grey band over the page; a page that scrolls lets its colour through to the top of the window, and this one is then as the rest.
    /// (`.toolbarBackgroundVisibility(.hidden, for: .windowToolbar)` does not remove the band here, and the empty state no longer asks for it.)
    func inPageScroll() -> some View {
        ScrollView { containerRelativeFrame(.vertical) }.scrollBounceBehavior(.basedOnSize)
    }
}
