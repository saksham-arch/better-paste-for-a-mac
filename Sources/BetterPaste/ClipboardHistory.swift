import AppKit
import Foundation

enum ClipboardPayload: Equatable {
    case text(String)
    case richText(NSAttributedString, plainText: String)
    case image(NSImage, data: Data?)

    static func == (lhs: ClipboardPayload, rhs: ClipboardPayload) -> Bool {
        switch (lhs, rhs) {
        case (.text(let l), .text(let r)): return l == r
        case (.richText(_, let lPlain), .richText(_, let rPlain)): return lPlain == rPlain
        case (.image(_, let lData), .image(_, let rData)): return lData == rData && lData != nil
        default: return false
        }
    }
    
    var plainText: String {
        switch self {
        case .text(let str): return str
        case .richText(_, let str): return str
        case .image: return "[Image]"
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

    private var config = ConfigManager.shared.config

    var visibleItems: [ClipboardItem] {
        Array(items.prefix(config.visibleItemCount))
    }

    func reloadLimit() {
        config = ConfigManager.shared.config
        trim()
    }

    func add(payload: ClipboardPayload, sourceApp: NSRunningApplication?) {
        reloadLimit()
        
        if case .text(let str) = payload, str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        if case .richText(_, let str) = payload, str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }

        let bundleID = sourceApp?.bundleIdentifier
        if let bundleID, config.ignoredBundleIdentifiers.contains(bundleID) {
            return
        }

        let appName = sourceApp?.localizedName ?? "Unknown App"
        let now = Date()

        if config.mergeDuplicates {
            let existingIndex = items.firstIndex { item in
                switch (item.payload, payload) {
                case (.text(let l), .text(let r)): return normalized(l) == normalized(r)
                case (.richText(_, let l), .richText(_, let r)): return normalized(l) == normalized(r)
                case (.image(_, let lData), .image(_, let rData)): return lData == rData && lData != nil
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
    }

    func clear() {
        items.removeAll()
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
    }

    private func trim() {
        if items.count > config.maxHistoryItems {
            items.removeLast(items.count - config.maxHistoryItems)
        }
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let store: ClipboardHistoryStore
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastRecordedPayload: ClipboardPayload?
    
    var isPasting = false

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
        
        if isPasting { return }

        recordCurrentPasteboard()
    }

    private func recordCurrentPasteboard() {
        let payload: ClipboardPayload?
        
        if let tiffData = pasteboard.data(forType: .tiff), let image = NSImage(data: tiffData) {
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
        if let last = lastRecordedPayload, last == payload { return }
        lastRecordedPayload = payload
        
        store.add(payload: payload, sourceApp: NSWorkspace.shared.frontmostApplication)
    }
}
