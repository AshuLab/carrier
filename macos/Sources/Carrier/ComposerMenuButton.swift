import CarrierCore
import SwiftUI

/// The mark of a provider, as the rest of the app draws it (its bundled icon in the text colour, its letter when it has none).
struct ProviderMark: View {
    let name: String
    var size: CGFloat = 14

    var body: some View {
        if let image = AgentAvatar.mark(name) {
            Image(nsImage: image).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Text(String(name.prefix(1)).uppercased()).font(.scaled(size * 0.8, weight: .bold)).frame(width: size, height: size)
        }
    }
}

/// A provider the panel offers as a tab.
struct ProviderTab: Identifiable {
    let name: String
    /// What the icon is looked up by (the harness): two agents of one provider share its mark.
    let icon: String
    var available = true
    var note: String?
    var id: String { name }
}

/// The one button of the message box, at its left: the provider's mark, the model and the reasoning level (and a flag when access is not
/// the careful default). It opens the panel: the providers as tabs, that provider's models, and a slider each for the reasoning and the access.
struct ComposerMenuButton: View {
    let providers: [ProviderTab]
    let agent: String
    /// The provider of a session that already started cannot change: the other tabs are off.
    var locked = false
    let options: [ChatOption]
    /// What the panel says in place of the lists while the provider lists none.
    var emptyNote = "Each provider's models will be listed here."
    /// The agent is answering: the host refuses a change of the reasoning until the turn ends.
    var busy = false
    let chooseAgent: (String) -> Void
    let choose: (String, String) -> Void
    @State private var open = false
    @State private var query = ""
    /// The model just chosen, until the host's list says it too.
    @State private var pendingModel: String?

    private var menu: ComposerMenu { composerMenu(options) }
    private var icon: String { providers.first { $0.name == agent }?.icon ?? agent }

    var body: some View {
        Button { open.toggle() } label: { pill }
            .buttonStyle(.plain)
            // the panel hangs from a point at the pill's left, not from the pill: the pill grows and shrinks with the model it names
            .background(alignment: .leading) {
                Color.clear.frame(width: 1, height: 28).padding(.leading, 20).popover(isPresented: $open, arrowEdge: .top) { panel }
            }
            .help("Provider, model, reasoning and access").accessibilityLabel("Provider, model, reasoning and access")
            .accessibilityValue([agent, menu.pillModel, menu.pillReasoning, menu.accessFlag].compactMap { $0 }.joined(separator: ", "))
    }

