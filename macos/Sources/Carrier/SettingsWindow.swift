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
            Field(title: "carrier", hint: "Path of the carrier binary", value: $setup.settings.carrier)
            Field(title: "node", hint: "Path of node", value: $setup.settings.node)
            Field(title: "PATH", hint: "PATH to find the tools with", value: $setup.settings.path)

            VStack(alignment: .leading, spacing: 2) {
                Text("PATH Carrier will run with").font(.caption).foregroundStyle(.secondary)
                Text(enginePath(detected: setup.settings.path, node: setup.settings.node))
                    .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
            }

            HStack {
                Button("Detect again") { setup.detect() }.disabled(setup.detecting)
                if setup.detecting {
                    ProgressView().controlSize(.small)
                    Text("Asking your shell…").foregroundStyle(.secondary)
                }
            }
            if let message = setup.message {
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
        .padding(18)
        .frame(width: 560)
    }
}

private struct Field: View {
    let title: String
    let hint: String
    @Binding var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.headline)
                if value.isEmpty {
                    Label("not found", systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
                }
            }
            TextField(hint, text: $value).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
        }
    }
}
