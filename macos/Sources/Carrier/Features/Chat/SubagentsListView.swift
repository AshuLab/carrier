import CarrierCore
import CarrierUI
import SwiftUI

/// The list opened by the header's Subagents button: running launches first and finished launches below, most recent first,
/// each under a time bar on the session's timeline (except a lone running launch, which shows no bar above it), with nested
/// subagents indented under their launcher with a guide. Every launch stays open and the list scrolls within the window.
struct SubagentsListPopover: View {
    let list: SubagentsList
    /// The time the timers and launch age labels read instead of the clock; a test sets it.
    var clock: Date?
    /// Explicit height cap when passed by the toolbar or a test; otherwise bounded by `maxHeight` and `windowSize`.
    var maxHeight: CGFloat?
    let select: (String) -> Void
    @State private var contentHeight: CGFloat = 0
    @Environment(\.windowSize) private var windowSize

    static let width: CGFloat = 520
    static let maxHeight: CGFloat = 400

    /// Maximum popover height that fits inside `windowHeight` without overflowing the window.
    static func allowedHeight(windowHeight: CGFloat) -> CGFloat {
        min(maxHeight, max(120, windowHeight - 120))
    }

    private var heightCap: CGFloat {
        min(maxHeight ?? Self.maxHeight, Self.allowedHeight(windowHeight: windowSize.height))
    }

    private var estimatedHeight: CGFloat {
        let rows = CGFloat(list.allSubagents.count) * 30
        let rowGaps = CGFloat(list.launches.reduce(0) { $0 + max(0, $1.totalCount - 1) }) * Tokens.Space.s2
        let bars = CGFloat(list.launches.filter { list.showsBar(for: $0) }.count) * 22
        let launchGaps = CGFloat(max(0, list.launches.count - 1)) * Tokens.Space.s10
        return rows + rowGaps + bars + launchGaps + Tokens.Space.s8 * 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Space.s10) {
                ForEach(list.launches) { launch in
                    VStack(alignment: .leading, spacing: Tokens.Space.s2) {
                        if list.showsBar(for: launch) {
                            LaunchTimeBar(launch: launch, sessionStart: list.sessionStartedAt, clock: clock)
                        }
                        ForEach(launch.displayRows) { row in
                            SubagentsListRow(subagent: row.subagent, guides: row.guides, clock: clock) {
                                select(row.id)
                            }
                        }
                    }
                }
            }
            .padding(Tokens.Space.s8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: Self.width)
        .frame(height: min(contentHeight > 0 ? contentHeight : estimatedHeight, heightCap))
        .accessibilityLabel(Copy.chatSubagentsListSpoken())
    }
}

/// The time bar above a launch: spans when the launch ran on the session's timeline (open at the end while running)
/// beside when it ended and its subagent count, updated each minute while the list stays open.
struct LaunchTimeBar: View {
    let launch: SubagentLaunch
    let sessionStart: Int
    /// Overrides the clock for deterministic tests.
    var clock: Date?

    private static let trackWidth: CGFloat = 160
    private static let trackHeight: CGFloat = 5
    private static let minSegmentWidth: CGFloat = 4

    var body: some View {
        TickingTimeline(every: 60) { context in
            let now = Int((clock ?? context.date).timeIntervalSince1970 * 1000)
            let span = launch.timelineSpan(sessionStart: sessionStart, now: now)
            HStack(spacing: Tokens.Space.s10) {
                track(span)
                Text(launch.barLabel(now: now))
                    .scaledFont(11.5, weight: .medium)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, Tokens.Space.s10)
            .padding(.top, Tokens.Space.s4)
            .padding(.bottom, Tokens.Space.s2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(launch.barSpoken(now: now))
        }
    }

    private func track(_ span: LaunchTimelineSpan) -> some View {
        let shape: AnyShape = span.isOpen
            ? AnyShape(UnevenRoundedRectangle(topLeadingRadius: Tokens.Radius.hair, bottomLeadingRadius: Tokens.Radius.hair, bottomTrailingRadius: .zero, topTrailingRadius: .zero))
            : AnyShape(Capsule())
        let rawWidth = Self.trackWidth * (span.end - span.start)
        let segWidth = max(Self.minSegmentWidth, rawWidth)
        let offset = span.isOpen
            ? min(Self.trackWidth - segWidth, Self.trackWidth * span.start)
            : min(Self.trackWidth - segWidth, Self.trackWidth * span.start)
        let fillWidth = span.isOpen ? max(Self.minSegmentWidth, Self.trackWidth - offset) : segWidth
        return ZStack(alignment: .leading) {
            shape.fill(Color.primary.opacity(0.10))
            if span.isOpen {
                UnevenRoundedRectangle(
                    topLeadingRadius: Tokens.Radius.hair,
                    bottomLeadingRadius: Tokens.Radius.hair,
                    bottomTrailingRadius: .zero,
                    topTrailingRadius: .zero
                )
                .fill(LinearGradient(colors: [Color.thought, Color.thought.opacity(0.45)], startPoint: .leading, endPoint: .trailing))
                .frame(width: fillWidth, height: Self.trackHeight)
                .offset(x: offset)
            } else {
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: fillWidth, height: Self.trackHeight)
                    .offset(x: offset)
            }
        }
        .frame(width: Self.trackWidth, height: Self.trackHeight)
        .clipShape(shape)
    }
}

