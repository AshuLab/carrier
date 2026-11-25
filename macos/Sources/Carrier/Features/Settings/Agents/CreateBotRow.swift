import AppKit
import CarrierCore
import SwiftUI

/// Create a bot… on the Agents page: Terminal opens on `agent-forge add` (`createBotInTerminal`). The page reads the registry again when the
/// app is active, so the new bot shows without a refresh button. Under `--fixture` the opener only says what it would have run.
struct CreateBotRow: View {
    @State private var failure: String?

    var body: some View {
        SettingsTabRow(id: "create-a-bot", title: Copy.agentsCreateBotTitle(), detail: failure ?? Copy.agentsCreateBotDetail()) {
            Button { open() } label: { Label(Copy.agentsCreateBotTitle(), icon: .plus) }.buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).help(Copy.agentsCreateBotHelp())
        }
    }

    private func open() {
        do {
            try createBotInTerminal(opener: CommandLine.arguments.contains("--fixture") ? FixtureTerminalOpener() : WorkspaceTerminalOpener())
            failure = nil
        } catch {
            NSLog("Carrier: create a bot in Terminal failed: %@", String(describing: error))
            failure = Copy.agentsCouldNotOpenTerminal()
        }
    }
}
