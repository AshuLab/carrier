import AppKit
import CarrierCore
import SwiftUI

/// The window's toolbar, which changes with the page: the epic's links and inspector, a session's header and terminal, Usage's check, Carrier's controls.
extension PanelView {
    @ToolbarContentBuilder var panelToolbar: some ToolbarContent {
        let shell = model.shell
        ToolbarItem(placement: .navigation) {
            Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleSidebar() } } label: { Label("Sidebar", systemIcon: .sidebar) }
                .help("Show or hide the sidebar")
        }
        // a subagent view has its own ‹ Back, one level up, in the same place: two with the same name would be one too many
        if shell.subagentHeader == nil {
            ToolbarItemGroup(placement: .navigation) {
                Button { shell.goBack() } label: { Label("Back", systemIcon: .chevronLeft) }
                    .disabled(shell.history.canGoBack == false).help("Back")
                Button { shell.goForward() } label: { Label("Forward", systemIcon: .chevronRight) }
                    .disabled(shell.history.canGoForward == false).help("Forward")
            }
        }
        if let epic {
            if let open = shell.subagentHeader {
                // a slice card's subagent view wears the same header as a conversation's, with the epic in its subtitle and no Stop
                ToolbarItem(placement: .navigation) {
                    Button { shell.leaveSubagent() } label: { Label("Back", systemIcon: .chevronLeft) }
                        .help("Back to Agent output")
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
                Button { withAnimation(.smooth(duration: 0.25)) { shell.toggleInspector() } } label: { Label("Inspector", systemIcon: .sidebarRight) }
                    .help("Show or hide the inspector")
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
                // a subagent view wears the window's header: Back next to the sidebar's button, its title, and its state where the worktree pill is
                ToolbarItem(placement: .navigation) {
                    Button { shell.leaveSubagent() } label: { Label("Back", systemIcon: .chevronLeft) }
                        .help(shell.subagents.count > 1 ? "Back to the subagent that launched this one" : "Back to the conversation")
                }
                ToolbarItem(placement: .navigation) {
                    SubagentTitle(title: open.title, subtitle: open.subtitle(of: conversationTitle(session)))
                        .frame(maxWidth: windowSize.width * 0.35, alignment: .leading)
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .primaryAction) { SubagentStatePill(header: open) }
                    .sharedBackgroundVisibility(.hidden)
                if open.canStop {
                    ToolbarItem(placement: .primaryAction) {
                        ToolbarPillButton(title: "Stop", icon: .stopFilled, iconTint: .red) { shell.perform(.conversation(.stopSubagent)) }
                            .glassEffect(.regular, in: .capsule)
                            .help("Stop this subagent; the main agent goes on")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            } else {
                ToolbarItem(placement: .primaryAction) { SessionPlacePill(row: session) }
                    .sharedBackgroundVisibility(.hidden)
            }
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                ToolbarGlassIconButton(icon: .terminal, active: drawerOpen, name: drawerOpen ? "Hide terminal" : "Open terminal in \(abbreviatedTerminalPath(session.folder))") {
                    toggleSessionTerminal(for: session)
                }
                .glassEffect(.regular, in: .capsule)
                .padding(.trailing, Tokens.Space.snug)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if shell.selection == .usage {
            ToolbarItem(placement: .primaryAction) {
                CheckAgainButton(skin: .toolbar, checking: AppUsage.store.isRefreshing, failed: AppUsage.store.error != nil) { AppUsage.refresher.checkAgain() }
                    .glassEffect(.regular, in: .capsule)
                    .padding(.trailing, Tokens.Space.snug)
                    .help("Asks every provider again, skipping the minute the chat host keeps its answer")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        if let snapshot, shell.selection == .carrier {
            // two glass pills: the check against GitHub, then what governs Carrier itself (intake and stopping)
            ToolbarItem(placement: .primaryAction) {
                // the engine polls on its own after the answer: the button says so until the next check is scheduled again
                let checking = isChecking(snapshot, asked: checkAsked, now: Date())
                CheckAgainButton(skin: .toolbar, title: "Check now", checking: checking) {
                    checkAsked = CheckAsked(at: Date(), nextCheckAt: snapshot.nextCheckAt)
                    MenuControls.shared.checkNow()
                }
                .glassEffect(.regular, in: .capsule)
                .help(checking ? "Checking GitHub…" : "Check GitHub now")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarSpacer(.fixed, placement: .primaryAction)
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: Tokens.Space.none) {
                    ToolbarPillButton(title: snapshot.paused ? "Resume" : "Pause", icon: snapshot.paused ? .playFilled : .pauseFilled) { MenuControls.shared.pauseOrResume() }
                        .help(snapshot.paused ? "Resume intake" : "Pause intake")
                    ToolbarPillButton(title: "Stop", icon: .stopFilled, iconTint: .red) { MenuControls.shared.stopCarrier() }
                        .help("Stop Carrier")
                }
                .glassEffect(.regular, in: .capsule)
                .padding(.trailing, Tokens.Space.snug)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
