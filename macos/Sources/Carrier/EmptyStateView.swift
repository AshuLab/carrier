import AppKit
import CarrierCore
import SwiftUI

/// Icon, title and one line, centred in the space it is given; neutral colours.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let line: String

    init(state: EmptyState) { self.init(icon: state.icon, title: state.title, line: state.line) }

    init(icon: String, title: String, line: String) {
        self.icon = icon
        self.title = title
        self.line = line
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
                .padding(.bottom, 9)
            Text(title).font(.headline)
            // wraps to as many lines as it needs, whatever height it is given
            Text(line).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 280)
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

/// All of them, as in the mockup's gallery; reachable from the menu in `--fixture` mode.
struct EmptyStatesGallery: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(EmptyState.allCases, id: \.title) { state in
                    EmptyStateView(state: state).frame(minHeight: 230)
                        .background(RoundedRectangle(cornerRadius: 20).fill(Color.secondary.opacity(0.06)))
                }
            }
            .padding(18)
        }
    }
}

final class EmptyStatesWindowController: NSObject {
    static let shared = EmptyStatesWindowController()
    private var window: NSWindow?

    func addMenuItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Empty states", action: #selector(open), keyEquivalent: "")
        item.target = self
    }

    @objc private func open() {
        let window = window ?? {
            let made = NSWindow(contentViewController: NSHostingController(rootView: EmptyStatesGallery()))
            made.title = "Empty states"
            made.styleMask = [.titled, .closable, .resizable]
            made.isReleasedWhenClosed = false
            made.setContentSize(NSSize(width: 900, height: 560))
            made.center()
            return made
        }()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
