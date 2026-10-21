import AppKit
import CarrierCore
import SwiftUI

/// The About sheet over a veil: the window's own sheet cannot be closed by a click outside, so it is drawn here.
struct AboutSheetView: View {
    let state: ConnectionState?
    let onInput: (AboutInput) -> Void

    var body: some View {
        let info = Bundle.main.infoDictionary
        let sheet = aboutSheet(version: info?["CFBundleShortVersionString"] as? String, build: info?["CFBundleVersion"] as? String, state: state)
        ZStack {
            Color.black.opacity(0.35).contentShape(Rectangle()).onTapGesture { onInput(.clickOutside) }
            // Escape closes it; the button is only there to carry the key
            Button("Close") { onInput(.escape) }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0)
            card(sheet).onTapGesture { onInput(.clickInside) }
        }
    }

    private func card(_ sheet: AboutSheet) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 19).fill(LinearGradient(colors: [Color(white: 0.23), Color(white: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                    .overlay { Image(systemName: "text.alignleft").font(.system(size: 38, weight: .regular)).foregroundStyle(.white) }
                Circle().fill(sheet.connected ? Color.green : Color.gray).frame(width: 9, height: 9).padding(14)
            }
            Text(sheet.name).font(.system(size: 20, weight: .bold)).padding(.top, 12)
            Text(sheet.version).foregroundStyle(.secondary).monospacedDigit().padding(.top, 2)
            Text(sheet.connection).font(.caption.weight(.semibold)).foregroundStyle(sheet.connected ? .green : .secondary).padding(.top, 10)
            Text(sheet.summary).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 10)
            HStack(spacing: 6) {
                ForEach(sheet.links, id: \.title) { link in
                    Button("\(link.title) ↗") { NSWorkspace.shared.open(link.url) }.buttonStyle(.glass).controlSize(.small)
                }
            }
            .padding(.top, 14)
            Text(sheet.footer).font(.caption).foregroundStyle(.tertiary).padding(.top, 12)
        }
        .padding(.init(top: 26, leading: 24, bottom: 18, trailing: 24))
        .frame(width: 340)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
    }
}