    private var pill: some View {
        HStack(spacing: 7) {
            ProviderMark(name: icon)
            Text(menu.pillModel ?? agent).fontWeight(.medium).lineLimit(1)
            if let level = menu.pillReasoning { Text("· \(level)").foregroundStyle(.secondary).lineLimit(1) }
            if let flag = menu.accessFlag {
                Text(flag).font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(Color.orange.opacity(0.2)))
            }
            Image(systemName: "chevron.down").font(.scaled(9, weight: .bold)).foregroundStyle(.secondary)
        }
        .font(.callout).padding(.horizontal, 10).frame(height: 28)
        .glassEffect(.regular.interactive(), in: .capsule)
        .contentShape(Capsule())
    }

    // MARK: the panel

    /// The same size whatever is chosen, so the panel does not move or grow as the person goes through providers and models: the list of
    /// models takes what the sliders leave. With nothing listed yet it is the short note.
    @ViewBuilder private var panel: some View {
        if menu.models.isEmpty && menu.access.isEmpty { panelContent.frame(width: panelWidth) } else { panelContent.frame(width: panelWidth, height: 520) }
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            tabs
            if menu.models.isEmpty {
                Text(emptyNote).font(.scaled(12)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                if menu.models.count > 5 { search }
                models
            }
            if let reasoning = menu.reasoning {
                ScaleRow(scale: reasoning, note: busy ? "Changes between turns: the agent is answering." : nil, color: { _, _ in Color.themeAccent }, commit: commit(reasoning)).disabled(busy)
            } else if menu.models.isEmpty == false {
                ScaleRow(scale: nil, title: "Reasoning", note: "This model has no reasoning levels.", color: { _, _ in .secondary }, commit: { _ in })
            }
            ForEach(menu.access) { scale in
                if scale.isSwitch {
                    SwitchRow(scale: scale, commit: commit(scale))
                } else {
                    ScaleRow(scale: scale, color: { index, count in riskColor(index, count) }, commit: commit(scale))
                }
            }
        }
    }

    private func commit(_ scale: OptionScale) -> (Int) -> Void {
        { index in
            guard scale.steps.indices.contains(index) else { return }
            choose(scale.id, scale.steps[index].id)
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(providers) { provider in
                let on = provider.name == agent
                let enabled = provider.available && (locked == false || on)
                Button { if on == false { chooseAgent(provider.name) } } label: {
                    ProviderMark(name: provider.icon, size: 18).frame(width: 42, height: 40)
                        .overlay(alignment: .bottom) { if on { Capsule().fill(.primary).frame(height: 2).padding(.horizontal, 9) } }
                }
                .buttonStyle(.plain).disabled(enabled == false).opacity(enabled ? (on ? 1 : 0.7) : 0.3)
                .help(provider.note.map { "\(provider.name) (\($0))" } ?? provider.name).accessibilityLabel(provider.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12).padding(.top, 4)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.scaled(12)).foregroundStyle(.secondary)
            TextField("Search models", text: $query).textFieldStyle(.plain).font(.scaled(13))
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.08)))
        .padding(.horizontal, 12).padding(.top, 10)
    }

    private var models: some View {
        let shown = menu.models.filter { query.isEmpty || $0.label.localizedCaseInsensitiveContains(query) }
        let chosen = pendingModel ?? menu.models.first(where: \.ticked)?.id
        return ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shown) { model in
                    let ticked = model.id == chosen
                    HoverRow(action: { pendingModel = model.id; choose("model", model.id) }, fill: ticked ? Color.themeAccent.opacity(0.18) : nil) { _ in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.label).font(.scaled(13, weight: .medium)).lineLimit(1)
                                // the exact model, only when it says more than the name does
                                if let line = modelLine(model) { Text(line).font(.scaled(11.5)).foregroundStyle(.secondary).lineLimit(2) }
                            }
                            Spacer(minLength: 8)
                            if ticked { ChosenMark() }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                    }
                }
                if shown.isEmpty { Text("No model matches").font(.scaled(12)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(14) }
            }
            .padding(.horizontal, 8).padding(.vertical, 8)
        }
        .frame(maxHeight: .infinity)
        // what was just chosen shows at once; the host's answer takes a moment, and replaces it
        .task(id: pendingModel) {
            guard pendingModel != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            pendingModel = nil
        }
    }

    /// The model's description, else its exact name when that is not the label said again ("GPT-6-Luna" and "gpt-6-luna" are one thing).
    private func modelLine(_ model: OptionRow.Choice) -> String? {
        if let detail = model.detail { return detail }
        guard let version = model.version, version.lowercased() != model.label.lowercased() else { return nil }
        return version
    }
}

private let panelWidth: CGFloat = 380
private let panelMargin: CGFloat = 18

/// Green for the careful end of a scale, orange in the middle, red for the free end.
private func riskColor(_ index: Int, _ count: Int) -> Color {
    let t = count < 2 ? 0 : Double(index) / Double(count - 1)
    return t < 0.34 ? .green : t < 0.67 ? .orange : .red
}

/// Holds the step the person just chose until the host's list says it too: the host answers after a moment, and until then the thumb
/// would go back to where it was and then jump. Dropped after two seconds, so a choice the host refused shows what it kept.
private struct Pending: ViewModifier {
    @Binding var pending: Int?
    let current: Int?

    func body(content: Content) -> some View {
        content
            .onChange(of: current) { _, now in if now == pending { pending = nil } }
            .task(id: pending) {
                guard pending != nil else { return }
                try? await Task.sleep(for: .seconds(2))
                pending = nil
            }
    }
}

/// A titled slider: the current value above it in the scale's colour, the two ends below it and a line on the current value. A nil
/// `scale` is the greyed row of a model with nothing to choose, with its reason.
private struct ScaleRow: View {
    let scale: OptionScale?
    var title = ""
    var note: String?
    let color: (Int, Int) -> Color
    let commit: (Int) -> Void
    /// The step under the finger while it drags.
    @State private var dragging: Int?
    /// The step chosen, until the host says it.
    @State private var pending: Int?

