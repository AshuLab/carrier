import CarrierCore
import SwiftUI

/// A long text pasted into the chat, as a card of glass in the family of the attached files: a badge, "Pasted text" over what it holds (its
/// characters, lines and tokens), Expand to read it where it is (a scroll of at most 220 points) and a × while the pointer is over it when it
/// can be taken out. In the box it waits for the message and, opened, can be edited (`edit`; the numbers follow what is typed); under a sent
/// bubble it is the same card to read, without the ×.
struct PastedTextCard: View {
    let text: String
    var edit: ((String) -> Void)?
    var remove: (() -> Void)?
    @State private var open = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "doc.text").font(.scaled(15, weight: .medium)).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(red: 0.42, green: 0.47, blue: 0.58))
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pasted text").font(.scaled(12.5, weight: .semibold)).lineLimit(1)
                    Text(pasteStats(text)).font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button { toggle() } label: { Label(open ? "Collapse" : "Expand", systemImage: open ? "chevron.up" : "chevron.down") }
                    .buttonStyle(HoverTextButtonStyle(tint: nil))
                if let remove {
                    Button(action: remove) {
                        Image(systemName: "xmark").font(.scaled(9, weight: .bold)).foregroundStyle(.secondary)
                            .frame(width: 18, height: 18).background(Circle().fill(Color.primary.opacity(0.14))).contentShape(Circle())
                    }
                    .buttonStyle(.plain).help("Take it out").accessibilityLabel("Remove the pasted text")
                    .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.leading, 5).padding(.trailing, 7).padding(.vertical, 5)
            if open {
                Group {
                    if let edit {
                        TextEditor(text: Binding(get: { text }, set: edit))
                            .font(.scaled(11.5, design: .monospaced)).scrollContentBackground(.hidden).padding(6)
                            .frame(height: min(220, max(90, CGFloat(text.split(separator: "\n", omittingEmptySubsequences: false).count) * 17 + 24)))
                            .accessibilityLabel("Pasted text")
                    } else {
                        ScrollView {
                            Text(text).font(.scaled(11.5, design: .monospaced)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, 6).padding(.bottom, 6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { open.toggle() }
    }
}
