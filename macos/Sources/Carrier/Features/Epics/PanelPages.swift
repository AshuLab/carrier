import AppKit
import CarrierCore
import SwiftUI

struct Running: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        switch selection {
        case .carrier:
            Overview(snapshot: snapshot, selection: $selection)
        case .epic(let repo, let issue):
            // not in the snapshot (any more)
            Text("\(repo) #\(issue)")
        case .home, .sessions, .session, .newSession, .terminals, .terminal, .archive, .usage:
            EmptyView()  // PanelView shows these pages
        }
    }
}

struct Overview: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        YourTurnView(snapshot: snapshot, selection: $selection)
        RunningView(snapshot: snapshot, selection: $selection)
        if snapshot.queue.isEmpty == false { UpNextView(snapshot: snapshot, selection: $selection) }
        WatchedReposView(snapshot: snapshot)
    }
}
