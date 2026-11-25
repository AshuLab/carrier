import CarrierCore
import SwiftUI

/// A text field that hands its number to `value` as it is typed, so Save is on at once; text that is not a number yet is
/// reported through `unparsable` and the value keeps its last good number.
struct NumberField<Value: Equatable>: View {
    let key: String
    @Binding var value: Value
    @Binding var unparsable: Set<String>
    @Environment(\.settingsInvalid) private var invalid
    let parse: (String) -> Value?
    let format: (Value) -> String
    /// The value one click of − (-1) or + (1) moves to; nil when it would go below the least the engine takes.
    let step: (Value, Int) -> Value?
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Tokens.Space.none) {
            stepButton(.minus, -1)
            TextField("", text: $text).textFieldStyle(.plain).multilineTextAlignment(.center).frame(width: 42).focused($focused)
            stepButton(.plus, 1)
        }
        .padding(Tokens.Space.s2)
        .background(RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).fill(Color.primary.opacity(focused ? 0.09 : 0.07)))
        .overlay { if invalid { RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).strokeBorder(Color.orange, lineWidth: 1.5) } else if focused { RoundedRectangle(cornerRadius: Tokens.Radius.control, style: .continuous).strokeBorder(.tint, lineWidth: 1.5) } }
            .onAppear { text = format(value) }
            .onChange(of: text) {
                if let parsed = parse(text) {
                    unparsable.remove(key)
                    if parsed != value { value = parsed }
                } else {
                    unparsable.insert(key)
                }
            }
            // Revert, or a reload: show the value the draft now has, unless the text already means it
            .onChange(of: value) { if parse(text) != value { text = format(value) } }
            // Revert clears the mark: text that is still not a number goes back to the value
            .onChange(of: unparsable) { if unparsable.contains(key) == false, parse(text) == nil { text = format(value) } }
            .accessibilityLabel(key)
    }

    private func stepButton(_ symbol: AppIcon, _ direction: Int) -> some View {
        Button {
            guard let next = step(parse(text) ?? value, direction) else { return }
            unparsable.remove(key)
            value = next
            text = format(next)
        } label: {
            Glyph(symbol, size: 12).foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(direction < 0 ? Copy.pieceNumberLess() : Copy.pieceNumberMore())
    }
}
