import AppKit
import CarrierCore
import SwiftUI

extension SliceGroup {
    /// The mockup's: merged green, in progress blue, pending the grey of the track.
    var color: Color {
        switch self {
        case .merged: .green
        case .inProgress: .blue
        case .pending: Color.secondary.opacity(0.45)
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

/// The track, then merged and in progress on it; pending is the bare track. The count and its caption sit in the middle.
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
                if arc.group != SliceGroup.allCases.firstIndex(of: .pending) {
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

/// The Slices tab: ring, the totals that filter one at a time, and the list of every slice by number.
struct SlicesTabView: View {
    let subject: EpicSubject?
    let reply: EpicReply?
    @State private var filter: SliceFilter = .all

    var body: some View {
        let model = slicesTabModel(subject, reply: reply, filter: filter, now: Int(Date().timeIntervalSince1970 * 1000))
        if model.isEmpty {
            EmptyStateView(state: .noSlices)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    SlicesRing(counts: model.counts, centre: model.centre, caption: model.caption)
                        .frame(maxWidth: .infinity).padding(.top, 16).padding(.bottom, 22)
                    ForEach(model.legend, id: \.group) { entry in
                        total(entry.group.title, count: entry.count, color: entry.group.color, filter: .only(entry.group), selected: model.selected)
                    }
                    total("Total", count: model.total, color: .clear, filter: .all, selected: model.selected)
                    if let why = model.unavailable {
                        EmptyStateView(icon: why.icon, title: why.title, line: why.line).frame(minHeight: 190)
                    }
                    VStack(spacing: 8) {
                        ForEach(model.rows, id: \.number) { SliceRowView(row: $0) }
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    /// One total. Selected, it is the row filled with the system accent colour: no check mark and no line under the totals.
    private func total(_ title: String, count: Int, color: Color, filter target: SliceFilter, selected: SliceFilter) -> some View {
        Button { filter = target } label: {
            HStack(spacing: 9) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title).fontWeight(.medium)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(target == selected ? Color.accentColor.opacity(0.18) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(target == selected ? .isSelected : [])
    }
}

/// A slice. One in progress is a card with a turning ring, "#210 Webhooks" and what it is doing; a merged or pending one is a
/// plain row with its mark (a green check or an empty circle). Under the title go its links on GitHub: the issue number and, when the engine found one, the pull
/// request. A tap on the row opens the pull request (the issue when there is none).
struct SliceRowView: View {
    let row: SliceRow
    private var group: SliceGroup { row.state }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            mark.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 5) {
                Text(group == .inProgress ? "#\(row.number) \(row.title)" : row.title)
                    .fontWeight(group == .inProgress ? .semibold : .regular)
                    .foregroundStyle(group == .pending ? Color.secondary : .primary).lineLimit(2)
                HStack(spacing: 6) {
                    if group != .inProgress { chip("#\(row.number)", url: row.issueURL, accent: false) }
                    if let number = row.prNumber { chip("PR #\(number)", url: row.prURL, accent: true) }
                    Text(row.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, group == .inProgress ? 10 : 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { if group == .inProgress { RoundedRectangle(cornerRadius: 12).fill(Color.blue.opacity(0.14)) } }
        .contentShape(Rectangle())
        .onTapGesture { open(row.prURL ?? row.issueURL) }
    }

    @ViewBuilder private var mark: some View {
        switch group {
        case .inProgress: SpinningRing(diameter: 18, lineWidth: 2.5, color: .systemBlue)
        case .merged:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 16, height: 16).background(Circle().fill(Color.green))
        case .pending: Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 2).frame(width: 12, height: 12)
        }
    }

    @ViewBuilder private func chip(_ text: String, url: String?, accent: Bool) -> some View {
        let color: Color = accent ? .accentColor : .secondary
        let label = HStack(spacing: 3) {
            Text(text)
            if url != nil { Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)) }
        }
        .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.16)))
        if let link = url.flatMap(browserURL) {
            Link(destination: link) { label }.buttonStyle(.plain).help(link.absoluteString)
        } else {
            label
        }
    }

    private func open(_ url: String?) {
        if let target = url.flatMap(browserURL) { NSWorkspace.shared.open(target) }
    }
}
