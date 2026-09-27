import AppKit
import Foundation

enum ClipboardPayload: Equatable {
    case text(String)
    case richText(NSAttributedString, plainText: String)
    case image(NSImage, data: Data?)
    case file(URL)

    static func == (lhs: ClipboardPayload, rhs: ClipboardPayload) -> Bool {
        switch (lhs, rhs) {
        case (.text(let l), .text(let r)): return l == r
        case (.richText(let l, _), .richText(let r, _)): return l.isEqual(to: r)
        case (.image(_, let lData), .image(_, let rData)): return lData == rData && lData != nil
        case (.file(let left), .file(let right)): return left == right
        default: return false
        }
    }
    
    var plainText: String {
        switch self {
        case .text(let str): return str
        case .richText(_, let str): return str
        case .image: return "[Image]"
        case .file(let url): return url.lastPathComponent
        }
    }
}

struct ClipboardItem: Identifiable, Equatable {
    let id: UUID
    var payload: ClipboardPayload
    var firstCopiedAt: Date
    var lastCopiedAt: Date
    var copyCount: Int
    var sourceAppName: String
    var sourceBundleIdentifier: String?
    var isPinned = false
    var group = ""
    var note = ""
    var tags: [String] = []

    var preview: String {
        payload.plainText
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []

    @Published private var config = ConfigManager.shared.config
    private var pendingSave: Task<Void, Never>?
    private let persistenceEnabled: Bool

    init(initialItems: [ClipboardItem]? = nil, persistenceEnabled: Bool = true) {
        self.persistenceEnabled = persistenceEnabled
        items = initialItems ?? (persistenceEnabled ? HistoryArchive.load() : nil) ?? []
        trim()
    }

    var visibleItems: [ClipboardItem] {
        Array((items.filter(\.isPinned) + items.filter { !$0.isPinned }).prefix(config.visibleItemCount))
    }

    var groups: [String] {
        Array(Set(items.map(\.group).filter { !$0.isEmpty })).sorted()
    }

    func reloadLimit() {
        config = ConfigManager.shared.config
        trim()
        scheduleSave()
    }

    func add(payload: ClipboardPayload, sourceApp: NSRunningApplication?) {
        reloadLimit()
        
        if case .text(let str) = payload, str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if case .richText(_, let str) = payload, str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        let bundleID = sourceApp?.bundleIdentifier
        if let bundleID, config.ignoredBundleIdentifiers.contains(bundleID) {
            return
        }
        if config.ignoredTextPatterns.contains(where: { payload.plainText.localizedCaseInsensitiveContains($0) }) {
            return
        }

        let appName = sourceApp?.localizedName ?? "Unknown App"
        let now = Date()

        if config.mergeDuplicates {
            let existingIndex = items.firstIndex { item in
                switch (item.payload, payload) {
                case (.text(let l), .text(let r)): return l == r
                case (.richText(let l, _), .richText(let r, _)): return l.isEqual(to: r)
                case (.image(_, let lData), .image(_, let rData)): return lData == rData && lData != nil
                case (.file(let left), .file(let right)): return left == right
                default: return false
                }
            }
            if let existingIndex = existingIndex {
                var existing = items.remove(at: existingIndex)
                existing.lastCopiedAt = now
                existing.copyCount += 1
                existing.sourceAppName = appName
                existing.sourceBundleIdentifier = bundleID
                items.insert(existing, at: 0)
                trim()
                scheduleSave()
                return
            }
        }

        let item = ClipboardItem(
            id: UUID(),
            payload: payload,
            firstCopiedAt: now,
            lastCopiedAt: now,
            copyCount: 1,
            sourceAppName: appName,
            sourceBundleIdentifier: bundleID
        )
        items.insert(item, at: 0)
        trim()
        scheduleSave()
    }

    func clear() {
        items.removeAll { !$0.isPinned }
        scheduleSave()
    }

    func clearAll() {
        items.removeAll()
        scheduleSave()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    func togglePin(id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned.toggle()
        scheduleSave()
    }

    func setGroup(id: UUID, name: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].group = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        scheduleSave()
    }

    func move(id: UUID, before targetID: UUID) {
        guard id != targetID,
              let source = items.firstIndex(where: { $0.id == id }),
              let target = items.firstIndex(where: { $0.id == targetID }),
              items[source].isPinned == items[target].isPinned else { return }
        let clip = items.remove(at: source)
        guard let destination = items.firstIndex(where: { $0.id == targetID }) else { return }
        items.insert(clip, at: destination)
        scheduleSave()
    }

    func update(id: UUID, text: String, group: String, note: String, tags: [String]) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if case .image = items[index].payload {} else if case .file = items[index].payload {} else if text != items[index].payload.plainText {
            items[index].payload = .text(text)
        }
        items[index].group = String(group.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        items[index].note = String(note.prefix(500))
        items[index].tags = Array(Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted().prefix(12))
        scheduleSave()
    }

    private func trim() {
        if items.count > config.maxHistoryItems {
            let excess = items.count - config.maxHistoryItems
            let unpinned = items.indices.reversed().filter { !items[$0].isPinned }
            for index in unpinned.prefix(excess) { items.remove(at: index) }
        }
    }

    private func scheduleSave() {
        guard persistenceEnabled else { return }
        pendingSave?.cancel()
        pendingSave = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await HistoryArchive.shared.save(persistenceSnapshot())
        }
    }

