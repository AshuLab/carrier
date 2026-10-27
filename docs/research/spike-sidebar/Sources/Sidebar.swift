import SwiftUI

// The prototype of the sidebar of docs/specs/sidebar-home-sessions-carrier.md, built inside the native `List(.sidebar)`.
// Self-contained on purpose (SwiftUI only, every type prefixed Spike) so the same file can be dropped into the app's window.

enum SpikeSelection: Hashable {
    case home, sessions, session(String), archive, carrier, epic(Int), settings
}

enum SpikeOpen { case sessions, carrier }

@Observable final class SpikeModel {
    var selection: SpikeSelection = .home
    var open: SpikeOpen? = .sessions
    var searchOpen = false
    var sortPopover = false
    var plusPopover = false
    var query = ""
    /// What the buttons did, in order: the probe reads it, nobody else does.
    var log: [String] = []

    func select(_ next: SpikeSelection) {
        selection = next
        switch next {
        case .sessions, .session: open = .sessions
        case .carrier, .epic: open = .carrier
        case .home, .archive, .settings: break
        }
    }
}

struct SpikeSidebar: View {
    @Bindable var model: SpikeModel
    /// "row": the Sessions row is a selectable list row and its sessions are rows after it. "section": a `Section(isExpanded:)`
    /// whose header holds the buttons.
    var variant = "row"

    var body: some View {
        let selection = Binding<SpikeSelection?>(get: { model.selection }, set: { if let next = $0 { model.select(next) } })
        List(selection: selection) {
            Label("Home", systemImage: "house").tag(SpikeSelection.home)
            if variant == "section" { sessionsSection } else { sessionsRows }
            Label("Archive", systemImage: "archivebox").badge(2).tag(SpikeSelection.archive)
            carrierRows
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 220, ideal: 268, max: 320)
        .safeAreaInset(edge: .bottom) {
            SpikeFooterRow(title: "Settings", icon: "gearshape", selected: model.selection == .settings) { model.select(.settings) }
                .padding(.horizontal, 10).padding(.vertical, 10)
        }
    }

    private static let sessions = [("a", "Fix the login redirect"), ("b", "Plan the release notes"), ("c", "Why is CI red")]

    // MARK: Sessions as a row

    @ViewBuilder private var sessionsRows: some View {
        HStack(spacing: 6) {
            SpikeIconButton(name: "Fold sessions", icon: model.open == .sessions ? "chevron.down" : "chevron.right") {
                model.open = model.open == .sessions ? nil : .sessions
                model.log.append("fold")
            }
            Text("Sessions").fontWeight(.semibold)
            Spacer(minLength: 0)
            sessionButtons
        }
        .contentShape(Rectangle())
        .tag(SpikeSelection.sessions)
        if model.open == .sessions {
            ForEach(Self.sessions, id: \.0) { Label($0.1, systemImage: "bubble.left").lineLimit(1).tag(SpikeSelection.session($0.0)) }
        }
    }

    // MARK: Sessions as a Section

    @ViewBuilder private var sessionsSection: some View {
        let expanded = Binding(get: { model.open == .sessions }, set: { model.open = $0 ? .sessions : nil })
        Section(isExpanded: expanded) {
            ForEach(Self.sessions, id: \.0) { Label($0.1, systemImage: "bubble.left").lineLimit(1).tag(SpikeSelection.session($0.0)) }
        } header: {
            HStack(spacing: 6) {
                Text("Sessions").fontWeight(.semibold)
                Spacer(minLength: 0)
                sessionButtons
            }
            .contentShape(Rectangle())
            .onTapGesture { model.log.append("header tap"); model.select(.sessions) }
        }
    }

    private var sessionButtons: some View {
        HStack(spacing: 2) {
            SpikeIconButton(name: "Search sessions", icon: "magnifyingglass") { model.searchOpen.toggle(); model.log.append("search") }
            SpikeIconButton(name: "Sort sessions", icon: "ellipsis") { model.sortPopover = true; model.log.append("sort") }
                .popover(isPresented: $model.sortPopover, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sort by").font(.caption).foregroundStyle(.secondary)
                        Text("Workspace"); Text("Age"); Text("Status")
                    }
                    .padding(12)
                }
            SpikeIconButton(name: "New session", icon: "plus") { model.plusPopover = true; model.log.append("plus") }
                .popover(isPresented: $model.plusPopover, arrowEdge: .trailing) { Text("No sessions yet").padding(12) }
        }
    }

    // MARK: The Carrier card and its list

    @ViewBuilder private var carrierRows: some View {
        SpikeCard(open: model.open == .carrier, selected: model.selection == .carrier)
            .tag(SpikeSelection.carrier)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 6, bottom: 4, trailing: 6))
        if model.open == .carrier {
            ForEach([(1, "Add retries to the poller"), (2, "Rename the sidebar rows"), (3, "Fix the footer")], id: \.0) {
                Label($0.1, systemImage: "circle.dotted").lineLimit(1).tag(SpikeSelection.epic($0.0))
            }
        }
    }
}

/// An icon button that does not select the row it sits in: a plain button with its own hit area and name.
struct SpikeIconButton: View {
    let name: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
    }
}

struct SpikeCard: View {
    let open: Bool
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(.green).frame(width: 8, height: 8)
                Text("Carrier").fontWeight(.semibold)
                Text("Running").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
            }
            // the summary: slots as bars and the counters; shown folded, the epics take its place when open
            if open == false {
                HStack(spacing: 3) { ForEach(0..<4) { Capsule().fill($0 < 2 ? Color.green : Color.secondary.opacity(0.3)).frame(height: 4) } }
                Text("1 needs you · 2 running · 3 next · 4 ready").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(selected ? 0.22 : 0.1)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SpikeFooterRow: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(selected ? 0.12 : 0)))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

struct SpikeDetail: View {
    let model: SpikeModel
    var body: some View { Text("\(String(describing: model.selection))").font(.title2).frame(maxWidth: .infinity, maxHeight: .infinity) }
}
