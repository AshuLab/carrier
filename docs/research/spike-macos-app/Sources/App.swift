import SwiftUI

/// Experiment: animate a plain NSStatusItem from AppKit, so SwiftUI does not re-evaluate the scene on every frame.
var appKitItem: NSStatusItem?
var caController: CAStatusController?
func startAppKitItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    appKitItem = item
    var phase = 0.0
    Timer.scheduledTimer(withTimeInterval: Store.frame, repeats: true) { _ in
        let st = Store.shared
        if !st.running.isEmpty { phase = (phase + Store.frame / 1.2).truncatingRemainder(dividingBy: 1) }
        item.button?.image = cachedIcon(st.variant, st.iconState, phase: phase, motion: st.motion)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)   // bare executables start as .prohibited
        if Store.appkit { startAppKitItem() }
    }
}

@MainActor func renderPNGs(to dir: String) {
    func write<V: View>(_ v: V, _ name: String, scale: CGFloat = 2) {
        let r = ImageRenderer(content: v); r.scale = scale
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("render failed: \(name)"); return }
        try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png")); print("wrote \(name).png")
    }
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    write(IconLab().background(Color.white), "icon-lab", scale: 3)
    write(MotionLab().background(Color.white), "motion-lab", scale: 3)
    for s in Scenario.allCases {
        let st = Store(); st.scenario = s
        write(PanelView(store: st).background(Color.white), "panel-\(s.rawValue)")
    }
}

struct SpikeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var store = Store.shared
    @StateObject var notifier = Notifier()
    @Environment(\.openWindow) var openWindow

    init() {
        if let i = CommandLine.arguments.firstIndex(of: "--render"), i + 1 < CommandLine.arguments.count {
            let dir = CommandLine.arguments[i + 1]
            DispatchQueue.main.async { MainActor.assumeIsolated { renderPNGs(to: dir) }; exit(0) }
        }
    }

    var body: some Scene {
        let _ = { Store.shared.openWindowHook = { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) } }()
        MenuBarExtra(isInserted: .constant(!Store.ca)) {
            Text("Carrier · \(store.scenario.rawValue)")
            Divider()
            Picker("Scenario", selection: $store.scenario) { ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) } }
            Picker("Icon", selection: $store.variant) { ForEach(IconVariant.allCases) { Text($0.title).tag($0) } }
            Picker("Motion", selection: $store.motion) { ForEach(IconMotion.allCases) { Text($0.title).tag($0) } }
            Divider()
            Button("Open window") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
            Button("Quit") { NSApp.terminate(nil) }
        } label: {
            Image(nsImage: store.menuImage())
        }
        Window("Carrier spike", id: "main") {
            RootView(store: store, notifier: notifier).onAppear { notifier.setup() }
        }
    }
}
