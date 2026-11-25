import AppKit
import CarrierCore
@testable import CarrierUI
import SwiftUI
import Testing
@testable import Carrier

@MainActor
struct TerminalWorkspaceLayoutTests {
    private func makeStore() -> (store: CarrierTerminalStore, cleanup: () -> Void) {
        let suite = "carrier.layout.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let store = CarrierTerminalStore(
            fileStore: TerminalWorkspaceFileStore(fileURL: nil),
            preferences: AppPreferences(defaults: defaults),
            scheme: .dark
        )
        return (store, {
            store.teardownAll()
            defaults.removePersistentDomain(forName: suite)
        })
    }

    @Test func singlePaneHostPlacesHeaderAboveTerminalSurface() async throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let terminalId = store.createStandaloneTerminal(workingDirectory: "/tmp")
        let view = NavigationSplitView {
            Text("Sidebar")
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Group {
                        TerminalDetailView(
                            store: store,
                            terminalId: terminalId,
                            newTerminal: {}
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .themedWindowBackground()
            .navigationTitle("~/Desktop")
            .navigationSubtitle("~/Desktop")
        }
        .frame(width: 900, height: 600)

        let host = NSHostingController(rootView: view)
        host.sizingOptions = []
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 900, height: 600))
        window.makeKeyAndOrderFront(nil)
        host.view.layoutSubtreeIfNeeded()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()

        var entries: [String] = []
        var terminalFrame: NSRect?
        var scrollViewFrame: NSRect?
        var tabBarScrollFrame: NSRect?
        var scrollPocketFrames: [NSRect] = []
        func walk(_ v: NSView, depth: Int = 0) {
            let name = String(describing: type(of: v))
            let rect = v.convert(v.bounds, to: host.view)
            entries.append("\(String(repeating: " ", count: depth))\(name)=\(rect)")
            if name == "AppTerminalView" {
                terminalFrame = rect
            }
            if name.contains("HostingScrollView"), rect.width >= 400, rect.height >= 400 {
                scrollViewFrame = rect
            }
            if name.contains("HostingScrollView"), rect.width >= 400, rect.height <= 40 {
                tabBarScrollFrame = rect
            }
            if name == "NSScrollPocket" {
                scrollPocketFrames.append(rect)
            }
            for sub in v.subviews { walk(sub, depth: depth + 1) }
        }
        walk(host.view)

        let msg = "safe=\(host.view.safeAreaInsets) entries=\(entries.joined(separator: " | "))"
        let actual = try #require(terminalFrame, "Missing AppTerminalView: \(msg)")
        let container = try #require(scrollViewFrame, "Missing HostingScrollView: \(msg)")
        let tabBar = try #require(tabBarScrollFrame, "Missing bottom TerminalTabBarView: \(msg)")
        // Detail view lets the terminal surface extend behind the translucent top toolbar while mounting the shared tab bar below it.
        #expect(actual.minY <= 4, "Expected terminal to extend behind top toolbar to the window top edge: \(msg)")
        #expect(abs(actual.maxY - container.maxY) <= 1, "Expected terminal bottom to match detail ScrollView bottom: \(msg)")
        #expect(tabBar.minY >= actual.maxY, "Expected TerminalTabBarView below terminal surface: \(msg)")
        // Ensure macOS mounts a detail-column NSScrollPocket spanning the translucent top toolbar.
        #expect(scrollPocketFrames.contains(where: { $0.height >= 40 && $0.width >= 400 }), "Expected detail NSScrollPocket: \(msg)")
        window.close()
    }

    @Test func sharedTabBarRendersCompactStripAtConfiguredHeight() throws {
        let (store, cleanup) = makeStore()
        defer { cleanup() }

        let owner = TerminalOwner.terminal(UUID())
        let first = store.openTab(for: owner, workingDirectory: "/tmp/one", title: "one")
        _ = store.openTab(for: owner, workingDirectory: "/tmp/two", title: "two")
        _ = store.splitPane(first.activePaneId, edge: .trailing)

        let renderer = ImageRenderer(
            content: TerminalTabBarView(
                store: store,
                tabs: store.tabs(for: owner),
                activeTabId: first.id,
                onSelectTab: { _ in },
                onAddTab: {},
                onCloseTab: { _ in },
                onCloseOtherTabs: { _ in }
            )
            .frame(width: 480)
        )
        renderer.scale = 2
        let cgImage = try #require(renderer.cgImage)
        #expect(cgImage.height == Int(TerminalTabBarView<EmptyView>.height) * 2)
    }

    @Test func hoverControlsCapsuleRendersAtToolbarPillHeightWithoutLeftTitle() throws {
        let pane = TerminalPane(
            id: UUID(),
            title: "dev-shell",
            workingDirectory: "/tmp/project"
        )
        let renderer = ImageRenderer(
            content: TerminalPaneHeaderView(
                pane: pane,
                isSplit: true,
                isZoomed: false,
                onBeginDrag: { NSItemProvider(object: pane.id.uuidString as NSString) },
                splitRight: {},
                splitDown: {},
                toggleZoom: {},
                equalizeSplits: {},
                moveToNewTab: {},
                close: {}
            )
            .fixedSize()
        )
        renderer.scale = 2
        let cgImage = try #require(renderer.cgImage)
        // 28 pt height at 2x scale = 56 px; compact grouped capsule width stays well under 240 pt (480 px).
        #expect(cgImage.height == Int(ToolbarPillButton.height) * 2)
        #expect(cgImage.width > 100 && cgImage.width < 480)
    }
}
