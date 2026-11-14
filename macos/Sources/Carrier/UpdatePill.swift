import CarrierCore
import SwiftUI

/// The sidebar's title bar, after the window's buttons: the update, from the version found to Restart, as one glass pill
/// (docs/research/macos-app-design/explorations/update-pill-options.html, option B). It slides in out of a blur; while it downloads the
/// version rolls to the percent and the chat's thinking glow runs round its edge; done, a tick bounces and it rolls to Restart, whose words
/// shimmer. A failed download leaves Retry. Absent while there is nothing new.
struct UpdatePill: View {
    let model = AppUpdater.model
    /// The tick and "Ready" between the download and Restart.
    @State private var justDownloaded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ToolbarContentBuilder static var item: some ToolbarContent {
        ToolbarItem(placement: .automatic) { UpdatePill() }.sharedBackgroundVisibility(.hidden)
    }

    private var phase: UpdatePhase { model.flow.phase }

    var body: some View {
        ZStack {
            if phase != .none {
                Button { model.press() } label: {
                    HStack(spacing: 5) {
                        icon
                        // the words that leave roll out of the pill, not over the title bar
                        ZStack { label }.clipped()
                    }
                    .padding(.horizontal, 11).frame(height: ToolbarPillButton.height)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular, in: .capsule)
                .overlay {
                    GlowEdge(color: .thought, waiting: false, moves: reduceMotion == false, cornerRadius: ToolbarPillButton.height / 2)
                        .opacity(downloading ? 1 : 0).allowsHitTesting(false)
                }
                .disabled(phase == .installing)
                .help(help)
                .accessibilityLabel(help)
                .transition(.move(edge: .leading).combined(with: .blurReplace))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3), value: phase)
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.3), value: justDownloaded)
        .onChange(of: phase) { old, new in
            guard case .downloading = old, case .ready = new else { return }
            justDownloaded = true
            Task {
                try? await Task.sleep(for: .milliseconds(750))
                justDownloaded = false
            }
        }
    }

    private var downloading: Bool {
        if case .downloading = phase { true } else { false }
    }

    private var icon: some View {
        let (name, tint): (String, Color) = switch phase {
        case .none, .available: ("arrow.down.to.line", .themeAccent)
        case .downloading: ("arrow.down.to.line", .primary)
        case .ready: justDownloaded ? ("checkmark", .primary) : ("arrow.clockwise", .themeAccent)
        case .installing: ("arrow.clockwise", .themeAccent)
        case .failed: ("exclamationmark.triangle", .orange)
        }
        return Image(systemName: name).font(.scaled(11, weight: .medium)).foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce.down, options: .repeating, isActive: downloading && reduceMotion == false)
            .symbolEffect(.rotate, options: .repeating, isActive: phase == .installing && reduceMotion == false)
    }

    /// Each kind of words rolls in from below; the percent only turns its digits.
    private var label: some View {
        let (kind, text): (String, String) = switch phase {
        case .none: ("none", "")
        case .available(let version): ("version", version)
        case .downloading(_, let percent): ("percent", "\(percent)%")
        case .ready: justDownloaded ? ("done", "Ready") : ("restart", "Restart")
        case .installing: ("installing", "Restarting…")
        case .failed: ("failed", "Retry")
        }
        let shimmers = kind == "restart" || kind == "installing"
        return Text(text).font(.scaled(12, weight: .medium)).monospacedDigit()
            .foregroundStyle(shimmers && reduceMotion == false ? .secondary : .primary)
            .modifier(Shimmer(active: shimmers && reduceMotion == false))
            .contentTransition(.numericText())
            .id(kind)
            .transition(.push(from: .bottom).combined(with: .opacity))
    }

    private var help: String {
        switch phase {
        case .none: ""
        case .available(let version): "Download Carrier \(version)"
        case .downloading(let version, let percent): "Downloading Carrier \(version), \(percent) percent"
        case .ready(let version): justDownloaded ? "Carrier \(version) is downloaded" : "Restart to update to Carrier \(version)"
        case .installing: "Restarting"
        case .failed(let version): "The download of Carrier \(version) failed. Retry"
        }
    }
}
