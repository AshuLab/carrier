import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

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
                VStack(alignment: .leading, spacing: Tokens.Space.none) {
                    Button {
                        guard case .success(let freshValid) = validateResume(descriptor, engine: engineFolder()) else {
                            tell(Copy.terminalContinueGone())
                            return
                        }
                        onContinue(freshValid)
                    } label: {
                        HStack(spacing: Tokens.Space.s8) {
                            Glyph(.terminal, size: 12).foregroundStyle(.secondary).frame(width: 16, height: 16)
                            Text(Copy.terminalContinueTitle()).fontWeight(.semibold)
                            Text(Copy.terminalContinueResumes()).foregroundStyle(.secondary)
                            Spacer(minLength: 8)
                        }
                        .scaledFont(12.5).lineLimit(1)
                        .padding(.horizontal, Tokens.Space.s10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: Tokens.Radius.card).fill(Color.primary.opacity(hovered ? 0.05 : 0)))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 }
                    .help(section.state == .stopped
                        ? Copy.terminalContinueHelp(agent: section.agent, command: resumeCommand(valid))
                        : resumeCommand(valid))
                    .accessibilityHint(Copy.terminalContinueHint())
                }
                .workCard()
                .padding(.horizontal, LogMetrics.iconColumn).padding(.vertical, Tokens.Space.s4)
                .sessionRow()
            }
        }
    }
}
