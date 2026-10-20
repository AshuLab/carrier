import AppKit
import CarrierCore
import SwiftUI

/// What the output view shows: nil lines until the first answer.
final class OutputModel: ObservableObject {
    @Published var lines: [String]?
    @Published var error: String?
    @Published var carrierStopped = false
}

/// Set from the main thread, read from the watcher's.
private final class StopFlag {
    private let lock = NSLock()
    private var stopped = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func set() { lock.lock(); stopped = true; lock.unlock() }
}

/// One window per execution, opened from an epic's card. Its watcher asks for the lines while the window is open and ends
/// with it. A window of its own rather than a sheet of the panel: the panel is replaced by a message when Carrier stops,
/// and this view has to stay and say so.
final class AgentOutputWindow: NSObject, NSWindowDelegate {
    private static var open: [String: AgentOutputWindow] = [:]

    private let key: String
    private let window: NSWindow
    private let stop = StopFlag()

    static func show(title: String, executionId: String) {
        let existing = open[executionId]
        let output = existing ?? AgentOutputWindow(title: title, executionId: executionId)
        open[executionId] = output
        NSApp.activate(ignoringOtherApps: true)
        output.window.makeKeyAndOrderFront(nil)
    }

    private init(title: String, executionId: String) {
        key = executionId
        let model = OutputModel()
        window = NSWindow(contentViewController: NSHostingController(rootView: AgentOutputView(model: model)))
        super.init()
        window.title = "\(title) · output"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 480))
        window.center()
        window.delegate = self

        let stop = stop
        let watcher = OutputWatcher(
            executionId: executionId,
            connect: { connectForTail(socketPath: controlSocketPath()) },
            // sleeps in short steps so closing the window ends the thread within a tenth of a second
            wait: { seconds in
                let end = Date().addingTimeInterval(seconds)
                while Date() < end && stop.isSet == false { Thread.sleep(forTimeInterval: 0.1) }
                return stop.isSet == false
            },
            onUpdate: { update in
                DispatchQueue.main.async {
                    guard stop.isSet == false else { return }
                    switch update {
                    case .lines(let lines): model.lines = lines; model.error = nil
                    case .error(let text): model.error = text
                    case .carrierStopped: model.carrierStopped = true
                    }
                }
            }
        )
        Thread.detachNewThread { watcher.run() }
    }

    func windowWillClose(_ notification: Notification) {
        stop.set()
        Self.open[key] = nil
    }
}

private struct AgentOutputView: View {
    @ObservedObject var model: OutputModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.carrierStopped {
                Label("Carrier stopped: this output is no longer updated", systemImage: "stop.circle").foregroundStyle(.orange).padding(10)
            } else if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).padding(10)
            }
            if let lines = model.lines, lines.isEmpty == false {
                OutputText(lines: lines)
            } else {
                Text(model.lines == nil ? "Reading output…" : "No output yet")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 480, minHeight: 240)
    }
}

/// The lines in a read-only text view. It follows new lines only while it is at the bottom, so reading further up is not interrupted.
private struct OutputText: NSViewRepresentable {
    let lines: [String]

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 8, height: 8)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let text = scroll.documentView as! NSTextView
        let joined = lines.joined(separator: "\n")
        guard text.string != joined else { return }
        let visible = scroll.contentView.bounds
        let atBottom = visible.maxY >= (scroll.documentView?.frame.height ?? 0) - 4
        text.string = joined
        if atBottom { text.scrollToEndOfDocument(nil) }
    }
}
