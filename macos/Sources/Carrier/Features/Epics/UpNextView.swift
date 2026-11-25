import CarrierCore
import CarrierUI
import SwiftUI

/// The Carrier home's Up next section; a thin mapping of `upNext(_:)`. The epics are the Running ones that have not started, so the
/// rows look alike: the icon is the waiting circle, still. Clicking a row opens the epic.
struct UpNextView: View {
    let snapshot: PanelSnapshot
    @Binding var selection: Selection

    var body: some View {
        let rows = upNext(snapshot)
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            OverviewTitle(title: Copy.epicsStateUpNext(), detail: "\(rows.count)")
            OverviewCard {
                ForEach(rows.indices, id: \.self) { index in
                    OverviewLinkRow(action: { selection = rows[index].selection }) {
                        StateGlyph(state: .waiting).frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: Tokens.Space.s1) {
                            Text(rows[index].title).fontWeight(.semibold).lineLimit(1)
                            Text(rows[index].line).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                    }
                }
            }
        }
    }
}
