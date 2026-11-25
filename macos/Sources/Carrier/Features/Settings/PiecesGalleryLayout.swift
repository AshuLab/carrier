import CarrierCore
import CarrierUI
import SwiftUI

/// The Layout pieces of `CarrierUI/` in the states their catalog entries list.
struct PiecesGalleryLayout: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s22) {
            GalleryEntry("FlowLayout") {
                GalleryState(.normal) {
                    FlowLayout(spacing: Tokens.Space.s6) { ForEach(PiecesGalleryData.chips, id: \.self) { StatusChip(text: $0, tint: .blue) } }.frame(width: 220, alignment: .leading)
                }
            }
            GalleryEntry("EqualWidthRow") {
                GalleryState(.normal) {
                    EqualWidthRow {
                        Text(sample(.label)).frame(maxWidth: .infinity).background(Color.primary.opacity(0.08))
                        Text(sample(.title)).frame(maxWidth: .infinity).background(Color.primary.opacity(0.08))
                    }
                }
            }
            GalleryEntry("TickingTimeline", "MovingTimeline", "LookingSchedule") {
                GalleryState(.working) {
                    HStack(spacing: Tokens.Space.s24) {
                        TickingTimeline(every: 1) { context in Text(context.date, format: .dateTime.hour().minute().second()).monospacedDigit() }
                        MovingTimeline { context in
                            Circle().fill(.tint).frame(width: 10, height: 10).offset(x: 30 * sin(context.date.timeIntervalSinceReferenceDate * 2)).frame(width: 80)
                        }
                    }
                }
                GalleryState(.still) {
                    // nobody can see the window: the clock shows its first tick and stays
                    TickingTimeline(every: 1) { context in Text(context.date, format: .dateTime.hour().minute().second()).monospacedDigit() }
                        .environment(Viewing())
                }
            }
            GalleryEntry("SettingsDivider") {
                GalleryState(.normal) { SettingsDivider().frame(width: 160) }
                GalleryState(.plain) { SettingsDivider(vertical: true).frame(height: 40) }
            }
            GalleryEntry("SettingsPageBody", "SettingsPreview") {
                GalleryState(.normal) {
                    SettingsPageBody {
                        SettingsGroup(title: sample(.group)) {
                            SettingsTabRow(title: sample(.row), detail: sample(.rowDetail), first: true) { EmptyView() }
                            SettingsPreview { Text(sample(.detail)) }
                        }
                    }
                    .frame(width: 420)
                }
            }
            GalleryEntry("UnderlineTabs") {
                GalleryState(.normal) { TabsSample(fill: false, extras: false) }
                GalleryState(.withIcon) { TabsSample(fill: false, extras: true) }
                GalleryState(.large) { TabsSample(fill: true, extras: false).frame(width: 320) }
            }
        }
    }
}

private struct TabsSample: View {
    let fill: Bool
    let extras: Bool
    @State private var selection = 0

    var body: some View {
        UnderlineTabs(
            items: [
                .init(id: 0, title: sample(.label), icon: extras ? .code : nil, count: extras ? "3" : nil),
                .init(id: 1, title: sample(.title), icon: extras ? .clock : nil, count: extras ? "12" : nil, countColor: .orange),
            ], selection: $selection, fill: fill)
    }
}
