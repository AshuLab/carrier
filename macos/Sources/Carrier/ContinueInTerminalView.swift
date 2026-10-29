import AppKit
import CarrierCore
import SwiftUI

/// Opens the script through `NSWorkspace`, which hands it to the user's handler for `.command` files (Terminal by default).
struct WorkspaceTerminalOpener: TerminalOpener {
    func open(_ script: URL) throws {
        guard NSWorkspace.shared.open(script) else { throw ContinueError.notWritten }
    }
}

/// Under an open session that is not running: a row of the log's own, edge to edge, that opens a Terminal on the command. The
/// command (and, for a stopped session, what it will do) is its tooltip. Nothing for a session with no descriptor (running) or one
/// the validation refuses.
struct ContinueInTerminalView: View {
    let section: SessionSection
    @State private var failure: String?
    @State private var hovered = false

    var body: some View {
        if let descriptor = section.resume {
            let engine = engineFolder()
            if case .success(let valid) = validateResume(descriptor, engine: engine) {
                VStack(alignment: .leading, spacing: 0) {
                    Button { open(descriptor, engine: engine) } label: {
                        HStack(spacing: LogMetrics.gap) {
                            Image(systemName: "apple.terminal").font(.system(size: 12)).foregroundStyle(.secondary)
                                .frame(width: LogMetrics.iconWidth, height: LogMetrics.iconWidth)
                            HStack(spacing: 4) {
                                Text("Continue in Terminal").fontWeight(.medium)
                                Text("· resumes this session").foregroundStyle(.secondary)
                            }
                            .font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, LogMetrics.iconColumn)
                        .frame(maxWidth: .infinity, minHeight: LogMetrics.groupLine, alignment: .leading)
                        .background(Color.primary.opacity(hovered ? 0.05 : 0))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 }
                    .help(section.state == .stopped
                        ? "Opens a new Terminal in the folder it started in and resumes \(section.agent) so you can keep talking to it.\n\(resumeCommand(valid))"
                        : resumeCommand(valid))
                    .accessibilityHint("Opens Terminal and resumes this session")
                    if let failure {
                        Text(failure).font(.caption).foregroundStyle(.red).padding(.horizontal, LogMetrics.iconColumn).padding(.bottom, 8)
                    }
                }
                // the card's foot gives the bottom 12 pt
                .sessionRow()
            }
        }
    }

    private func open(_ descriptor: ResumeDescriptor, engine: String) {
        do {
            try continueInTerminal(descriptor, engine: engine, opener: WorkspaceTerminalOpener())
            failure = nil
        } catch {
            NSLog("Carrier: continue in Terminal failed: %@", String(describing: error))
            failure = "Could not open Terminal."
        }
    }
}
