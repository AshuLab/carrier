import AppKit
import CarrierCore
import SwiftUI

// The pieces of the Engine page and of the readiness banner over the pages that fix what Carrier is missing.

struct ReadinessBannerView: View {
    let banner: ReadinessBanner
    let detecting: Bool
    let detectAgain: () -> Void

    var body: some View {
        let tint: Color = banner.state == .ready ? .green : .orange
        HStack(spacing: Tokens.Space.s12) {
            if banner.state == .detecting {
                ProgressView().controlSize(.small)
            } else {
                StatusDot(found: banner.state == .ready)
            }
            VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                Text(banner.title).fontWeight(.semibold)
                Text(banner.detail).font(.scaled(11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: detectAgain) { Label("Detect", icon: .refresh).labelStyle(.titleAndIcon) }
                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small).disabled(detecting)
        }
        .padding(.horizontal, Tokens.Space.s14).padding(.vertical, Tokens.Space.s12)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.panel).fill(tint.opacity(0.13)))
        .accessibilityElement(children: .combine)
    }
}

/// The round check or exclamation mark in front of a banner or a row.
struct StatusDot: View {
    let found: Bool

    var body: some View {
        Glyph(found ? .check : .exclamation, size: 11, bold: true).foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(found ? Color.green : Color.orange))
            .accessibilityElement(children: .ignore).accessibilityLabel(found ? "Found" : "Not found")
    }
}

/// The buttons of the `carrier` row: choose another one (a path as chosen; a `.ts` or `.js` one runs under `node`), and go back to the Homebrew one.
struct CarrierChoice: View {
    @ObservedObject var setup: SetupController
    let offersHomebrew: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            if offersHomebrew {
                Button { setup.carrierOverride = "" } label: { Label("Use the Homebrew one", icon: .undo).labelStyle(.titleAndIcon) }
                    .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
            }
            Button { choose() } label: { Label("Use another…", icon: .folderPlus).labelStyle(.titleAndIcon) }
                .buttonStyle(SecondaryCapsuleButtonStyle()).controlSize(.small)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { setup.carrierOverride = url.path }
    }
}
