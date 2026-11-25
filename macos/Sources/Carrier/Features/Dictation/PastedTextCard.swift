import CarrierCore
import SwiftUI

/// A long text pasted into the chat, as a card of glass in the family of the attached files: a badge, "Pasted text" over what it holds (its
/// characters, lines and tokens), Expand to read it where it is (a scroll of at most 220 points) and a × while the pointer is over it when it
/// can be taken out. In the box it waits for the message and, opened, can be edited (`edit`; the numbers follow what is typed); under a sent
/// bubble it is the same card to read, without the ×.
struct PastedTextCard: View {
    let text: String
    /// Worked out by whoever edits the text, once per edit; without it the card works it out at each draw.
    var summary: PasteSummary?
    var edit: ((String) -> Void)?
    var remove: (() -> Void)?
    @State private var open = false
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summary = summary ?? PasteSummary(text)
        VStack(alignment: .leading, spacing: Tokens.Space.none) {
            HStack(spacing: Tokens.Space.s10) {
                Glyph(.fileText, size: 15, bold: true).foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Color(Tokens.Attachment.log))
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.tile))
                    .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.tile).strokeBorder(.white.opacity(0.16), lineWidth: 0.5))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Tokens.Space.none) {
                    Text(Copy.dictationPastedText()).scaledFont(12.5, weight: .semibold).lineLimit(1)
                    Text(summary.stats).scaledFont(11).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                Button { toggle() } label: { Label(open ? Copy.dictationCollapse() : Copy.dictationExpand(), icon: open ? .chevronUp : .chevronDown) }
                    .buttonStyle(HoverTextButtonStyle(tint: nil))
                if let remove {
                    Button(action: remove) {
                        Glyph(.close, size: 9).foregroundStyle(.secondary)
                            .frame(width: 18, height: 18).background(Circle().fill(Color.primary.opacity(0.14))).contentShape(Circle())
                    }
                    .buttonStyle(.plain).help(Copy.dictationTakeItOut()).accessibilityLabel(Copy.dictationRemovePasted())
                    .opacity(hovering ? 1 : 0)
                }
            }
            .padding(.leading, Tokens.Space.s5).padding(.trailing, Tokens.Space.s8).padding(.vertical, Tokens.Space.s5)
            if open {
                Group {
                    if let edit {
                        TextEditor(text: Binding(get: { text }, set: edit))
                            .scaledFont(11.5, design: .monospaced).scrollContentBackground(.hidden).padding(Tokens.Space.s6)
                            .frame(height: min(220, max(90, CGFloat(summary.lines) * 17 + 24)))
                            .accessibilityLabel(Copy.dictationPastedText())
                    } else {
                        ScrollView {
                            Text(text).scaledFont(11.5, design: .monospaced).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(Tokens.Space.s10)
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .background(RoundedRectangle(cornerRadius: Tokens.Radius.tile).fill(Color.primary.opacity(0.06)))
                .padding(.horizontal, Tokens.Space.s6).padding(.bottom, Tokens.Space.s6)
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
        .chatSurface(in: RoundedRectangle(cornerRadius: Tokens.Radius.card))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { open.toggle() }
    }
}
