import CarrierCore
import SwiftUI

/// The Carrier home while Carrier is not running (or not answered yet): what happened and the button that starts it. When the setup
/// lacks something the button is off and one line says what, with the way to Settings.
struct StoppedView: View {
    let state: ConnectionState?
    @Binding var selection: Selection
    @ObservedObject private var setup = SetupController.shared

    var body: some View {
        // the content is at least as tall as the window, so it sits in the middle both ways and scrolls only when it does not fit
        GeometryReader { window in
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
                        missing
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: window.size.height)
            }
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

    /// Why the button is off, when it is: the Engine tab's banner text and the way to the tab.
    @ViewBuilder private var missing: some View {
        let banner = engineTab(setup.settings, detecting: setup.detecting).banner
        if banner.state != .ready {
            VStack(spacing: 8) {
                Label(banner.title, systemImage: banner.state == .detecting ? "magnifyingglass" : "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
                if banner.state == .missing {
                    Button("Open Settings") { selection = .settings }.buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
                }
            }
        }
    }
}
