import AppKit
import Carbon
import Foundation
import UniformTypeIdentifiers

@MainActor
final class PasteController {
    private let store: ClipboardHistoryStore
    private let pasteboard = NSPasteboard.general

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityIfNeeded() {
        guard !isAccessibilityTrusted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func paste(_ items: [ClipboardItem], textTransformer: TextTransformer, imageTransformer: ImageTransformer, action: ActionType?, into targetApp: NSRunningApplication?) {
        guard !items.isEmpty else { return }

        if let action = action {
            handleAction(action, for: items)
            return
        }

        NSLog("Better Paste: paste called for \(items.count) items into \(targetApp?.localizedName ?? "nil")")

        guard PasteController.isAccessibilityTrusted else {
            NSLog("Better Paste: ⚠️ Accessibility NOT granted — paste will fail. Prompting.")
            PasteController.requestAccessibilityIfNeeded()
            return
        }

        guard let targetApp, targetApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            showError("Choose a destination app", detail: "Open the picker with your shortcut while the app you want to paste into is active.")
            return
        }

        let previous = ClipboardTransfer.snapshot(pasteboard)
        let objects = ClipboardTransfer.objects(for: items, textTransformer: textTransformer, imageTransformer: imageTransformer)
        guard !objects.isEmpty else { return }
        pasteboard.clearContents()
        guard pasteboard.writeObjects(objects) else {
            ClipboardTransfer.restore(previous, to: pasteboard)
            showError("Could not prepare the clipboard", detail: "Try copying the item again.")
            return
        }
        ClipboardTransfer.ignoredChangeCount = pasteboard.changeCount
        let writtenCount = pasteboard.changeCount
        let shouldRestore = ConfigManager.shared.config.restoreClipboardAfterPaste

        NSApp.yieldActivation(to: targetApp)
        targetApp.activate()
        Task { @MainActor in
            for _ in 0..<10 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                if targetApp.isActive { break }
                targetApp.activate()
            }
            guard pasteboard.changeCount == writtenCount else { return }
            guard targetApp.isActive else {
                ClipboardTransfer.restore(previous, to: pasteboard)
                self.showError("Could not activate the destination", detail: "Switch to the destination app and try again.")
                return
            }
            self.sendCommandV()
            guard shouldRestore else { return }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            ClipboardTransfer.restoreIfUnchanged(previous, to: pasteboard, expectedChangeCount: writtenCount)
        }
    }

    private func handleAction(_ action: ActionType, for items: [ClipboardItem]) {
        if items.count > 1, items.contains(where: { if case .image = $0.payload { return true }; return false }), action == .saveAs {
            showError("Save one image at a time", detail: "Clear the selection and choose a single image to save as PNG.")
            return
        }
        let text = items.map { $0.payload.plainText }.joined(separator: "\n")
        switch action {
        case .saveAs:
            showSavePanel(for: items)
        case .search(let engine):
            guard !items.contains(where: { if case .image = $0.payload { return true }; return false }) else {
                showError("Search needs text", detail: "Select a text clip to search the web.")
                return
            }
            openSearch(engine, query: text)
        }
    }

    private func openSearch(_ engine: SearchEngine, query: String) {
        let config = ConfigManager.shared.config
        let template: String
        switch engine {
        case .google:
            template = config.googleURL
        case .chatGPT:
            template = config.chatGPTURL
        case .bing:
            template = config.bingURL
        case .duckDuckGo:
            template = config.duckDuckGoURL
        }

        let encoded = ClipboardTransfer.encodeQuery(query)
        let urlString = template.contains("%s") ? template.replacingOccurrences(of: "%s", with: encoded) : template + encoded
        if let url = URL(string: urlString), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            NSWorkspace.shared.open(url)
        } else {
            showError("Invalid search URL", detail: "Check this search engine’s URL in Settings.")
        }
    }

    private func showSavePanel(for items: [ClipboardItem]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let payload: SavePayload
        if items.count == 1, case .image(let image, let data) = items[0].payload {
            payload = .image(data: pngData(for: image, fallback: data))
            panel.nameFieldStringValue = "Image_\(timestamp).png"
            panel.allowedContentTypes = [.png]
        } else {
            payload = .text(items.map { $0.payload.plainText }.joined(separator: "\n"))
            panel.nameFieldStringValue = "Text_\(timestamp).txt"
            panel.allowedContentTypes = [.plainText]
        }

        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                switch payload {
                case .image(let data):
                    try data.write(to: url, options: .atomic)
                case .text(let string):
                    try string.write(to: url, atomically: true, encoding: .utf8)
                }
            } catch {
                NSLog("Better Paste could not save file: \(error.localizedDescription)")
            }
        }
    }

    private func pngData(for image: NSImage, fallback: Data?) -> Data {
        if let fallback,
           let rep = NSBitmapImageRep(data: fallback),
           let png = rep.representation(using: .png, properties: [:]) {
            return png
        }

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return fallback ?? Data()
        }
        return png
    }

    private enum SavePayload {
        case image(data: Data)
        case text(String)
    }

    private func showError(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        NSApp.activate()
        alert.runModal()
    }

    private func sendCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else {
            NSLog("Better Paste: ❌ failed to create CGEvent")
            return
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        usleep(30_000)
        keyUp.post(tap: .cgSessionEventTap)
        NSLog("Better Paste: ⌘V posted via cgSessionEventTap")
    }
}
