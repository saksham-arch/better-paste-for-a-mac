import AppKit
import XCTest
@testable import BetterPaste

final class HistoryAndFormatsTests: XCTestCase {
    func testNamedTextRulesApplyOnlyWhenValid() {
        let literal = TextRule(name: "Greeting", find: "hello", replacement: "hi")
        XCTAssertEqual(literal.apply(to: "hello world"), "hi world")
        let regex = TextRule(name: "Collapse spaces", find: " +", replacement: " ", usesRegex: true)
        XCTAssertEqual(regex.apply(to: "a   b"), "a b")
        let invalid = TextRule(name: "Broken", find: "[", replacement: "", usesRegex: true)
        XCTAssertFalse(invalid.isValid)
        XCTAssertEqual(invalid.apply(to: "original"), "original")
    }

    func testPinClearAndGroupKeepSavedClip() async {
        await MainActor.run {
            let store = ClipboardHistoryStore(initialItems: [], persistenceEnabled: false)
            store.add(payload: .text("keep"), sourceApp: nil)
            let pinnedID = store.items[0].id
            store.togglePin(id: pinnedID)
            store.setGroup(id: pinnedID, name: "Work")
            store.add(payload: .text("discard"), sourceApp: nil)
            store.clear()

            XCTAssertEqual(store.items.map(\.id), [pinnedID])
            XCTAssertEqual(store.items[0].group, "Work")
            XCTAssertEqual(store.groups, ["Work"])
            store.clearAll()
            XCTAssertTrue(store.items.isEmpty)
        }
    }

    func testDragOrderStaysWithinPinnedSection() async {
        await MainActor.run {
            let store = ClipboardHistoryStore(initialItems: [], persistenceEnabled: false)
            store.add(payload: .text("first"), sourceApp: nil)
            let first = store.items[0].id
            store.add(payload: .text("second"), sourceApp: nil)
            let second = store.items[0].id
            store.move(id: first, before: second)
            XCTAssertEqual(store.items.map(\.id), [first, second])
            store.togglePin(id: first)
            store.move(id: second, before: first)
            XCTAssertEqual(store.items.map(\.id), [first, second])
        }
    }

    func testFileClipPublishesFileURL() async {
        await MainActor.run {
            let url = URL(fileURLWithPath: "/tmp/example.mov")
            let item = ClipboardItem(
                id: UUID(), payload: .file(url), firstCopiedAt: Date(), lastCopiedAt: Date(),
                copyCount: 1, sourceAppName: "Finder", sourceBundleIdentifier: nil
            )
            let objects = ClipboardTransfer.objects(for: [item], textTransformer: .none, imageTransformer: .none)
            XCTAssertEqual(objects.first?.string(forType: .fileURL), url.absoluteString)
            XCTAssertEqual(StoredClip(item)?.item()?.payload.plainText, "example.mov")
        }
    }

    func testSavedClipRoundTripsPinnedMetadataAndRichText() throws {
        let rich = NSAttributedString(string: "Important", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        var item = ClipboardItem(
            id: UUID(), payload: .richText(rich, plainText: rich.string),
            firstCopiedAt: Date(), lastCopiedAt: Date(), copyCount: 2,
            sourceAppName: "Test", sourceBundleIdentifier: "dev.test"
        )
        item.isPinned = true
        item.group = "Research"
        item.note = "Reusable"
        item.tags = ["work", "reference"]

        let saved = try XCTUnwrap(StoredClip(item))
        let encoded = try JSONEncoder().encode(saved)
        let decoded = try JSONDecoder().decode(StoredClip.self, from: encoded)
        let restored = try XCTUnwrap(decoded.item())

        XCTAssertEqual(restored.id, item.id)
        XCTAssertTrue(restored.isPinned)
        XCTAssertEqual(restored.group, "Research")
        XCTAssertEqual(restored.note, "Reusable")
        XCTAssertEqual(restored.tags, ["work", "reference"])
        guard case .richText(let value, let plain) = restored.payload else {
            return XCTFail("Rich text should survive the archive")
        }
        XCTAssertEqual(value.string, "Important")
        XCTAssertEqual(plain, "Important")
    }

    func testArchiveOverwriteKeepsPrivatePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("betterpaste-test-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("history.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        HistoryArchive.saveNow([], at: url)
        HistoryArchive.saveNow([], at: url)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int, 0o700)
        XCTAssertEqual(try JSONDecoder().decode([StoredClip].self, from: Data(contentsOf: url)).count, 0)
    }

    func testMarkdownAndJSONPasteFormats() async {
        await MainActor.run {
            let rich = NSAttributedString(string: "hello", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
            let item = ClipboardItem(
                id: UUID(), payload: .richText(rich, plainText: "hello"),
                firstCopiedAt: Date(), lastCopiedAt: Date(), copyCount: 1,
                sourceAppName: "Test", sourceBundleIdentifier: nil
            )
            let markdown = ClipboardTransfer.objects(for: [item], textTransformer: .markdown, imageTransformer: .none)
            let json = ClipboardTransfer.objects(for: [item], textTransformer: .jsonString, imageTransformer: .none)
            XCTAssertEqual(markdown.first?.string(forType: .string), "**hello**")
            XCTAssertEqual(json.first?.string(forType: .string), "\"hello\"")
            XCTAssertNil(markdown.first?.data(forType: .rtf))
            XCTAssertNil(json.first?.data(forType: .rtf))
        }
    }
}
