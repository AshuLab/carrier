import CarrierCore
import SwiftUI

/// The message box of the draft and of an open session: a roomy text area with a hint and the send button, which is Stop while the
/// agent answers, and under it the selects of what the session runs with. Enter sends and Shift+Enter adds a line.
struct MessageBox<Selects: View>: View {
    @Binding var text: String
    var placeholder: String
    var minLines = 3
    var canSend: Bool
    var sendHelp = "Send"
    /// Whether the agent is answering: the button is Stop, and Enter still sends (the session holds the message until the turn ends).
    var busy = false
    /// Set to true to put the caret in the text.
    var focus: Binding<Bool>
    /// What the person can invoke by typing a slash and its name (skills and the provider's own commands); empty when there is none to list.
    var commands: [ChatCommand] = []
    /// Whether the selects get a darker, feathered patch behind them as wide as they are: over a conversation that scrolls under them.
    var halo = false
    var send: () -> Void
    var stop: () -> Void = {}
    @ViewBuilder var selects: () -> Selects
    /// Counts the sends, so the arrow bounces up each time one goes.
    @State private var sent = 0
    /// The row of the list of commands that Enter or Tab would take.
    @State private var highlighted = 0
    /// The word for which the list was closed with Escape: it opens again as soon as the word is another.
    @State private var closedFor: CommandToken?
    /// Where the caret is in the text.
    @State private var cursor = 0

    /// The word under the caret, while it is a slash and what is typed of a name.
    private var token: CommandToken? { commands.isEmpty ? nil : commandToken(in: text, cursor: cursor) }

