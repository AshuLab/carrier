import AppKit
import CarrierCore
import SwiftUI

/// Opens the script through `NSWorkspace`, which hands it to the user's handler for `.command` files (Terminal by default).
struct WorkspaceTerminalOpener: TerminalOpener {
    func open(_ script: URL) throws {
        guard NSWorkspace.shared.open(script) else { throw ContinueError.notWritten }
    }
}

/// Under an open epic session that is not running: a card line of the feed that opens the embedded terminal drawer
/// on the validated command. Nothing for a session with no descriptor (running) or one the validation refuses.
struct ContinueInTerminalView: View {
    let section: SessionSection
    let onContinue: (ValidResume) -> Void
    @State private var hovered = false

    var body: some View {
        if let descriptor = section.resume {
            let engine = engineFolder()
            if case .success(let valid) = validateResume(descriptor, engine: engine) {
                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        guard case .success(let freshValid) = validateResume(descriptor, engine: engineFolder()) else {
                            tell("The session folder is no longer available.")
                            return
                        }
                        onContinue(freshValid)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "terminal").font(.scaled(12)).foregroundStyle(.secondary).frame(width: 16, height: 16)
                            Text("Continue in Terminal").fontWeight(.semibold)
                            Text("· resumes this session").foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                        }
                        .font(.scaled(12.5)).lineLimit(1)
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(hovered ? 0.05 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 }
                    .help(section.state == .stopped
                        ? "Opens the terminal panel below in the folder it started in and resumes \(section.agent) so you can keep talking to it.\n\(resumeCommand(valid))"
                        : resumeCommand(valid))
                    .accessibilityHint("Opens the terminal panel and resumes this session")
                }
                .workCard()
                .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, 4)
                .sessionRow()
            }
        }
    }
}
