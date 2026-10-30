import AppKit
import CarrierCore
import SwiftUI

/// What the fixed list has for a failed check (`healthFix`): a button that names the command and opens Terminal on it (the script and the
/// opener are Continue in Terminal's), or a link to the CLI's installation page. Nothing for a check with no fix.
struct HealthFixButton: View {
    let tool: HealthTool
    let state: ToolState
    @State private var failure: String?

    var body: some View {
        switch healthFix(tool, state) {
        case .command(let words):
            VStack(alignment: .leading, spacing: 2) {
                Button { open() } label: { Label(words.joined(separator: " "), systemImage: "apple.terminal").font(.system(.callout, design: .monospaced)) }
                    .controlSize(.small).help("Opens Terminal and runs this command")
                if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
            }
        case .install(let url):
            Link("Installation page", destination: url).font(.callout)
        case nil:
            EmptyView()
        }
    }

    private func open() {
        do {
            try fixInTerminal(tool, state, opener: WorkspaceTerminalOpener())
            failure = nil
        } catch {
            NSLog("Carrier: health fix in Terminal failed: %@", String(describing: error))
            failure = "Could not open Terminal."
        }
    }
}