    func flush() {
        guard persistenceEnabled else { return }
        pendingSave?.cancel()
        HistoryArchive.saveNow(persistenceSnapshot())
    }

    private func persistenceSnapshot() -> [StoredClip] {
        var remainingBytes = 40_000_000
        let candidates = items.filter(\.isPinned) + items.filter { !$0.isPinned && config.persistHistory }
        let saved = candidates.compactMap { item -> StoredClip? in
            guard let clip = StoredClip(item) else { return nil }
            let size = (clip.data?.count ?? 0) + clip.text.utf8.count + clip.note.utf8.count + 512
            guard size <= remainingBytes else { return nil }
            remainingBytes -= size
            return clip
        }
        let order = Dictionary(uniqueKeysWithValues: items.enumerated().map { ($0.element.id, $0.offset) })
        return saved.sorted { order[$0.id, default: .max] < order[$1.id, default: .max] }
    }

}

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let store: ClipboardHistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipboardHistoryStore) {
        self.store = store
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        recordCurrentPasteboard()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
    }

    private func poll() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        
        if pasteboard.changeCount == ClipboardTransfer.ignoredChangeCount { return }

        recordCurrentPasteboard()
    }

    private func recordCurrentPasteboard() {
        let payload: ClipboardPayload?
        
        if let fileString = pasteboard.string(forType: .fileURL),
           let url = URL(string: fileString), url.isFileURL {
            payload = .file(url)
        } else if let tiffData = pasteboard.data(forType: .tiff), let image = NSImage(data: tiffData) {
            payload = .image(image, data: tiffData)
        } else if let pngData = pasteboard.data(forType: .png), let image = NSImage(data: pngData) {
            payload = .image(image, data: pngData)
        } else if let rtfData = pasteboard.data(forType: .rtf),
                  let attrString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            payload = .richText(attrString, plainText: attrString.string)
        } else if let htmlData = pasteboard.data(forType: .html),
                  let attrString = NSAttributedString(html: htmlData, documentAttributes: nil) {
            payload = .richText(attrString, plainText: attrString.string)
        } else if let text = pasteboard.string(forType: .string) {
            payload = .text(text)
        } else {
            payload = nil
        }
        
        guard let payload else { return }
        
        store.add(payload: payload, sourceApp: NSWorkspace.shared.frontmostApplication)
    }
}
