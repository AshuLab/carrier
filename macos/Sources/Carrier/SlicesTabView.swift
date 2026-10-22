import CarrierCore
import SwiftUI

extension SliceGroup {
    /// The mockup's: merged green, in progress blue, waiting the grey of the track.
    var color: Color {
        switch self {
        case .merged: .green
        case .inProgress: .blue
        case .waiting: Color.secondary.opacity(0.45)
        }
    }
}

/// One arc of the ring, stroked with round caps by the view. A custom shape because the chart framework gives rounded corners,
/// not round caps with a gap (docs/research/macos-app-swiftui.md, question 4).
struct SlicesRingArcShape: Shape {
    let arc: RingArc

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
            startAngle: .degrees(-90 + arc.start * 360), endAngle: .degrees(-90 + arc.end * 360), clockwise: false
        )
        return path
    }
}

/// The track, then merged and in progress on it; waiting is the bare track. The count and its caption sit in the middle.
struct SlicesRing: View {
    let counts: [Int]
    let centre: String
    let caption: String
    static let size = 120.0
    static let lineWidth = 11.0

    var body: some View {
        let radius = (Self.size - Self.lineWidth) / 2
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: Self.lineWidth)
            ForEach(ringArcs(counts, radius: radius, lineWidth: Self.lineWidth, gap: 3), id: \.group) { arc in
                if arc.group != SliceGroup.allCases.firstIndex(of: .waiting) {
                    SlicesRingArcShape(arc: arc)
                        .stroke(SliceGroup.allCases[arc.group].color, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: arc.full ? .butt : .round))
                }
            }
            VStack(spacing: 0) {
                Text(centre).font(.system(size: 24, weight: .bold)).monospacedDigit()
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(Self.lineWidth / 2)
        .frame(width: Self.size, height: Self.size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(centre) slices, \(caption)")
    }
}

/// The Slices tab: ring, legend that selects a group, and that group's list.
struct SlicesTabView: View {
    let subject: EpicSubject?
    let reply: EpicReply?
    @State private var chosen: SliceGroup?

    var body: some View {
        let model = slicesTabModel(subject, reply: reply, chosen: chosen, now: Int(Date().timeIntervalSince1970 * 1000))
        if model.isEmpty {
            EmptyStateView(state: .noSlices)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SlicesRing(counts: model.counts, centre: model.centre, caption: model.caption)
                        .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 22)
                    ForEach(model.legend, id: \.group) { entry in
                        Button { chosen = entry.group } label: {
                            HStack(spacing: 9) {
                                Circle().fill(entry.group.color).frame(width: 9, height: 9)
                                Text(entry.group.title).fontWeight(.medium)
                                Spacer()
                                Text("\(entry.count)").foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 10).fill(entry.group == model.selected ? Color.secondary.opacity(0.16) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(entry.group == model.selected ? .isSelected : [])
                    }
                    if let notice = model.notice {
                        Text(notice).font(.callout).foregroundStyle(.secondary).padding(.top, 10)
                    }
                    if model.rows.isEmpty == false { Divider().padding(.horizontal, 10).padding(.top, 12) }
                    ForEach(model.rows, id: \.number) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(row.title).lineLimit(2)
                            Spacer(minLength: 8)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                    }
                    .padding(.top, 4)
                }
            }
        }
    }
}
