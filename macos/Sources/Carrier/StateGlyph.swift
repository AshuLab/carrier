import CarrierCore
import SwiftUI

/// The glyph of an epic's state, 20 points square as in the mockup: a turning ring while it runs, a filled orange disc with a
/// mark when it needs you (red when `attention` says it failed), a hollow grey circle while it waits and a filled blue disc with a
/// tick when it is ready.
struct StateGlyph: View {
    let state: EpicMenuState
    var attention: Attention?

    var body: some View {
        glyph.frame(width: 20, height: 20).accessibilityLabel(state.label)
    }

    @ViewBuilder private var glyph: some View {
        switch state {
        case .running: SpinningRing().overlay { StateMark(shape: .working, size: 8).foregroundStyle(.secondary) }
        case .needsYou: Disc(color: (attention ?? .input).color, mark: "!", shape: state.shape(attention: attention))
        case .waiting: Circle().strokeBorder(Color.gray, lineWidth: 2).frame(width: 14, height: 14)
        case .ready: Disc(color: .blue, mark: "✓", shape: .ready)
        case .done: Disc(color: .green, mark: "✓")
        case .cancelled: Disc(color: .gray, mark: "✕")
        }
    }
}

extension Attention {
    /// Red when something failed, orange when a person's input is needed (and for an epic whose kind is not known).
    var color: Color { self == .error ? .red : .orange }
}

struct Disc: View {
    let color: Color
    let mark: String
    var shape: StateShape?

    var body: some View {
        Circle().fill(color).frame(width: 18, height: 18)
            .overlay { StateMark(text: mark, shape: shape, size: 10).foregroundStyle(.white) }
    }
}

/// What a state wears inside its glyph: its text, or, with "Tell states apart by shape" on, the symbol of its shape. A state with
/// no shape, or no text with the setting off, draws nothing.
struct StateMark: View {
    var text = ""
    let shape: StateShape?
    let size: CGFloat
    var weight = Font.Weight.heavy
    @AppStorage(AppPreferences.statesByShapeKey) private var byShape = false

    @ViewBuilder var body: some View {
        if byShape, let shape {
            Image(systemName: stateSymbol(shape)).font(.scaled(size, weight: weight))
        } else if text.isEmpty == false {
            Text(text).font(.scaled(size, weight: weight))
        }
    }
}

extension EpicMenuState {
    var label: String {
        switch self {
        case .needsYou: "Needs attention"
        case .running: "Running"
        case .waiting: "Up next"
        case .ready: "Ready for test"
        case .done: "Done"
        case .cancelled: "Cancelled"
        }
    }
}
