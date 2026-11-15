import CarrierCore
import GhosttyTerminal
import SwiftUI

/// Minimal SwiftUI surface for one embedded Ghostty terminal pane owned by `CarrierTerminalStore`.
struct CarrierTerminalView: View {
    let store: CarrierTerminalStore
    let paneId: UUID
    var autoFocus: Bool = false
    var isActivePane: Bool = false
    var isSplit: Bool = false
    var focusWhenActivated: Bool = false
    var onFocusChange: ((Bool) -> Void)? = nil

    var body: some View {
        if let state = store.state(for: paneId) {
            let label = store.pane(id: paneId)?.displayTitle ?? "Terminal"
            MountedTerminalSurface(
                store: store,
                paneId: paneId,
                state: state,
                autoFocus: autoFocus,
                isActivePane: isActivePane,
                isSplit: isSplit,
                focusWhenActivated: focusWhenActivated,
                accessibilityLabel: label,
                onFocusChange: onFocusChange
            )
            .id(paneId)
        } else {
            Color.clear
        }
    }
}

private struct MountedTerminalSurface: View {
    let store: CarrierTerminalStore
    let paneId: UUID
    let state: TerminalViewState
    let autoFocus: Bool
    let isActivePane: Bool
    let isSplit: Bool
    let focusWhenActivated: Bool
    let accessibilityLabel: String
    let onFocusChange: ((Bool) -> Void)?
    @FocusState private var focused: Bool
    @State private var visibilityToken: UUID?

    var body: some View {
        TerminalSurfaceView(context: state)
            .terminalFocused($focused)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(isSplit ? (isActivePane ? "Active pane" : "Pane") : "")
            .onChange(of: focused) { _, isFocused in
                onFocusChange?(isFocused)
            }
            .onChange(of: isActivePane) { _, active in
                if active && focusWhenActivated {
                    focused = true
                    store.focus(paneId: paneId)
                }
            }
            .onAppear {
                if visibilityToken == nil {
                    visibilityToken = store.beginVisibilityMount(for: paneId)
                }
                if autoFocus {
                    focused = true
                    store.focus(paneId: paneId)
                }
            }
            .onDisappear {
                if let token = visibilityToken {
                    store.endVisibilityMount(token, for: paneId)
                    visibilityToken = nil
                }
            }
    }
}
