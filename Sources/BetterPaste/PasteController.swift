import AppKit
import AVFoundation
import Carbon
import Foundation
import UniformTypeIdentifiers
import Vision

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
            handleAction(action, for: items, into: targetApp)
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

    private func handleAction(_ action: ActionType, for items: [ClipboardItem], into targetApp: NSRunningApplication?) {
        if items.count > 1, items.contains(where: { if case .image = $0.payload { return true }; return false }), action == .saveAs {
            showError("Save one image at a time", detail: "Clear the selection and choose a single image to save as PNG.")
            return
        }
        let text = items.map { $0.payload.plainText }.joined(separator: "\n")
        switch action {
        case .saveAs:
            showSavePanel(for: items)
        case .extractText:
            guard items.count == 1, case .image(let image, _) = items[0].payload,
                  let data = image.tiffRepresentation else {
                showError("Choose one image", detail: "Text extraction works on a single image clip.")
                return
            }
            Task {
                let recognized = await Task.detached(priority: .userInitiated) { () -> String in
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    let handler = VNImageRequestHandler(data: data)
                    guard (try? handler.perform([request])) != nil else { return "" }
                    return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                }.value
                guard !recognized.isEmpty else {
                    showError("No text found", detail: "Try a clearer image or higher resolution copy.")
                    return
                }
                var clip = items[0]
                clip.payload = .text(recognized)
                paste([clip], textTransformer: .none, imageTransformer: .none, action: nil, into: targetApp)
            }
        case .transcodeAudio, .transcodeVideo:
            guard items.count == 1, case .file(let url) = items[0].payload else {
                showError("Choose one media file", detail: "Copy a media file in Finder, then convert that clip.")
                return
            }
            transcode(url, audioOnly: action == .transcodeAudio)
        case .rule(let id):
            guard let rule = ConfigManager.shared.config.textRules.first(where: { $0.id == id }),
                  items.allSatisfy({ item in
                      switch item.payload { case .text, .richText: return true; default: return false }
                  }) else { return }
            let source = items.map { $0.payload.plainText }.joined(separator: "\n")
            Task {
                let result = await Task.detached(priority: .userInitiated) { rule.apply(to: source) }.value
                var clip = items[0]
                clip.payload = .text(result)
                paste([clip], textTransformer: .none, imageTransformer: .none, action: nil, into: targetApp)
            }
        case .search(let engine):
            guard !items.contains(where: {
                switch $0.payload { case .image, .file: return true; default: return false }
            }) else {
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
        if items.count == 1, case .file(let source) = items[0].payload {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = source.lastPathComponent
            NSApp.activate()
            panel.begin { response in
                guard response == .OK, let destination = panel.url,
                      destination.standardizedFileURL != source.standardizedFileURL else { return }
                do {
                    let temporary = self.temporaryURL(for: destination)
                    try FileManager.default.copyItem(at: source, to: temporary)
                    try self.commitFile(at: temporary, to: destination)
                } catch {
                    self.showError("Could not save file", detail: error.localizedDescription)
                }
            }
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = formatter.string(from: Date())

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let accessory = SaveFormatAccessory(panel: panel)

        let imagePayload: Data?
        if items.count == 1, case .image(let image, let data) = items[0].payload {
            imagePayload = pngData(for: image, fallback: data)
            panel.nameFieldStringValue = "Image_\(timestamp).png"
            panel.allowedContentTypes = [.png]
        } else {
            imagePayload = nil
            panel.nameFieldStringValue = "Text_\(timestamp).txt"
            panel.accessoryView = accessory.popup
        }

        NSApp.activate()
        panel.begin { [accessory] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if let imagePayload {
                    try imagePayload.write(to: url, options: .atomic)
                } else {
                    let format = accessory.popup.indexOfSelectedItem
                    let text = items.map { $0.payload.plainText }.joined(separator: "\n")
                    let data: Data
                    let ext: String
                    switch format {
                    case 1:
                        data = items.map { ClipboardFormats.markdown($0.payload) }.joined(separator: "\n").data(using: .utf8) ?? Data()
                        ext = "md"
                    case 2:
                        let value: Any = items.count == 1 ? text : items.map { $0.payload.plainText }
                        data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .prettyPrinted])
                        ext = "json"
                    case 3:
                        data = ClipboardFormats.html(items.count == 1 ? items[0].payload : .text(text)) ?? Data()
                        ext = "html"
                    default:
                        data = text.data(using: .utf8) ?? Data()
                        ext = "txt"
                    }
                    try data.write(to: url.deletingPathExtension().appendingPathExtension(ext), options: .atomic)
                }
            } catch {
                NSLog("Better Paste could not save file: \(error.localizedDescription)")
            }
        }
    }

    private func transcode(_ source: URL, audioOnly: Bool) {
        let ext = audioOnly ? "m4a" : "mp4"
        let fileType: AVFileType = audioOnly ? .m4a : .mp4
        let preset = audioOnly ? AVAssetExportPresetAppleM4A : AVAssetExportPresetHighestQuality
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset),
              session.supportedFileTypes.contains(fileType) else {
            showError("Unsupported media file", detail: "This file cannot be converted to \(ext.uppercased()) on this Mac.")
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = source.deletingPathExtension().lastPathComponent + "." + ext
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            let temporary = self.temporaryURL(for: destination)
            session.outputURL = temporary
            session.outputFileType = fileType
            session.exportAsynchronously {
                Task { @MainActor in
                    if session.status == .completed {
                        do { try self.commitFile(at: temporary, to: destination) }
                        catch { self.showError("Could not save converted file", detail: error.localizedDescription) }
                    } else {
                        try? FileManager.default.removeItem(at: temporary)
                        self.showError("Conversion failed", detail: session.error?.localizedDescription ?? "The media format may be unsupported.")
                    }
                }
            }
        }
    }

    private func temporaryURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent()
            .appendingPathComponent(".betterpaste-\(UUID().uuidString).\(destination.pathExtension)")
    }

    private func commitFile(at temporary: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
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

@MainActor
private final class SaveFormatAccessory: NSObject {
    weak var panel: NSSavePanel?
    let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26))
    private let extensions = ["txt", "md", "json", "html"]

    init(panel: NSSavePanel) {
        self.panel = panel
        super.init()
        popup.addItems(withTitles: ["Plain Text (.txt)", "Markdown (.md)", "JSON (.json)", "HTML (.html)"])
        popup.target = self
        popup.action = #selector(formatChanged)
    }

    @objc private func formatChanged() {
        guard let panel, extensions.indices.contains(popup.indexOfSelectedItem) else { return }
        let base = (panel.nameFieldStringValue as NSString).deletingPathExtension
        panel.nameFieldStringValue = base + "." + extensions[popup.indexOfSelectedItem]
    }
}
