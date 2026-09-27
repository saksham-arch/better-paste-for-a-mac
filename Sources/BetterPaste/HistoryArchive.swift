import AppKit
import Foundation

struct StoredClip: Codable {
    enum Kind: String, Codable { case text, richText, image, file }

    let id: UUID
    let kind: Kind
    let text: String
    let data: Data?
    let firstCopiedAt: Date
    let lastCopiedAt: Date
    let copyCount: Int
    let sourceAppName: String
    let sourceBundleIdentifier: String?
    let isPinned: Bool
    let group: String
    let note: String
    let tags: [String]

    init?(_ item: ClipboardItem) {
        id = item.id
        firstCopiedAt = item.firstCopiedAt
        lastCopiedAt = item.lastCopiedAt
        copyCount = item.copyCount
        sourceAppName = item.sourceAppName
        sourceBundleIdentifier = item.sourceBundleIdentifier
        isPinned = item.isPinned
        group = item.group
        note = item.note
        tags = item.tags

        switch item.payload {
        case .text(let value):
            kind = .text
            text = value
            data = nil
        case .richText(let value, let plain):
            kind = .richText
            text = plain
            data = try? value.data(from: NSRange(location: 0, length: value.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case .image(let image, _):
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]),
                  png.count <= 5_000_000 else { return nil }
            kind = .image
            text = ""
            data = png
        case .file(let url):
            kind = .file
            text = url.absoluteString
            data = nil
        }
    }

    func item() -> ClipboardItem? {
        let payload: ClipboardPayload
        switch kind {
        case .text:
            payload = .text(text)
        case .richText:
            if let data, let rich = NSAttributedString(rtf: data, documentAttributes: nil) {
                payload = .richText(rich, plainText: text)
            } else {
                payload = .text(text)
            }
        case .image:
            guard let data, let image = NSImage(data: data) else { return nil }
            payload = .image(image, data: data)
        case .file:
            guard let url = URL(string: text), url.isFileURL else { return nil }
            payload = .file(url)
        }
        return ClipboardItem(
            id: id,
            payload: payload,
            firstCopiedAt: firstCopiedAt,
            lastCopiedAt: lastCopiedAt,
            copyCount: copyCount,
            sourceAppName: sourceAppName,
            sourceBundleIdentifier: sourceBundleIdentifier,
            isPinned: isPinned,
            group: group,
            note: note,
            tags: tags
        )
    }
}

actor HistoryArchive {
    static let shared = HistoryArchive()
    private static let fileLock = NSLock()

    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BetterPaste", isDirectory: true)
            .appendingPathComponent("history.json")
    }

    static func load() -> [ClipboardItem]? {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([StoredClip].self, from: data) else { return nil }
        let shouldLoadHistory = ConfigManager.shared.config.persistHistory
        return saved.filter { shouldLoadHistory || $0.isPinned }.compactMap { $0.item() }
    }

    func save(_ clips: [StoredClip]) {
        Self.saveNow(clips)
    }

    static func saveNow(_ clips: [StoredClip], at destination: URL? = nil) {
        fileLock.lock()
        defer { fileLock.unlock() }
        let url = destination ?? Self.url
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
            let data = try JSONEncoder().encode(clips)
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".history-\(UUID().uuidString).tmp")
            guard FileManager.default.createFile(atPath: temporary.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            do {
                try data.write(to: temporary)
                if FileManager.default.fileExists(atPath: url.path) {
                    _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
                } else {
                    try FileManager.default.moveItem(at: temporary, to: url)
                }
            } catch {
                try? FileManager.default.removeItem(at: temporary)
                throw error
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            NSLog("Better Paste could not save history: \(error.localizedDescription)")
        }
    }
}
