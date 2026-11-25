import AppKit
import CarrierCore
import SwiftUI

/// The terminals the panel opens and closes: the standalone ones, a session's drawer and an epic's Continue in Terminal.
extension PanelView {
    func createNewTerminal() {
        let terminalId = terminalStore.createStandaloneTerminal(workingDirectory: NSHomeDirectory())
        model.shell.selection = .terminal(id: terminalId)
    }

    func closeStandaloneTerminal(_ id: UUID) {
        Task {
            guard await terminalStore.closeAll(for: .terminal(id)) else { return }
            reconcileSelectedTerminal()
        }
    }

    func reconcileSelectedTerminal() {
        guard case .terminal(let currentId) = model.shell.selection else { return }
        guard terminalStore.standaloneTerminal(id: currentId) == nil else { return }
        if let nextId = terminalStore.standaloneTerminals().first?.id {
            model.shell.selection = .terminal(id: nextId)
        } else {
            model.shell.selection = .terminals
        }
    }

    func setDrawerOpen(_ open: Bool, for owner: TerminalOwner) {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            model.shell.setTerminalDrawerOpen(open, for: owner)
        }
    }

    func toggleSessionTerminal(for session: SessionRow) {
        let owner = TerminalOwner.session(session.id)
        if model.shell.isTerminalDrawerOpen(for: owner) == false,
           terminalStore.tabs(for: owner).isEmpty {
            _ = terminalStore.openTab(for: owner, workingDirectory: session.folder)
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.25)) {
            model.shell.toggleTerminalDrawer(for: owner)
        }
    }

    /// Launches or focuses a validated epic Continue-in-Terminal session inside the epic's integrated bottom drawer.
    func continueEpicInTerminal(epic: EpicRef, section: SessionSection, resume: ValidResume) {
        let launch = embeddedResumeLaunch(resume)
        guard isAccessibleTerminalDirectory(launch.workingDirectory) else {
            NSLog("Carrier: continue in terminal refused because folder is inaccessible: %@", launch.workingDirectory)
            tell(Copy.epicsTerminalFolderGone())
            return
        }
        let owner = TerminalOwner.epic(repo: epic.repo, issue: epic.issue)
        if let existingTab = terminalStore.tabs(for: owner).first(where: { tab in
            tab.orderedPanes.contains { $0.command == launch.command }
        }) {
            terminalStore.selectTab(existingTab.id, for: owner)
            setDrawerOpen(true, for: owner)
            if let matchingPaneId = existingTab.orderedPanes.first(where: { $0.command == launch.command })?.id {
                terminalStore.selectPane(matchingPaneId)
                terminalStore.focus(paneId: matchingPaneId)
            }
            return
        }
        let tab = terminalStore.openTab(
            for: owner,
            workingDirectory: launch.workingDirectory,
            command: launch.command,
            title: "\(section.agent) · \(section.role)",
            activate: true
        )
        setDrawerOpen(true, for: owner)
        terminalStore.focus(paneId: tab.activePaneId)
    }

    /// Bottom terminal drawer target for the currently selected chat session or epic, if any.
    var activeDrawerTarget: (owner: TerminalOwner, defaultDirectory: String, isSessionDrawer: Bool)? {
        if case .session(let id) = model.shell.selection, let session = openSession {
            return (.session(id), session.folder, true)
        }
        if let epic {
            let owner = TerminalOwner.epic(repo: epic.subject.repo, issue: epic.subject.issue)
            let directory = terminalStore.activeTab(for: owner)?.workingDirectory ?? NSHomeDirectory()
            return (owner, directory, false)
        }
        return nil
    }
}
