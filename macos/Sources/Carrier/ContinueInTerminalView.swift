import AppKit
import CarrierCore
import SwiftUI

/// Opens the script through `NSWorkspace`, which hands it to the user's handler for `.command` files (Terminal by default).
struct WorkspaceTerminalOpener: TerminalOpener {
    func open(_ script: URL) throws {
        guard NSWorkspace.shared.open(script) else { throw ContinueError.notWritten }
    }
}

/// Under an open session that is not running: a block with the command and a button for a stopped one, a quiet link for the
/// others. Nothing for a session with no descriptor (running) or one the validation refuses.
struct ContinueInTerminalView: View {
    let section: SessionSection
    @State private var failure: String?

    var body: some View {
        if let descriptor = section.resume {
            let root = sharedRoot(
                configJSON: try? Data(contentsOf: URL(fileURLWithPath: configFilePath(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory()))),
                home: NSHomeDirectory())
            if case .success(let valid) = validateResume(descriptor, root: root) {
                VStack(alignment: .leading, spacing: 8) {
                    if section.state == .stopped {
                        Text("Continue this session").fontWeight(.semibold)
                        Text("Opens a new Terminal in the folder it started in and resumes \(section.agent) so you can keep talking to it.")
                            .foregroundStyle(.secondary)
                        Text(resumeCommand(valid)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .padding(8).background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
                        Button { open(descriptor, root: root) } label: { Label("Continue in Terminal", systemImage: "terminal") }
                            .buttonStyle(.glass).controlSize(.small)
                    } else {
                        Button { open(descriptor, root: root) } label: { Text("Resume this session in Terminal ↗") }
                            .buttonStyle(.link).font(.caption).help(resumeCommand(valid))
                    }
                    if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
                }
                .padding(.horizontal, 12).padding(.bottom, 11).sessionRow()
            }
        }
    }

    private func open(_ descriptor: ResumeDescriptor, root: String) {
        do {
            try continueInTerminal(descriptor, root: root, opener: WorkspaceTerminalOpener())
            failure = nil
        } catch {
            NSLog("Carrier: continue in Terminal failed: %@", String(describing: error))
            failure = "Could not open Terminal."
        }
    }
}
