import CarrierCore
import SwiftUI

extension MessageBox {
    /// The list of commands the typed name leads to, over the text, a section for each kind: the one Enter takes is marked, and a click
    /// takes any. The rows reach out past the text on each side so their icons line up with it.
    var commandList: some View {
        let indexed = Array(matches.enumerated())
        return ScrollViewReader { proxy in
            ScrollView {
                // each section's title stays at the top while its rows scroll under it
                LazyVStack(alignment: .leading, spacing: Tokens.Space.xs, pinnedViews: .sectionHeaders) {
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
                .padding(.bottom, Tokens.Space.hair)
            }
            .frame(maxHeight: 280).fixedSize(horizontal: false, vertical: true)
            .onChange(of: highlighted) { _, index in
                if matches.indices.contains(index) { proxy.scrollTo(matches[index].id) }
            }
        }
        .padding(.horizontal, -Tokens.Space.sm)
    }

    /// A small glass capsule with the kind's icon in its colour and its name and count in the text's own, which read on the glass where
    /// the colour alone does not. It has no bar behind it: the rows that scroll under it show around it.
    func sectionHeader(_ kind: ChatCommand.Kind, count: Int) -> some View {
        HStack(spacing: Tokens.Space.none) {
            HStack(spacing: Tokens.Space.tight) {
                Glyph(kind.symbol, size: 11).foregroundStyle(kind.color)
                Text(kind.plural).font(.scaled(12, weight: .semibold))
                Text("\(count)").font(.scaled(11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, Tokens.Space.snug).frame(height: 24)
            .chatSurface(flat: Color.primary.opacity(0.08), in: Capsule())
            Spacer(minLength: 0)
        }
        .padding(.leading, Tokens.Space.tight).padding(.top, Tokens.Space.tight).padding(.bottom, Tokens.Space.xs)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }

    /// Its icon in the colour of its kind; the name, quiet in the plugin it belongs to and what it takes after it; its description under.
    func row(_ command: ChatCommand, marked: Bool) -> some View {
        HoverRow(action: { take(command) }, fill: marked ? Color.primary.opacity(0.1) : nil) { _ in
            HStack(spacing: Tokens.Space.snug) {
                Glyph(command.kind.symbol, size: 13).foregroundStyle(command.kind.color)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: Tokens.Radius.snug).fill(command.kind.color.opacity(marked ? 0.24 : 0.14)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.tight) {
                        Text("\(Text("/\(command.source.map { "\($0):" } ?? "")").foregroundStyle(.secondary))\(Text(command.shortName))")
                            .font(.scaled(13, weight: .medium, design: .monospaced)).lineLimit(1)
                        if let hint = command.argumentHint, hint.isEmpty == false {
                            Text(hint).font(.scaled(12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Text(command.summary).font(.scaled(12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, Tokens.Space.snug).padding(.vertical, Tokens.Space.sm)
        }
        .id(command.id)
    }
}
