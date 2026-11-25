import AppKit
import Testing
@testable import Carrier

/// The paste goes through a pasteboard of its own, never the person's general one, and sends no key: a recording stands for the ⌘V.
@MainActor @Suite struct SystemClipboardTests {
    private func board() -> NSPasteboard { NSPasteboard(name: NSPasteboard.Name("carrier-test-\(UUID().uuidString)")) }

    private func paste(_ text: String, on board: NSPasteboard, whileWaiting: @escaping () -> Void = {}) async -> (onTheClipboardAtThePaste: String?, marked: Bool) {
        var seen: (String?, Bool) = (nil, false)
        var clipboard = SystemClipboard(board: board)
        clipboard.modifiersDown = { false }
        clipboard.sendPasteKey = { seen = (board.string(forType: .string), board.types?.contains(.transient) == true) }
        clipboard.sleep = { _ in whileWaiting() }
        await clipboard.paste(text)
        return seen
    }

    @Test func theTextIsOnTheClipboardWhenTheKeyIsSentAndTheClipboardIsBackAfterwards() async throws {
        let board = board()
        defer { board.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("plain", forType: .string)
        rich.setData(Data("<b>plain</b>".utf8), forType: .html)
        rich.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.custom"))
        let second = NSPasteboardItem()
        second.setString("file:///tmp/a", forType: .fileURL)
        board.clearContents()
        board.writeObjects([rich, second])

        let seen = await paste("dictated", on: board)

        #expect(seen.onTheClipboardAtThePaste == "dictated" && seen.marked)
        let items = try #require(board.pasteboardItems)
        #expect(items.count == 2)
        #expect(items[0].string(forType: .string) == "plain")
        #expect(items[0].data(forType: .html) == Data("<b>plain</b>".utf8))
        #expect(items[0].data(forType: NSPasteboard.PasteboardType("com.example.custom")) == Data([1, 2, 3]))
        #expect(items[1].string(forType: .fileURL) == "file:///tmp/a")
        #expect(board.types?.contains(.transient) == false)
    }

    @Test func anEmptyClipboardIsEmptyAgain() async {
        let board = board()
        defer { board.releaseGlobally() }
        board.clearContents()
        _ = await paste("dictated", on: board)
        #expect(board.pasteboardItems?.isEmpty ?? true)
    }

    @Test func aCopyDuringTheWaitStaysAndIsNotRestoredOver() async {
        let board = board()
        defer { board.releaseGlobally() }
        board.clearContents()
        board.setString("before", forType: .string)
        _ = await paste("dictated", on: board) {
            board.clearContents()
            board.setString("copied meanwhile", forType: .string)
        }
        #expect(board.string(forType: .string) == "copied meanwhile")
    }

    @Test func theKeyWaitsForTheModifiersOfTheShortcutToComeUp() async {
        let board = board()
        defer { board.releaseGlobally() }
        var down = 3
        var sent = false
        var waits = 0
        var clipboard = SystemClipboard(board: board)
        clipboard.modifiersDown = {
            defer { down -= 1 }
            return down > 0
        }
        clipboard.sendPasteKey = { sent = true }
        clipboard.sleep = { _ in if sent == false { waits += 1 } }
        await clipboard.paste("dictated")
        #expect(waits == 3 && sent)
    }
}
