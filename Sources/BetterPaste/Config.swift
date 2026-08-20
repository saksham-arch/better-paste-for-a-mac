import Foundation

struct AppConfig: Codable, Equatable {
    var visibleItemCount: Int
    var maxHistoryItems: Int
    var mergeDuplicates: Bool
    var pasteShortcut: ShortcutConfig
    var restoreClipboardAfterPaste: Bool
    var ignoredBundleIdentifiers: [String]
    var googleURL: String
    var chatGPTURL: String
    var bingURL: String
    var duckDuckGoURL: String

    static let `default` = AppConfig(
        visibleItemCount: 7,
        maxHistoryItems: 80,
        mergeDuplicates: true,
        pasteShortcut: ShortcutConfig(key: "v", modifiers: ["control"]),
        restoreClipboardAfterPaste: true,
        ignoredBundleIdentifiers: [
            "com.1password.1password",
            "com.agilebits.onepassword7",
            "com.apple.keychainaccess"
        ],
        googleURL: "https://www.google.com/search?q=%s",
        chatGPTURL: "https://chatgpt.com/?q=%s",
        bingURL: "https://www.bing.com/search?&q=%s",
        duckDuckGoURL: "https://duckduckgo.com/?q=%s"
    )

    private enum CodingKeys: String, CodingKey {
        case visibleItemCount
        case maxHistoryItems
        case mergeDuplicates
        case pasteShortcut
        case restoreClipboardAfterPaste
        case ignoredBundleIdentifiers
        case searchEngineURL
        case googleURL
        case chatGPTURL
        case bingURL
        case duckDuckGoURL
    }

    init(
        visibleItemCount: Int,
        maxHistoryItems: Int,
        mergeDuplicates: Bool,
        pasteShortcut: ShortcutConfig,
        restoreClipboardAfterPaste: Bool,
        ignoredBundleIdentifiers: [String],
        googleURL: String,
        chatGPTURL: String,
        bingURL: String,
        duckDuckGoURL: String
    ) {
        self.visibleItemCount = visibleItemCount
        self.maxHistoryItems = maxHistoryItems
        self.mergeDuplicates = mergeDuplicates
        self.pasteShortcut = pasteShortcut
        self.restoreClipboardAfterPaste = restoreClipboardAfterPaste
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers
        self.googleURL = googleURL
        self.chatGPTURL = chatGPTURL
        self.bingURL = bingURL
        self.duckDuckGoURL = duckDuckGoURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppConfig.default
        let legacySearchURL = try container.decodeIfPresent(String.self, forKey: .searchEngineURL)

        visibleItemCount = try container.decodeIfPresent(Int.self, forKey: .visibleItemCount) ?? defaults.visibleItemCount
        maxHistoryItems = try container.decodeIfPresent(Int.self, forKey: .maxHistoryItems) ?? defaults.maxHistoryItems
        mergeDuplicates = try container.decodeIfPresent(Bool.self, forKey: .mergeDuplicates) ?? defaults.mergeDuplicates
        pasteShortcut = try container.decodeIfPresent(ShortcutConfig.self, forKey: .pasteShortcut) ?? defaults.pasteShortcut
        restoreClipboardAfterPaste = try container.decodeIfPresent(Bool.self, forKey: .restoreClipboardAfterPaste) ?? defaults.restoreClipboardAfterPaste
        ignoredBundleIdentifiers = try container.decodeIfPresent([String].self, forKey: .ignoredBundleIdentifiers) ?? defaults.ignoredBundleIdentifiers
        googleURL = try container.decodeIfPresent(String.self, forKey: .googleURL) ?? legacySearchURL ?? defaults.googleURL
        chatGPTURL = try container.decodeIfPresent(String.self, forKey: .chatGPTURL) ?? defaults.chatGPTURL
        bingURL = try container.decodeIfPresent(String.self, forKey: .bingURL) ?? defaults.bingURL
        duckDuckGoURL = try container.decodeIfPresent(String.self, forKey: .duckDuckGoURL) ?? defaults.duckDuckGoURL
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(visibleItemCount, forKey: .visibleItemCount)
        try container.encode(maxHistoryItems, forKey: .maxHistoryItems)
        try container.encode(mergeDuplicates, forKey: .mergeDuplicates)
        try container.encode(pasteShortcut, forKey: .pasteShortcut)
        try container.encode(restoreClipboardAfterPaste, forKey: .restoreClipboardAfterPaste)
        try container.encode(ignoredBundleIdentifiers, forKey: .ignoredBundleIdentifiers)
        try container.encode(googleURL, forKey: .googleURL)
        try container.encode(chatGPTURL, forKey: .chatGPTURL)
        try container.encode(bingURL, forKey: .bingURL)
        try container.encode(duckDuckGoURL, forKey: .duckDuckGoURL)
    }
}

struct ShortcutConfig: Codable, Equatable {
    var key: String
    var modifiers: [String]
}

final class ConfigManager {
    static let shared = ConfigManager()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    var configURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("better-paste", isDirectory: true)
        return base.appendingPathComponent("config.json")
    }

    var config: AppConfig {
        guard let data = try? Data(contentsOf: configURL),
              let decoded = try? decoder.decode(AppConfig.self, from: data) else {
            return .default
        }
        return sanitized(decoded)
    }

    func ensureConfigExists() {
        save(config)
    }

    func save(_ config: AppConfig) {
        let safeConfig = sanitized(config)
        do {
            try FileManager.default.createDirectory(
                at: configURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(safeConfig)
            try data.write(to: configURL, options: [.atomic])
        } catch {
            NSLog("Better Paste could not save config: \(error.localizedDescription)")
        }
    }

    private func sanitized(_ config: AppConfig) -> AppConfig {
        var safe = config
        safe.visibleItemCount = min(max(safe.visibleItemCount, 3), 15)
        safe.maxHistoryItems = min(max(safe.maxHistoryItems, safe.visibleItemCount), 500)
        if safe.pasteShortcut.key.isEmpty {
            safe.pasteShortcut = AppConfig.default.pasteShortcut
        }
        if safe.googleURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            safe.googleURL = AppConfig.default.googleURL
        }
        if safe.chatGPTURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            safe.chatGPTURL = AppConfig.default.chatGPTURL
        }
        if safe.bingURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            safe.bingURL = AppConfig.default.bingURL
        }
        if safe.duckDuckGoURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            safe.duckDuckGoURL = AppConfig.default.duckDuckGoURL
        }
        return safe
    }
}
