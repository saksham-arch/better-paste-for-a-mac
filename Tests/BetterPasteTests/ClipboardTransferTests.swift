import AppKit
import XCTest
@testable import BetterPaste

final class ClipboardTransferTests: XCTestCase {
    private func item(_ payload: ClipboardPayload) -> ClipboardItem {
        ClipboardItem(id: UUID(), payload: payload, firstCopiedAt: Date(), lastCopiedAt: Date(), copyCount: 1, sourceAppName: "Test", sourceBundleIdentifier: nil)
    }

    func testSearchEncodingPreservesUnicodeAndReservedCharacters() async {
        await MainActor.run {
            let text = "C++ & café #1 = नमस्ते 👩🏽‍💻"
            let url = URL(string: "https://example.com/?q=" + ClipboardTransfer.encodeQuery(text))!
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(components.queryItems?.count, 1)
            XCTAssertEqual(components.queryItems?.first?.value, text)
            XCTAssertNil(components.fragment)
            XCTAssertEqual(TextTransformer.urlEncode.transform("+ &"), "%2B%20%26")
        }
    }

    func testImagePublishesPNGAndTIFFAndMixedSelectionKeepsImage() async {
        await MainActor.run {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.setColor(.red, atX: 0, y: 0)
            let image = NSImage(size: NSSize(width: 2, height: 2))
            image.addRepresentation(bitmap)
            for transform in ImageTransformer.allCases {
                let objects = ClipboardTransfer.objects(for: [self.item(.image(image, data: nil)), self.item(.text("你好 👋"))], textTransformer: .none, imageTransformer: transform)
                XCTAssertEqual(objects.count, 2)
                XCTAssertNotNil(objects[0].data(forType: .png).flatMap(NSImage.init(data:)))
                XCTAssertNotNil(objects[0].data(forType: .tiff))
                XCTAssertNil(objects[0].string(forType: .string))
                XCTAssertEqual(objects[1].string(forType: .string), "你好 👋")
            }
        }
    }

    func testClipboardSnapshotRestoresEveryRepresentation() async {
        await MainActor.run {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            let original = NSPasteboardItem()
            original.setString("Original 🦊", forType: .string)
            let custom = NSPasteboard.PasteboardType("dev.betterpaste.test")
            original.setData(Data([0, 1, 255]), forType: custom)
            board.writeObjects([original])
            let snapshot = ClipboardTransfer.snapshot(board)
            board.clearContents()
            board.setString("Temporary", forType: .string)
            ClipboardTransfer.restore(snapshot, to: board)
            XCTAssertEqual(board.string(forType: .string), "Original 🦊")
            XCTAssertEqual(board.data(forType: custom), Data([0, 1, 255]))
            XCTAssertEqual(ClipboardTransfer.ignoredChangeCount, board.changeCount)
        }
    }

    func testRichTextIncludesPlainFallbackAndExplicitPlainTransform() async {
        await MainActor.run {
            let text = "é नमस्ते 👋"
            let rich = NSAttributedString(string: text, attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
            let clip = self.item(.richText(rich, plainText: text))
            let original = ClipboardTransfer.objects(for: [clip], textTransformer: .none, imageTransformer: .none)[0]
            XCTAssertEqual(original.string(forType: .string), text)
            XCTAssertNotNil(original.data(forType: .rtf))
            let plain = ClipboardTransfer.objects(for: [clip], textTransformer: .plainText, imageTransformer: .none)[0]
            XCTAssertEqual(plain.string(forType: .string), text)
            XCTAssertNil(plain.data(forType: .rtf))
        }
    }

    func testRestoreDoesNotOverwriteNewCopy() async {
        await MainActor.run {
            let board = NSPasteboard.withUniqueName()
            defer { board.releaseGlobally() }
            board.setString("Original", forType: .string)
            let snapshot = ClipboardTransfer.snapshot(board)
            board.clearContents()
            board.setString("Temporary paste", forType: .string)
            let writtenCount = board.changeCount
            board.clearContents()
            board.setString("New user copy", forType: .string)
            ClipboardTransfer.restoreIfUnchanged(snapshot, to: board, expectedChangeCount: writtenCount)
            XCTAssertEqual(board.string(forType: .string), "New user copy")
        }
    }
}
