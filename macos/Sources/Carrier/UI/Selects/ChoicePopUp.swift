import SwiftUI

/// `SelectMenu` over a value: the choices as (value, title) pairs, the one chosen bound as the value itself. A stored value that is not on the
/// list shows the first choice, as the pages already read an unknown value as their default.
struct ChoicePopUp<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        SelectMenu(
            items: options.map(\.title),
            selection: Binding(
                get: { options.firstIndex { $0.value == selection } ?? 0 },
                set: { selection = options[$0].value }
            )
        )
        .accessibilityLabel(label)
    }
}