/// One row of the Subagents list: 30 pt high with optional nesting guides and indent, spinner while running, dimmed with no tick when finished,
/// a red dot (or state mark when states are told apart by shape) when failed, and dimmed saying Stopped when stopped.
struct SubagentsListRow: View {
    let subagent: Subagent
    var guides: [Bool] = []
    var clock: Date?
    let action: () -> Void
    @Environment(\.pieceTheme) private var theme

    private var isDimmed: Bool {
        subagent.status == .completed || subagent.status == .stopped
    }

    var body: some View {
        HStack(spacing: Tokens.Space.none) {
            ForEach(Array(guides.enumerated()), id: \.offset) { index, continues in
                NestGuide(isBranch: index == guides.count - 1, continues: continues)
            }
            HoverRow(action: action) { _ in
                SubagentLine(subagent: subagent, clock: clock, showsChevron: true, dimmed: isDimmed) {
                    lead
                }
            }
            .accessibilityHint(Copy.chatSubagentOpensHint())
        }
    }

    @ViewBuilder private var lead: some View {
        switch subagent.status {
        case .running:
            SpinningRing(diameter: 11, lineWidth: 1.5, color: .secondaryLabelColor)
        case .completed:
            Color.clear
        case .failed:
            if theme.statesByShape {
                StateMark(shape: .problem, size: 12).foregroundStyle(.red)
            } else {
                Circle().fill(Color.red).frame(width: 7, height: 7)
            }
        case .stopped:
            Glyph(.stopFilled, size: 8).foregroundStyle(.secondary)
        }
    }
}

/// The shared 30 pt subagent line: lead mark, type chip, title, current step or ending, step count, timer, and optional chevron.
private struct SubagentLine<Lead: View>: View {
    let subagent: Subagent
    var clock: Date?
    var showsChevron = true
    var dimmed = false
    @ViewBuilder let lead: () -> Lead

    private var steps: String { Copy.chatSubagentSteps(count: subagent.steps) }

    var body: some View {
        HStack(spacing: Tokens.Space.s10) {
            lead().frame(width: 16, height: 16)
            KindChipView(chip: .subagent(type: subagent.type))
            Text(subagent.name).scaledFont(12.5, weight: .semibold).foregroundStyle(.primary).lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Text(subagent.words()).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(steps).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
            timer
            if showsChevron { CardChevron(open: false, width: 9) }
        }
        .opacity(dimmed ? 0.55 : 1)
        .scaledFont(12, weight: .medium).monospacedDigit()
        .padding(.horizontal, Tokens.Space.s10)
        .frame(height: 30)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(subagent.spoken())
    }

    /// Ticking while it runs, its own duration once it ended.
    @ViewBuilder private var timer: some View {
        if subagent.status == .running {
            TickingTimeline(every: 1) { context in
                time(Int((clock ?? context.date).timeIntervalSince1970 * 1000))
            }
        } else {
            time(0)
        }
    }

    private func time(_ now: Int) -> some View {
        Text(formatCallDuration(subagent.elapsedMs(now: now))).scaledFont(12).foregroundStyle(.tertiary).lineLimit(1).fixedSize()
    }
}

/// One 22 × 30 pt tree-guide column aligned under the parent row's lead mark.
private struct NestGuide: View {
    let isBranch: Bool
    let continues: Bool

    private static let width: CGFloat = 22
    private static let rowHeight: CGFloat = 30
    private static let lineX: CGFloat = 18

    var body: some View {
        Canvas { context, size in
            let stroke = Path { path in
                if isBranch {
                    let midY = size.height / 2
                    path.move(to: CGPoint(x: Self.lineX, y: 0))
                    path.addLine(to: CGPoint(x: Self.lineX, y: continues ? size.height : midY))
                    path.move(to: CGPoint(x: Self.lineX, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                } else if continues {
                    path.move(to: CGPoint(x: Self.lineX, y: 0))
                    path.addLine(to: CGPoint(x: Self.lineX, y: size.height))
                }
            }
            context.stroke(stroke, with: .color(Color.primary.opacity(0.16)), lineWidth: 1)
        }
        .frame(width: Self.width, height: Self.rowHeight)
        .accessibilityHidden(true)
    }
}
