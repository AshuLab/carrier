import CarrierCore
import SwiftUI

/// The Agent output tab: one card per session with its header (avatar, who, counts, time or the stopped badge) and, below the
/// last, how many earlier sessions there are. An open section has nothing under its header until the transcript is built.
struct SessionSectionsView: View {
    let list: SessionList
    @Binding var folds: SessionFolds

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(list.sections) { section in
                let open = folds.isOpen(section)
                VStack(alignment: .leading, spacing: 0) {
                    Button { folds.toggle(section) } label: { SessionHeaderView(section: section, open: open) }
                        .buttonStyle(.plain)
                    if open { ContinueInTerminalView(section: section) }
                }
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.08)))
            }
            if let earlier = list.earlier { Text(earlier).font(.caption).foregroundStyle(.tertiary).padding(.horizontal, 6) }
        }
    }
}

struct SessionHeaderView: View {
    let section: SessionSection
    let open: Bool

    var body: some View {
        HStack(spacing: 11) {
            AgentAvatar(initial: section.initial, harness: section.agent, working: section.state == .running)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    Text(section.agent).fontWeight(.semibold)
                    Text(" · \(section.role) · \(section.place)").foregroundStyle(.secondary)
                }
                .lineLimit(1)
                if let counts = section.counts { Text(counts).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if section.state == .stopped {
                Text("stopped").font(.caption.weight(.medium)).foregroundStyle(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Color.orange.opacity(0.18)))
            } else if let time = section.timeLabel {
                Text(time).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

/// The agent's letter on a grey disc; a white ring turns inside it while the agent works.
struct AgentAvatar: View {
    let initial: String
    let harness: String
    let working: Bool

    var body: some View {
        Text(initial).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(harness == "Claude" ? Color(white: 0.37) : Color(white: 0.49)))
            .overlay { if working { SpinningRing(diameter: 26, lineWidth: 2, color: .white) } }
            .help(working ? "\(harness) · working" : harness)
    }
}
