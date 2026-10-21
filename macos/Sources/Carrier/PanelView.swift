import AppKit
import CarrierCore
import SwiftUI

struct PanelView: View {
    let model: PanelModel

    private var snapshot: PanelSnapshot? {
        if case .running(let snapshot)? = model.state { return snapshot }
        return nil
    }

    /// The selected epic when it is in the snapshot.
    private var epic: (subject: EpicSubject, header: EpicHeader, now: Int)? {
        guard case .epic(let repo, let issue) = model.shell.selection, let snapshot,
            let subject = snapshot.subject(repo: repo, issue: issue)
        else { return nil }
        return (subject, epicHeader(subject), snapshot.now)
    }

    var body: some View {
        @Bindable var shell = model.shell
        let groupBy = Binding(get: { model.groupBy }, set: { model.groupBy = $0; SidebarStore().groupBy = $0 })
        let columns = Binding<NavigationSplitViewVisibility>(
            get: { shell.sidebarShown ? .all : .detailOnly }, set: { shell.sidebarShown = $0 != .detailOnly }
        )
        NavigationSplitView(columnVisibility: columns) {
            SidebarView(snapshot: snapshot, selection: $shell.selection, groupBy: groupBy)
        } detail: {
            Group {
                if let epic {
                    EpicView(subject: epic.subject, reply: nil, filesChanged: 0, now: epic.now)
                        .id("\(epic.subject.repo)#\(epic.subject.issue)")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch model.state {
                            case nil:
                                Text("Connecting…").foregroundStyle(.secondary)
                            case .stopped?, .incompatible?:
                                // Carrier is not answering: nothing else to show
                                Label(model.state?.menuLine ?? "", systemImage: "stop.circle").font(.title3)
                                if model.state == .stopped { StartCarrierButton() }
                            case .running(let snapshot)?:
                                Running(snapshot: snapshot, selection: $shell.selection)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            }
            .navigationTitle(epic.map { "\($0.subject.repo.split(separator: "/").last ?? "") #\($0.subject.issue)" } ?? "Carrier")
            .inspector(isPresented: $shell.inspectorShown) {
                Text("Inspector").foregroundStyle(.secondary)
                    .inspectorColumnWidth(min: 280, ideal: 316, max: 400)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { shell.toggleSidebar() } label: { Label("Sidebar", systemImage: "sidebar.leading") }
                    .help("Show or hide the sidebar")
            }
            if let epic {
                ToolbarItemGroup(placement: .primaryAction) {
                    OpenLinkButton(title: "Open PR", url: epic.header.prURL)
                    OpenLinkButton(title: "Open issue", url: epic.header.issueURL)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { shell.toggleInspector() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
                    .help("Show or hide the inspector")
            }
        }
        .frame(minWidth: 980, minHeight: 600)
    }
}

private struct Running: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        switch selection {
        case .overview:
            Overview(snapshot: snapshot, selection: $selection)
        case .epic(let repo, let issue):
            // not in the snapshot (any more)
            Text("\(repo) #\(issue)")
        case .settings:
            Text("Settings").foregroundStyle(.secondary)
        case .about:
            Text("About Carrier").foregroundStyle(.secondary)
        }
    }
}

private struct Overview: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        YourTurnView(snapshot: snapshot, selection: $selection)
        CarrierBoxView(snapshot: snapshot)
        RunningView(snapshot: snapshot, selection: $selection)
        if snapshot.queue.isEmpty == false {
            PanelSection(title: "Queue \(snapshot.queue.count)") {
                ForEach(snapshot.queue, id: \.key) { Text("\($0.repo) #\($0.issue)") }
            }
        }
    }
}

private struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content
        }
    }
}

private extension PanelEpic { var key: String { "\(repo)#\(issue)" } }
private extension PanelSnapshot.QueuedEpic { var key: String { "\(repo)#\(issue)" } }
