import CarrierCore
import SwiftUI

/// The Carrier home while Carrier is not running (or not answered yet): what happened and the button that starts it. When the setup
/// lacks something the button is off and one line says what, with the way to Settings; with no config it says the engine is not configured.
struct StoppedView: View {
    let state: ConnectionState?
    let openSettings: () -> Void
    @ObservedObject private var setup = SetupController.shared
    @ObservedObject private var start = StartController.shared

    var body: some View {
        // the content is at least as tall as the window, so it sits in the middle both ways and scrolls only when it does not fit
        GeometryReader { window in
            ScrollView {
                VStack(spacing: Tokens.Space.s22) {
                    VStack(spacing: Tokens.Space.s6) {
                        Glyph(icon, size: 26).foregroundStyle(.secondary)
                            .frame(width: 54, height: 54)
                            .background(RoundedRectangle(cornerRadius: Tokens.Radius.panel).fill(Color.secondary.opacity(0.12)))
                            .padding(.bottom, Tokens.Space.s8)
                        Text(title).font(.title3.weight(.semibold))
                        Text(line).textSelection(.enabled).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
                    }
                    if state == .stopped {
                        StartCarrierButton()
                        missing
                    }
                }
                .padding(Tokens.Space.s28)
                .frame(maxWidth: .infinity, minHeight: window.size.height)
            }
        }
    }

    private var icon: AppIcon { state == nil ? .bolt : state == .stopped ? .power : .warning }

    private var title: String { state == nil ? "Connecting…" : state?.menuLine ?? "" }

    private var line: String {
        switch state {
        case nil: "Looking for Carrier."
        case .stopped?: "Start it to watch your repositories and run agents on the epics that are ready."
        case .incompatible(let update?)?: update
        default: "The app and Carrier speak different versions. Update whichever is older."
        }
    }

    /// Why the button is off, when it is: no config (nothing to do about it here), else the Engine tab's banner text and the way to the tab.
    @ViewBuilder private var missing: some View {
        let banner = readinessBanner(missing: setup.missing, detecting: setup.detecting)
        if let notice = engineNotConfiguredNotice(configExists: start.configExists) {
            Label(notice, icon: .warningFilled)
                .font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxWidth: 340)
        } else if banner.state != .ready {
            VStack(spacing: Tokens.Space.s8) {
                Label(banner.title, icon: banner.state == .detecting ? .search : .warningFilled)
                    .font(.callout).foregroundStyle(.orange)
                if banner.state == .missing {
                    Button("Open Settings", action: openSettings).buttonStyle(.glass).buttonBorderShape(.capsule).controlSize(.small)
                }
            }
        }
    }
}
