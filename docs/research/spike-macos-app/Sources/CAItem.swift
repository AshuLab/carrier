import AppKit
import QuartzCore
import Combine

enum CAMotion: String, CaseIterable { case none, bounce, sweep, pulse }

/// Experiment: the status item is drawn with Core Animation layers on the button, and the motion is a CAAnimation,
/// which runs in the render server. The app changes nothing per frame, so it neither burns CPU nor invalidates the open menu.
/// The layers' host must not take the clicks: the button underneath has to receive them to open the menu.
final class PassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class CAStatusController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let host = PassthroughView()
    let text = CATextLayer(), track = CALayer(), fill = CALayer(), mover = CALayer(), badge = CALayer()
    let shine = CAGradientLayer()
    var motion: CAMotion = CAMotion(rawValue: ProcessInfo.processInfo.environment["SPIKE_CA_MOTION"] ?? "") ?? .bounce
    var bag = Set<AnyCancellable>()
    let store = Store.shared

    override init() {
        super.init()
        host.wantsLayer = true
        host.layer?.addSublayer(text); host.layer?.addSublayer(track); host.layer?.addSublayer(badge)
        track.masksToBounds = true; track.cornerRadius = 2.5
        track.addSublayer(fill); track.addSublayer(mover); fill.addSublayer(shine); fill.masksToBounds = true
        item.button?.addSubview(host)
        item.menu = buildMenu()
        store.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.update() }
        }.store(in: &bag)
        update()
    }

    /// Without a cap the render server recomposes the translucent menu bar at the display rate (60+ fps), and WindowServer
    /// goes from ~8% to ~55% CPU. Capped at 20 fps it measured the same as a static bar.
    func cap(_ a: CAAnimation) {
        let fps = ProcessInfo.processInfo.environment["SPIKE_CA_FPS"].flatMap(Float.init) ?? 20
        a.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
    }

    func color(_ c: NSColor) -> CGColor {
        var out = c.cgColor
        (item.button?.effectiveAppearance ?? NSApp.effectiveAppearance).performAsCurrentDrawingAppearance { out = c.cgColor }
        return out
    }

    func update() {
        let s = store.iconState
        let thick = NSStatusBar.system.thickness
        let scale = item.button?.window?.backingScaleFactor ?? 2
        let main = color(.labelColor)
        let label: String? = (s.connected && s.working > 0) ? "\(s.working)" : nil
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let tw = label.map { ceil(NSAttributedString(string: $0, attributes: [.font: font]).size().width) } ?? 0
        var x: CGFloat = 4
        let w = 4 + (label != nil ? tw + 3 : 0) + 18 + 4 + (s.attention > 0 ? 5 : 0)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        item.length = w
        host.frame = NSRect(x: 0, y: 0, width: w, height: thick)
        text.isHidden = label == nil
        if label != nil {
            text.string = label; text.font = font; text.fontSize = 12; text.foregroundColor = main
            text.contentsScale = scale; text.frame = NSRect(x: x, y: (thick - 15) / 2, width: tw + 1, height: 15)
            x += tw + 3
        }
        track.frame = NSRect(x: x, y: (thick - 5) / 2, width: 18, height: 5)
        track.backgroundColor = color(NSColor.labelColor.withAlphaComponent(s.connected ? 0.3 : 0.2))
        let working = s.connected && s.working > 0
        let fw = working ? max(5, 18 * CGFloat(s.fraction)) : 0
        fill.frame = NSRect(x: 0, y: 0, width: fw, height: 5)
        fill.backgroundColor = main
        mover.removeAllAnimations(); fill.removeAllAnimations(); shine.removeAllAnimations()
        mover.isHidden = true; shine.isHidden = true; fill.opacity = 1
        if working {
            switch motion {
            case .none: break
            case .bounce:
                let room = 18 - fw
                if room > 4 {
                    mover.isHidden = false; mover.frame = NSRect(x: fw, y: 0, width: 4, height: 5)
                    mover.cornerRadius = 2; mover.backgroundColor = main
                    let env = ProcessInfo.processInfo.environment
                    if let steps = env["SPIKE_CA_STEPS"].flatMap(Double.init) {
                        // discrete: the layer only changes `steps` times per second, so the render server has little to redraw
                        let k = CAKeyframeAnimation(keyPath: "transform.translation.x")
                        let pts: [CGFloat] = [0, 1.0 / 3, 2.0 / 3, 1, 2.0 / 3, 1.0 / 3]
                        k.values = pts.map { $0 * (room - 4) }; k.calculationMode = .discrete
                        k.duration = Double(pts.count) / steps; k.repeatCount = .infinity
                        mover.add(k, forKey: "bounce")
                    } else {
                        let a = CABasicAnimation(keyPath: "transform.translation.x")
                        a.fromValue = 0; a.toValue = room - 4; a.duration = 0.7; a.autoreverses = true
                        a.repeatCount = .infinity; a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        cap(a)
                        mover.add(a, forKey: "bounce")
                    }
                }
            case .sweep:
                fill.backgroundColor = color(NSColor.labelColor.withAlphaComponent(0.55))
                shine.isHidden = false; shine.frame = NSRect(x: 0, y: 0, width: 10, height: 5)
                shine.colors = [main.copy(alpha: 0)!, main, main.copy(alpha: 0)!]
                shine.startPoint = CGPoint(x: 0, y: 0.5); shine.endPoint = CGPoint(x: 1, y: 0.5)
                let a = CABasicAnimation(keyPath: "transform.translation.x")
                a.fromValue = -10; a.toValue = fw; a.duration = 1.2; a.repeatCount = .infinity
                cap(a); shine.add(a, forKey: "sweep")
            case .pulse:
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 0.4; a.toValue = 1; a.duration = 0.8; a.autoreverses = true; a.repeatCount = .infinity
                cap(a); fill.add(a, forKey: "pulse")
            }
        }
        badge.isHidden = s.attention == 0
        badge.frame = NSRect(x: w - 8, y: thick - 9, width: 6, height: 6)
        badge.cornerRadius = 3; badge.backgroundColor = NSColor.systemOrange.cgColor
        CATransaction.commit()
    }

    // MARK: menu (plain NSMenu: nothing about it is invalidated by the animation)
    func buildMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Carrier spike (Core Animation icon)", action: nil, keyEquivalent: "").isEnabled = false
        m.addItem(.separator())
        let sc = NSMenuItem(title: "Scenario", action: nil, keyEquivalent: ""); let scm = NSMenu()
        for s in Scenario.allCases { let i = NSMenuItem(title: s.rawValue, action: #selector(pickScenario(_:)), keyEquivalent: ""); i.target = self; i.representedObject = s.rawValue; scm.addItem(i) }
        sc.submenu = scm; m.addItem(sc)
        let mo = NSMenuItem(title: "Motion", action: nil, keyEquivalent: ""); let mom = NSMenu()
        for a in CAMotion.allCases { let i = NSMenuItem(title: a.rawValue, action: #selector(pickMotion(_:)), keyEquivalent: ""); i.target = self; i.representedObject = a.rawValue; mom.addItem(i) }
        mo.submenu = mom; m.addItem(mo)
        m.addItem(.separator())
        let w = NSMenuItem(title: "Open window", action: #selector(openWin), keyEquivalent: ""); w.target = self; m.addItem(w)
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"); q.target = self; m.addItem(q)
        m.delegate = self
        return m
    }
    @objc func pickScenario(_ i: NSMenuItem) { if let s = (i.representedObject as? String).flatMap(Scenario.init(rawValue:)) { store.scenario = s } }
    @objc func pickMotion(_ i: NSMenuItem) { if let a = (i.representedObject as? String).flatMap(CAMotion.init(rawValue:)) { motion = a; update() } }
    @objc func openWin() { Store.shared.openWindowHook?() }
    @objc func quit() { NSApp.terminate(nil) }
}

extension CAStatusController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {   // checkmarks reflect the current choice
        for it in menu.items { for sub in it.submenu?.items ?? [] {
            let v = sub.representedObject as? String
            sub.state = (v == store.scenario.rawValue || v == motion.rawValue) ? .on : .off
        } }
    }
}

// MARK: self-test (SPIKE_SELFTEST=<logfile>): runs the menu's actions from code and logs each step, to find what kills the app.
extension CAStatusController {
    func selfTest(logPath: String) {
        func log(_ s: String) {
            let line = "\(Date().timeIntervalSince1970) \(s)\n"
            if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.synchronize(); try? h.close() }
            else { try? line.write(toFile: logPath, atomically: true, encoding: .utf8) }
        }
        let steps: [(String, () -> Void)] = [
            ("menuWillOpen", { if let m = self.item.menu { self.menuWillOpen(m) } }),
            ("scenario idle", { self.store.scenario = .idle }),
            ("scenario stopped", { self.store.scenario = .stopped }),
            ("scenario attention", { self.store.scenario = .attention }),
            ("scenario working", { self.store.scenario = .working }),
            ("motion sweep", { self.motion = .sweep; self.update() }),
            ("motion pulse", { self.motion = .pulse; self.update() }),
            ("motion none", { self.motion = .none; self.update() }),
            ("motion bounce", { self.motion = .bounce; self.update() }),
            ("openWindow hook is \(Store.shared.openWindowHook == nil ? "NIL" : "set")", {}),
            ("open window", { self.openWin() }),
            ("windows", { log("   -> " + NSApp.windows.map { "\($0.title)|\(type(of: $0))|visible=\($0.isVisible)" }.joined(separator: "; ")) }),
            ("close the Carrier spike window", { NSApp.windows.filter { $0.title == "Carrier spike" }.forEach { $0.close() } }),
            ("windows after close", { log("   -> " + NSApp.windows.map { "\($0.title)|visible=\($0.isVisible)" }.joined(separator: "; ")) }),
            ("reopen the window", { self.openWin() }),
            ("windows after reopen", { log("   -> " + NSApp.windows.map { "\($0.title)|visible=\($0.isVisible)" }.joined(separator: "; ")) }),
        ]
        log("start")
        for (i, st) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(i)) { log(st.0); st.1() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2 + Double(steps.count) + 3) { log("end: alive 3 s after the last step") }
    }
}
