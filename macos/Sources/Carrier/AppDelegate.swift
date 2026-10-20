import AppKit
import CarrierCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Static placeholder: the real icon comes in a later slice.
        let icon = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "Carrier")
        icon?.isTemplate = true
        item.button?.image = icon

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item

        if let path = Self.selfTestPath() {
            selfTest(logPath: path)
        }
    }

    // A menu bar app keeps running with no windows.
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    /// The value after `--selftest`, if there is one.
    private static func selfTestPath() -> String? {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--selftest") else { return nil }
        guard args.indices.contains(flag + 1) else {
            FileHandle.standardError.write(Data("carrier: --selftest needs a file path\n".utf8))
            return nil
        }
        return args[flag + 1]
    }

    /// Runs the menu's actions from code, one a second, and logs each step. Quit is only checked, never fired: it would end
    /// the process, and the last line has to say the process was still alive.
    private func selfTest(logPath: String) {
        try? FileManager.default.removeItem(atPath: logPath)
        let log = StepLog(path: logPath)
        func write(_ step: String) {
            do { try log.append(step) } catch {
                FileHandle.standardError.write(Data("carrier: selftest log failed: \(error)\n".utf8))
            }
        }
        let steps: [(String, () -> String)] = [
            ("status item present", { "\(self.statusItem != nil)" }),
            ("menu titles", { (self.statusItem?.menu?.items.map(\.title) ?? []).joined(separator: ", ") }),
            ("activation policy accessory", { "\(NSApp.activationPolicy() == .accessory)" }),
            ("app windows open", { "\(NSApp.windows.filter { $0.isVisible && $0.level != .statusBar }.count)" }),
            ("quit enabled", {
                guard let menu = self.statusItem?.menu else { return "false" }
                menu.update()
                return "\(menu.item(withTitle: "Quit")?.isEnabled == true)"
            }),
        ]
        write("start")
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(index)) {
                write("\(step.0): \(step.1())")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(steps.count) + 2) {
            write("end: process still alive 2 s after the last step")
        }
    }
}
