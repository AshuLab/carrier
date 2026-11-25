import AppKit
import CarrierCore
import SwiftUI
import UniformTypeIdentifiers

/// Full-size center detail view when an individual standalone terminal instance (and its group of tabs) is selected from Terminal.
struct TerminalDetailView: View {
    let store: CarrierTerminalStore
    let terminalId: UUID
    let newTerminal: () -> Void

    @State private var headerSafeInset: CGFloat = 0

    private var owner: TerminalOwner { .terminal(terminalId) }
    private var tabs: [TerminalTab] { store.tabs(for: owner) }
    private var activeTab: TerminalTab? { store.activeTab(for: owner) ?? tabs.first }

    var body: some View {
        Group {
            if let tab = activeTab {
                // Let the terminal surface extend behind the translucent top toolbar across the full detail height,
                // while offsetting top-edge floating pane controls below `headerSafeInset` so they never collide
                // with toolbar buttons and keeping the tab bar anchored cleanly below.
                GeometryReader { proxy in
                    let tabBarTotalHeight = TerminalTabBarView<EmptyView>.height + 1
                    VStack(spacing: Tokens.Space.none) {
                        ScrollView {
                            TerminalSplitLayoutView(
                                store: store,
                                tab: tab,
                                autoFocus: true,
                                topControlsInset: headerSafeInset,
                                onSelectTab: { store.selectTab($0, for: owner) }
                            )
                            .id(tab.id)
                            .frame(
                                width: proxy.size.width,
                                height: max(0, proxy.size.height - tabBarTotalHeight)
                            )
                        }
                        .scrollDisabled(true)
                        .scrollIndicators(.hidden)
                        .scrollEdgeEffectStyle(.soft, for: .top)
                        .ignoresSafeArea(.container, edges: .top)

                        SettingsDivider()
                        TerminalTabBarView(
                            store: store,
                            tabs: tabs,
                            activeTabId: tab.id,
                            addTabLabel: Copy.terminalAddTabIn(folder: abbreviatedTerminalPath(tab.workingDirectory)),
                            onSelectTab: { store.selectTab($0, for: owner) },
                            onAddTab: {
                                _ = store.openTab(for: owner, workingDirectory: tab.workingDirectory)
                            },
                            onCloseTab: { id in
                                Task { _ = await store.closeTab(id: id) }
                            },
                            onCloseOtherTabs: { keepingId in
                                Task { _ = await store.closeOtherTabs(except: keepingId, for: owner) }
                            }
                        )
                    }
                    .background {
                        if store.appearanceProfile.isSurfaceTranslucent == false {
                            Color(store.appearanceProfile.background)
                                .ignoresSafeArea(.container, edges: .top)
                        }
                    }
                }
                .ignoresSafeArea(.container, edges: .top)
                .toolbar { toolbar }
            } else {
                EmptyStateView(
                    state: .noTerminals,
                    action: (Copy.terminalNewSession(), newTerminal),
                    actionIcon: .plus,
                    actionStyle: .accentGlass
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { headerSafeInset = $0 }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            AccentGlassPillButton(title: Copy.terminalNewButton(), icon: .plus, action: newTerminal)
                .padding(.trailing, Tokens.Space.s10)
                .help(Copy.terminalNewHelp())
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