    /// The commands that word leads to.
    private var matches: [ChatCommand] {
        guard let token, closedFor != token else { return [] }
        return commandMatches(commands, query: token.query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                if matches.isEmpty == false {
                    commandList
                    Divider()
                }
                CommandTextView(
                    text: $text, cursor: $cursor, focus: focus, placeholder: placeholder, minLines: minLines, commands: commands, onKey: handle
                )
                .onChange(of: text) { highlighted = 0 }
                HStack {
                    Spacer(minLength: 0)
                    button
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            // glass: the conversation that scrolls under the box is blurred, not seen through it
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            // what the session runs with, under the box and at its left, side by side at their own width; a row that wraps when a provider
            // lists more than fit
            FlowLayout(spacing: 8) {
                if commands.isEmpty == false { skillsButton }
                selects()
            }
                .padding(.leading, 4)
                .background {
                    // as wide as the selects and no wider, with soft edges: the text that scrolls under them goes dark, not the whole row
                    if halo {
                        RoundedRectangle(cornerRadius: 16).fill(Color(nsColor: .windowBackgroundColor).opacity(0.92))
                            .padding(-8).blur(radius: 7)
                    }
                }
        }
    }

    /// The keys of the text that mean something to the list while it is open; Enter takes the marked row, or sends.
    private func handle(_ key: CommandTextView.Key) -> Bool {
        let marked = matches.isEmpty ? nil : matches[min(highlighted, matches.count - 1)]
        switch key {
        case .send:
            if let marked { take(marked) } else { fire() }
        case .tab:
            guard let marked else { return false }
            take(marked)
        case .up:
            guard marked != nil else { return false }
            highlighted = max(0, highlighted - 1)
        case .down:
            guard marked != nil else { return false }
            highlighted = min(matches.count - 1, highlighted + 1)
        case .escape:
            guard marked != nil else { return false }
            closedFor = token
        }
        return true
    }

    /// The list of commands the typed name leads to, over the text, a section for each kind: the one Enter takes is marked, and a click
    /// takes any. The rows reach out past the text on each side so their icons line up with it.
    private var commandList: some View {
        let indexed = Array(matches.enumerated())
        return ScrollViewReader { proxy in
            ScrollView {
                // each section's title stays at the top while its rows scroll under it
                LazyVStack(alignment: .leading, spacing: 3, pinnedViews: .sectionHeaders) {
                    ForEach(ChatCommand.Kind.allCases, id: \.self) { kind in
                        let group = indexed.filter { $0.element.kind == kind }
                        if group.isEmpty == false {
                            Section {
                                ForEach(group, id: \.element.id) { index, command in row(command, marked: index == highlighted) }
                            } header: {
                                sectionHeader(kind, count: group.count)
                            }
                        }
                    }
                }
                .padding(.bottom, 2)
            }
            .frame(maxHeight: 280).fixedSize(horizontal: false, vertical: true)
            .onChange(of: highlighted) { _, index in
                if matches.indices.contains(index) { proxy.scrollTo(matches[index].id) }
            }
        }
        .padding(.horizontal, -8)
    }

    /// A small glass capsule with the kind's icon in its colour and its name and count in the text's own, which read on the glass where
    /// the colour alone does not. It has no bar behind it: the rows that scroll under it show around it.
    private func sectionHeader(_ kind: ChatCommand.Kind, count: Int) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: kind.symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(kind.color)
                Text(kind.plural).font(.system(size: 12, weight: .semibold))
                Text("\(count)").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 24)
            .glassEffect(.regular, in: .capsule)
            Spacer(minLength: 0)
        }
        .padding(.leading, 6).padding(.top, 6).padding(.bottom, 4)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }

    /// Its icon in the colour of its kind; the name, quiet in the plugin it belongs to and what it takes after it; its description under.
    private func row(_ command: ChatCommand, marked: Bool) -> some View {
        HoverRow(action: { take(command) }, fill: marked ? Color.primary.opacity(0.1) : nil) { _ in
            HStack(spacing: 10) {
                Image(systemName: command.kind.symbol)
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(command.kind.color)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(command.kind.color.opacity(marked ? 0.24 : 0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Text("/\(command.source.map { "\($0):" } ?? "")").foregroundStyle(.secondary))\(Text(command.shortName))")
                            .font(.system(size: 13, weight: .medium, design: .monospaced)).lineLimit(1)
                        if let hint = command.argumentHint, hint.isEmpty == false {
                            Text(hint).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Text(command.summary).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .id(command.id)
    }

    /// A chosen command goes into the text in place of the word being typed, ready for what follows it.
    private func take(_ command: ChatCommand) {
        guard let token else { return }
        let taken = inserting(command, over: token, in: text)
        text = taken.text
        cursor = taken.cursor
        focus.wrappedValue = true
    }

    /// Opens the list for a person who does not know that a slash does.
    private var skillsButton: some View {
        Button {
            let appended = appendingSlash(to: text)
            text = appended.text
            cursor = appended.cursor
            closedFor = nil
            focus.wrappedValue = true
        } label: {
            Label("Skills", systemImage: "slash.circle").font(.callout).fontWeight(.medium)
                .padding(.horizontal, 10).frame(height: controlHeight).controlSurface().contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).help("Skills and commands: type a slash")
    }

    /// Enter and the button: sends, and makes the arrow bounce when there is something to send.
    private func fire() {
        if canSend || busy { sent += 1 }
        send()
    }

    /// A round glass button of the system's, tinted when there is something to send and plain when there is not; it gives under the finger
    /// and springs back. The arrow becomes the Stop square while the agent answers, bounces up on a send and pulses while it works.
    @ViewBuilder private var button: some View {
        let active = canSend || busy
        let action = busy ? stop : fire
        let label = Image(systemName: busy ? "stop.fill" : "arrow.up")
            .font(.system(size: busy ? 12 : 14, weight: .bold)).foregroundStyle(active ? .white : .secondary)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.bounce.up, value: sent)
            .symbolEffect(.pulse, isActive: busy)
            .frame(width: 20, height: 20)
        Group {
            if active {
                Button(action: action) { label }.buttonStyle(.glassProminent)
            } else {
                Button(action: action) { label }.buttonStyle(.glass).disabled(true)
            }
        }
        // a circle by construction: the system's border shape, over a label that is square
        .buttonBorderShape(.circle).controlSize(.large).tint(.accentColor)
        .animation(.smooth(duration: 0.25), value: active)
        .help(busy ? "Stop" : "\(sendHelp) (↩) · New line (⇧↩)").accessibilityLabel(busy ? "Stop" : "Send")
    }
}
