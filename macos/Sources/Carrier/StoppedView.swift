import CarrierCore
import SwiftUI

/// The Overview while Carrier is not running (or not answered yet): what happened, the button that starts it and what it needs to
/// start, each thing with a tick or a mark and a way to Settings when something is missing.
struct StoppedView: View {
    let state: ConnectionState?
    @Binding var selection: Selection
    @ObservedObject private var setup = SetupController.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                VStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.secondary)
                        .frame(width: 54, height: 54)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.secondary.opacity(0.12)))
                        .padding(.bottom, 9)
                    Text(title).font(.title3.weight(.semibold))
                    Text(line).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                }
                if state == .stopped {
                    StartCarrierButton()
                    needs
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 420)
        }
    }

    private var icon: String { state == nil ? "bolt.horizontal.circle" : state == .stopped ? "power.circle" : "exclamationmark.triangle" }

    private var title: String { state == nil ? "Connecting…" : state?.menuLine ?? "" }

    private var line: String {
        switch state {
        case nil: "Looking for Carrier."
        case .stopped?: "Start it to watch your repositories and run agents on the epics that are ready."
        default: "The app and Carrier speak different versions. Update whichever is older."
        }
    }

    /// What starting needs: the four things the settings hold, as the Engine tab shows them.
    private var needs: some View {
        let rows = engineTab(setup.settings, detecting: setup.detecting).rows.filter { $0.field != .path }
        return VStack(alignment: .leading, spacing: 8) {
            OverviewTitle(title: "What Carrier needs")
            OverviewCard {
                ForEach(rows, id: \.field) { row in
                    HStack(spacing: 12) {
                        StatusDot(found: row.found)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title).fontWeight(.medium)
                            Text(row.value ?? "Not found").font(.caption.monospaced())
                                .foregroundStyle(row.found ? Color.secondary : .orange).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 9)
                }
            }
            if rows.contains(where: { !$0.found }) {
                Button("Open Settings") { selection = .settings }.buttonStyle(.bordered).controlSize(.small).padding(.leading, 14)
            }
        }
        .frame(maxWidth: 460)
    }
}
