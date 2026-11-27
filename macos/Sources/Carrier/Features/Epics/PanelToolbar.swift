import AppKit
import CarrierCore
import CarrierUI
import SwiftUI

/// The window's toolbar, which changes with the page: the epic's links and inspector, a session's header and terminal, Usage's check, Carrier's controls.
extension PanelView {
    @ToolbarContentBuilder var panelToolbar: some ToolbarContent {
        let shell = model.shell
        ToolbarItem(placement: .navigation) {
            Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleSidebar() } } label: { Label(Copy.epicsToolbarSidebar(), systemIcon: .sidebar) }
                .help(Copy.epicsToolbarSidebarHelp())
        }
        // a subagent view has its own ‹ Back, one level up, in the same place: two with the same name would be one too many
        if shell.subagentHeader == nil {
            ToolbarItemGroup(placement: .navigation) {
                Button { shell.goBack() } label: { Label(Copy.epicsToolbarBack(), systemIcon: .chevronLeft) }
                    .disabled(shell.history.canGoBack == false).help(Copy.epicsToolbarBack())
                Button { shell.goForward() } label: { Label(Copy.epicsToolbarForward(), systemIcon: .chevronRight) }
                    .disabled(shell.history.canGoForward == false).help(Copy.epicsToolbarForward())
            }
        }
        if let epic {
            if let open = shell.subagentHeader {
                // a slice card's subagent view wears the same header as a conversation's, with the epic in its subtitle and no Stop
                ToolbarItem(placement: .navigation) {
                    Button { shell.leaveSubagent() } label: { Label(Copy.epicsToolbarBack(), systemIcon: .chevronLeft) }
                        .help(Copy.epicsToolbarBackToOutput())
                }
                ToolbarItem(placement: .navigation) {
                    SubagentTitle(title: open.title, subtitle: open.subtitle(of: epic.header.title))
                        .frame(maxWidth: windowSize.width * 0.35, alignment: .leading)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) { SubagentStatePill(header: open) }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) { EpicLinks(prURL: epic.header.prURL, issueURL: epic.header.issueURL) }
                    .sharedBackgroundVisibility(.hidden)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleInspector() } } label: { Label(Copy.epicsToolbarInspector(), systemIcon: .sidebarRight) }
                    .help(Copy.epicsToolbarInspectorHelp())
            }
            if shell.inspectorShown {
                // The toolbar is the window's, so its right end is over the panel, which runs up behind the title bar. An empty item
                // as wide as the panel at that end keeps the buttons on the centre's side of it.
                ToolbarItem(placement: .primaryAction) { Color.clear.frame(width: Self.inspectorWidth, height: 1) }
                    .sharedBackgroundVisibility(.hidden)
            }
        }
        if let session = openSession {
            let drawerOpen = shell.isTerminalDrawerOpen(for: .session(session.id))
            if let open = shell.subagentHeader {
                // a subagent view wears the window's header: Back next to the sidebar's button, its title, the Subagents button, its state and Stop
                ToolbarItem(placement: .navigation) {
                    Button { shell.leaveSubagent() } label: { Label(Copy.epicsToolbarBack(), systemIcon: .chevronLeft) }
                        .help(shell.subagents.count > 1 ? Copy.epicsToolbarBackToSubagent() : Copy.epicsToolbarBackToConversation())
                }
                ToolbarItem(placement: .navigation) {
                    SubagentTitle(title: open.title, subtitle: open.subtitle(of: conversationTitle(session)))
                        .frame(maxWidth: windowSize.width * 0.35, alignment: .leading)
                }
                .sharedBackgroundVisibility(.hidden)
                if shell.subagentsList.buttonState != .hidden {
                    ToolbarItem(placement: .primaryAction) { subagentsToolbarButton(shell) }
                        .sharedBackgroundVisibility(.hidden)
                }
                ToolbarItem(placement: .primaryAction) { SubagentStatePill(header: open) }
                    .sharedBackgroundVisibility(.hidden)
                if open.canStop {
                    ToolbarItem(placement: .primaryAction) {
                        ToolbarPillButton(title: Copy.epicsToolbarStop(), icon: .stopFilled, iconTint: .red) { shell.perform(.conversation(.stopSubagent)) }
                            .glassEffect(.regular, in: .capsule)
                            .help(Copy.epicsToolbarStopSubagentHelp())
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            } else {
                ToolbarItem(placement: .primaryAction) { SessionPlacePill(row: session) }
                    .sharedBackgroundVisibility(.hidden)
                if shell.subagentsList.buttonState != .hidden {
                    ToolbarItem(placement: .primaryAction) { subagentsToolbarButton(shell) }
                        .sharedBackgroundVisibility(.hidden)
                }
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                ToolbarGlassIconButton(icon: .terminal, active: drawerOpen, name: drawerOpen ? Copy.epicsToolbarHideTerminal() : Copy.epicsToolbarOpenTerminal(path: abbreviatedTerminalPath(session.folder))) {
                    toggleSessionTerminal(for: session)
                }
                .glassEffect(.regular, in: .capsule)
                .padding(.trailing, Tokens.Space.s10)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if shell.selection == .usage {
            ToolbarItem(placement: .primaryAction) {
                CheckAgainButton(skin: .toolbar, checking: AppUsage.store.isRefreshing, failed: AppUsage.store.error != nil) { AppUsage.refresher.checkAgain() }
                    .glassEffect(.regular, in: .capsule)
                    .padding(.trailing, Tokens.Space.s10)
                    .help(Copy.epicsToolbarCheckUsageHelp())
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if let snapshot, shell.selection == .carrier {
            // two glass pills: the check against GitHub, then what governs Carrier itself (intake and stopping)
            ToolbarItem(placement: .primaryAction) {
                // the engine polls on its own after the answer: the button says so until the next check is scheduled again
                let checking = isChecking(snapshot, asked: checkAsked, now: Date())
                CheckAgainButton(skin: .toolbar, title: Copy.epicsToolbarCheckNow(), checking: checking) {
                    checkAsked = CheckAsked(at: Date(), nextCheckAt: snapshot.nextCheckAt)
                    MenuControls.shared.checkNow()
                }
                .glassEffect(.regular, in: .capsule)
                .help(checking ? Copy.epicsToolbarChecking() : Copy.epicsToolbarCheckGithub())
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Tokens.Space.none) {
                    ToolbarPillButton(title: snapshot.paused ? Copy.lifecycleIntakeResume() : Copy.lifecycleIntakePause(), icon: snapshot.paused ? .playFilled : .pauseFilled) { MenuControls.shared.pauseOrResume() }
                        .help(snapshot.paused ? Copy.epicsToolbarResumeIntake() : Copy.epicsToolbarPauseIntake())
                    ToolbarPillButton(title: Copy.epicsToolbarStop(), icon: .stopFilled, iconTint: .red) { MenuControls.shared.stopCarrier() }
                        .help(Copy.epicsToolbarStopCarrier())
                }
                .glassEffect(.regular, in: .capsule)
                .padding(.trailing, Tokens.Space.s10)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    private func subagentsToolbarButton(_ shell: WindowShell) -> some View {
        SubagentsButton(
            state: shell.subagentsList.buttonState,
            spoken: shell.subagentsList.buttonSpoken(),
            open: subagentsOpen
        ) {
            subagentsOpen.toggle()
        }
        .popover(isPresented: $subagentsOpen, arrowEdge: .bottom) {
            SubagentsListPopover(list: shell.subagentsList) { id in
                subagentsOpen = false
                shell.jumpToSubagent(id)
            }
        }
    }
}