    var body: some View {
        let steps = scale?.steps ?? []
        let shown = dragging ?? pending ?? scale?.index ?? 0
        let tint = steps.isEmpty ? Color.secondary : color(shown, steps.count)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text((scale?.title ?? title).uppercased()).font(.scaled(11, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(steps.indices.contains(shown) ? steps[shown].label : "—").font(.scaled(13, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
            }
            if steps.isEmpty {
                // the room of a slider, so the rows under it keep their place from one model to the next
                Capsule().fill(Color.primary.opacity(0.06)).frame(height: 26)
                Text(" ").font(.scaled(11))
            } else {
                StepSlider(count: steps.count, index: shown, tint: tint, dragging: $dragging) { step in
                    guard step != scale?.index else { return }
                    pending = step
                    commit(step)
                }
                .accessibilityLabel(scale?.title ?? title).accessibilityValue(steps[shown].label)
                .accessibilityAdjustableAction { direction in
                    let next = shown + (direction == .increment ? 1 : -1)
                    if steps.indices.contains(next) { pending = next; commit(next) }
                }
                HStack {
                    Text(steps.first?.label ?? "")
                    Spacer(minLength: 12)
                    Text(steps.last?.label ?? "")
                }
                .font(.scaled(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            }
            Text(note ?? (steps.indices.contains(shown) ? steps[shown].detail : nil) ?? "").font(.scaled(12)).foregroundStyle(.primary.opacity(0.75))
                .frame(maxWidth: .infinity, minHeight: 16, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, panelMargin).padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
        .modifier(Pending(pending: $pending, current: scale?.index))
    }
}

/// An option with two values as a switch at the right of its row: on is the freer one, named as the row; the line under it says what the
/// current value lets it do.
private struct SwitchRow: View {
    let scale: OptionScale
    let commit: (Int) -> Void
    @State private var pending: Int?

    var body: some View {
        let on = (pending ?? scale.index) == 1
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(scale.steps[1].label).font(.scaled(13, weight: .semibold))
                Text(scale.steps[on ? 1 : 0].detail ?? "").font(.scaled(12)).foregroundStyle(.primary.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { on }, set: { pending = $0 ? 1 : 0; commit($0 ? 1 : 0) })).labelsHidden().toggleStyle(.switch).tint(.themeAccent)
                .accessibilityLabel(scale.steps[1].label)
        }
        .padding(.horizontal, panelMargin).padding(.vertical, 14)
        .overlay(alignment: .top) { Divider() }
        .modifier(Pending(pending: $pending, current: scale.index))
    }
}

/// A slider whose values are steps: a track with a dot per step, filled up to a white thumb that moves from step to step. A click or a
/// drag picks the nearest step; the choice is made when the finger lets go.
private struct StepSlider: View {
    let count: Int
    let index: Int
    let tint: Color
    @Binding var dragging: Int?
    let commit: (Int) -> Void
    private let thumb: CGFloat = 26

    var body: some View {
        GeometryReader { geometry in
            let usable = max(geometry.size.width - thumb, 1)
            let x = { (step: Int) -> CGFloat in thumb / 2 + (count < 2 ? usable / 2 : usable * CGFloat(step) / CGFloat(count - 1)) }
            let nearest = { (position: CGFloat) -> Int in min(max(Int(((position - thumb / 2) / usable * CGFloat(count - 1)).rounded()), 0), count - 1) }
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.14))
                Capsule().fill(tint).frame(width: x(index) + thumb / 2)
                ForEach(0..<count, id: \.self) { step in
                    Circle().fill(step < index ? Color.black.opacity(0.4) : Color.primary.opacity(0.5)).frame(width: 5, height: 5).position(x: x(step), y: thumb / 2)
                }
                Circle().fill(.white).shadow(color: .black.opacity(0.35), radius: 2, y: 1).frame(width: thumb, height: thumb).position(x: x(index), y: thumb / 2)
            }
            .animation(.smooth(duration: 0.16), value: index)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragging = nearest($0.location.x) }
                    .onEnded { value in
                        let step = nearest(value.location.x)
                        dragging = nil
                        commit(step)
                    }
            )
        }
        .frame(height: thumb)
    }
}
