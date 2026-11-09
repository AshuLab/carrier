import SwiftUI

@Observable final class SpikeModel {
    var setting = SpikeSetting()
    var selection: String? = "Home"
    var sheet = false
    var popover = false
    var toggle = true
    var value = 0.6
    var pick = 1
}

struct SpikeRoot: View {
    @Bindable var model: SpikeModel
    var body: some View {
        let s = model.setting
        NavigationSplitView {
            SpikeSidebar(model: model)
        } detail: {
            SpikeDetail(model: model)
        }
        // the accent: reaches every SwiftUI control in this window
        .modifier(AccentModifier(setting: s))
        // the scheme through SwiftUI: only this view tree
        .preferredColorScheme(s.schemeNSApp || s.scheme == "system" ? nil : (s.dark ? .dark : .light))
        .sheet(isPresented: $model.sheet) { SpikeSheet(model: model) }
    }
}

struct SpikeSidebar: View {
    @Bindable var model: SpikeModel
    var body: some View {
        let s = model.setting
        VStack(spacing: 0) {
            // the native list: its selection pill is the system's
            List(selection: $model.selection) {
                Section("Native list") {
                    row("Home", "house")
                    row("Sessions", "bubble.left")
                    row("Archive", "archivebox")
                }
            }
            .modifier(SheetTint(on: s.listTint, accent: s.theme.accent))
            .listStyle(.sidebar)
            // the list's own background out of the way, so the one we paint shows
            .scrollContentBackground(s.paint ? .hidden : .automatic)
            .frame(height: 200)
            // rows the app draws itself, as SidebarView does today: `selectedContentBackgroundColor` for the selected one, `Color.accentColor` for a badge
            VStack(alignment: .leading, spacing: 4) {
                Text("Own rows").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
                ownRow("Epic 1", selected: true, fill: Color(nsColor: .selectedContentBackgroundColor).opacity(0.45))
                ownRow("Epic 2 (accentColor)", selected: true, fill: Color.accentColor.opacity(0.25))
                ownRow("Epic 3 (.tint style)", selected: true, fill: Color.accentColor.opacity(0.25), useTint: true)
                ownRow("Epic 4", selected: false, fill: .clear)
            }.padding(8)
            Spacer()
        }
        .background(s.paint ? AnyShapeStyle(s.theme.sidebar(s.dark)) : AnyShapeStyle(.clear))
        .overlay(s.tint > 0 ? s.theme.accent.opacity(s.tint).allowsHitTesting(false) : nil)
    }

    @ViewBuilder func row(_ title: String, _ icon: String) -> some View {
        let s = model.setting
        let base = Label(title, systemImage: icon).tag(title)
        if s.listTint {
            base.listItemTint(.fixed(s.theme.accent)).listRowBackground(s.rowBackground ? s.theme.accent.opacity(0.25) : nil)
        } else {
            base.listRowBackground(s.rowBackground ? s.theme.accent.opacity(0.25) : nil)
        }
    }

    func ownRow(_ title: String, selected: Bool, fill: Color, useTint: Bool = false) -> some View {
        HStack {
            Text(title).foregroundStyle(useTint ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            Spacer()
            Text("3").font(.caption).padding(.horizontal, 6).background(Capsule().fill(Color.accentColor)).foregroundStyle(.white)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(fill))
    }
}

struct SpikeControls: View {
    @Bindable var model: SpikeModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Glass") {}.buttonStyle(.glass)
                Button("Glass prominent") {}.buttonStyle(.glassProminent)
                Button("Bordered") {}.buttonStyle(.bordered)
                Button("Bordered prominent") {}.buttonStyle(.borderedProminent)
            }
            HStack {
                Button("Capsule glass") {}.buttonStyle(.glass).buttonBorderShape(.capsule)
                Button("Plain") {}.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                Button("Link-like") {}.buttonStyle(.link)
                Image(systemName: "star.fill").foregroundStyle(.tint)
            }
            HStack(spacing: 20) {
                Toggle("Switch", isOn: $model.toggle).toggleStyle(.switch)
                Toggle("Checkbox", isOn: $model.toggle).toggleStyle(.checkbox)
            }
            Slider(value: $model.value).frame(width: 260)
            Picker("Seg", selection: $model.pick) { Text("One").tag(0); Text("Two").tag(1); Text("Three").tag(2) }.pickerStyle(.segmented).frame(width: 260)
            ProgressView(value: model.value).frame(width: 260)
            // a surface the app draws: a card with the accent at 16 percent, as WorkspaceSheet does
            Text("Own card").padding(10).background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.16)))
        }
    }
}

struct SpikeDetail: View {
    @Bindable var model: SpikeModel
    var body: some View {
        let s = model.setting
        VStack(alignment: .leading, spacing: 18) {
            Text("Detail").font(.title2.bold())
            SpikeControls(model: model)
            HStack {
                Button("Open sheet") { model.sheet = true }.buttonStyle(.glass)
                Button("Open popover") { model.popover = true }.buttonStyle(.glass)
                    .popover(isPresented: $model.popover, arrowEdge: .bottom) { SpikePopover(model: model) }
            }
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(s.paint ? AnyShapeStyle(s.theme.window(s.dark)) : AnyShapeStyle(.clear), ignoresSafeAreaEdges: s.underTitle ? .all : [])
        .overlay(s.tint > 0 ? s.theme.accent.opacity(s.tint).allowsHitTesting(false) : nil)
    }
}

struct SpikeSheet: View {
    @Bindable var model: SpikeModel
    var body: some View {
        let s = model.setting
        VStack(alignment: .leading, spacing: 14) {
            Text("Sheet").font(.title3.bold())
            SpikeControls(model: model)
            HStack { Spacer(); Button("Close") { model.sheet = false }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }
        .padding(24).frame(width: 520)
        .modifier(SheetTint(on: s.sheetTint, accent: s.theme.accent))
        .modifier(SheetBackground(on: s.sheetBackground, color: s.theme.window(s.dark)))
    }
}

struct SpikePopover: View {
    @Bindable var model: SpikeModel
    var body: some View {
        let s = model.setting
        VStack(alignment: .leading, spacing: 12) {
            Text("Popover").font(.headline)
            Toggle("Switch", isOn: $model.toggle).toggleStyle(.switch)
            Slider(value: $model.value).frame(width: 200)
            Button("Prominent") {}.buttonStyle(.borderedProminent)
            Button("Glass") {}.buttonStyle(.glass)
        }
        .padding(16)
        .modifier(SheetTint(on: s.sheetTint, accent: s.theme.accent))
        .modifier(SheetBackground(on: s.sheetBackground, color: s.theme.window(s.dark)))
    }
}

struct SheetTint: ViewModifier {
    var on: Bool, accent: Color
    func body(content: Content) -> some View { if on { content.tint(accent) } else { content } }
}

struct SheetBackground: ViewModifier {
    var on: Bool, color: Color
    func body(content: Content) -> some View { if on { content.presentationBackground(color) } else { content } }
}

struct AccentModifier: ViewModifier {
    var setting: SpikeSetting
    func body(content: Content) -> some View {
        if setting.noAccent { content }
        else if setting.accentColorAPI { content.accentColor(setting.theme.accent) }
        else { content.tint(setting.theme.accent) }
    }
}
