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
            VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                Button { open() } label: { Label(words.joined(separator: " "), icon: .terminal).font(.scaled(12, design: .monospaced)) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help("Opens Terminal and runs this command")
                if let failure { Text(failure).font(.scaled(11)).foregroundStyle(.red) }
            }
        case .install(let url):
            Link("Installation page", destination: url).font(.scaled(12))
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
