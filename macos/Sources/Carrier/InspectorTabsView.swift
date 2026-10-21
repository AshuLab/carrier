import CarrierCore
import SwiftUI

/// The right panel: small tabs with a short count each and the chosen tab's content. The choice is the person's until they
/// pick another, whatever the epic; without one the tab depends on the epic (`inspectorTab`).
struct InspectorTabsView: View {
    let subject: EpicSubject?
    let reply: EpicReply?
    @State private var chosen = InspectorStore().chosen

    var body: some View {
        let tab = inspectorTab(subject, chosen: chosen)
        let review = inspectorCount(.review, subject, reply: reply)
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: Binding(get: { tab }, set: { chosen = $0; InspectorStore().chosen = $0 })) {
                ForEach(InspectorTab.allCases, id: \.self) { item in
                    let count = inspectorCount(item, subject, reply: reply).text
                    Text(count.map { "\(item.title) \($0)" } ?? item.title).tag(item)
                }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            // a native segment cannot colour its own count: the control turns orange while a person is needed
            .tint(review.needsYou ? .orange : nil)
            // placeholders until the tabs' own slices land
            Text(tab.title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
