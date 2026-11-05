import AppKit
import CarrierCore
import SwiftUI

/// The settings pane: its own small window, kept for the life of the app like the main one.
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    /// Adds the "Settings…" item at the end of the menu.
    func addMenuItem(to menu: NSMenu) {
        let item = menu.addItem(withTitle: "Settings…", action: #selector(openFromMenu), keyEquivalent: ",")
        item.target = self
        showIcon("gearshape", on: item)
    }

    @objc private func openFromMenu() { open() }

    func open() {
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    /// For the self-test.
    var status: String { "visible \(window?.isVisible == true)" }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(setup: .shared)))
        window.title = "Carrier Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        // what the person fixed here is what the chat host needs: look again when they are done
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            ChatHostStarter.shared.checkAtOpen()
        }
        return window
    }
}

struct SettingsView: View {
    @ObservedObject var setup: SetupController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Advanced").font(.headline)
                Spacer()
                Button("Detect again") { setup.detect() }.disabled(setup.detecting)
                if setup.detecting {
                    ProgressView().controlSize(.small)
                    Text("Asking your shell…").foregroundStyle(.secondary)
                }
            }
            UseThisCarrierField(setup: setup)
            if let message = setup.message {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(width: 560)
    }
}
