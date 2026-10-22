import CarrierCore
import SwiftUI

/// The right panel: small tabs with a short count each and the chosen tab's content. The choice is the person's until they
/// pick another, whatever the epic; without one the tab depends on the epic (`inspectorTab`).
struct InspectorTabsView: View {
    let subject: EpicSubject?
    let reply: EpicReply?
    @State private var chosen = InspectorStore().chosen
    @State private var reviewFolds = ReviewFolds()

    var body: some View {
        let tab = inspectorTab(subject, chosen: chosen)
        let review = inspectorCount(.review, subject, reply: reply)
        VStack(alignment: .leading, spacing: 12) {
            UnderlineTabs(
                items: InspectorTab.allCases.map { item in
                    UnderlineTabs.Item(
                        id: item, title: item.title, count: inspectorCount(item, subject, reply: reply).text,
                        countColor: item == .review && review.needsYou ? .orange : .secondary
                    )
                },
                selection: Binding(get: { tab }, set: { chosen = $0; InspectorStore().chosen = $0 }), fill: true
            )
            switch tab {
            case .slices: SlicesTabView(subject: subject, reply: reply)
            case .review:
                ScrollView {
                    ReviewTabView(epic: EpicRef(repo: subject?.repo ?? "", issue: subject?.issue ?? 0), model: reviewTab(subject, reply: reply), folds: $reviewFolds)
                }
            case .details: DetailsTabView(subject: subject, reply: reply)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
