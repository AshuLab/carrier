import AppKit
import CarrierCore
import CarrierUI
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
                Button { open() } label: { Label(words.joined(separator: " "), icon: .terminal).scaledFont(12, design: .monospaced) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help(Copy.healthFixHelp())
                if let failure { Text(failure).scaledFont(11).foregroundStyle(.red) }
            }
        case .install(let url):
            Link(Copy.healthInstallPage(), destination: url).scaledFont(12)
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
            failure = Copy.healthTerminalFailed()
        }
    }
}
