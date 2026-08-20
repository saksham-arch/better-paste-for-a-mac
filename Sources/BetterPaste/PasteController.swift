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

        let previousText = pasteboard.string(forType: .string)
        let shouldRestore = ConfigManager.shared.config.restoreClipboardAfterPaste

        pasteboard.clearContents()
        
        if items.count == 1 {
            let item = items[0]
            switch item.payload {
            case .text(let string):
                pasteboard.setString(textTransformer.transform(string), forType: .string)
            case .richText(let attrString, let plain):
                if textTransformer == .none {
                    pasteboard.writeObjects([attrString])
                } else {
                    pasteboard.setString(textTransformer.transform(plain), forType: .string)
                }
            case .image(let image, _):
                if imageTransformer == .grayscale {
                    if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let context = CIContext()
                        let ciImage = CIImage(cgImage: cgImage)
                        if let filter = CIFilter(name: "CIColorControls") {
                            filter.setValue(ciImage, forKey: kCIInputImageKey)
                            filter.setValue(0.0, forKey: kCIInputSaturationKey)
                            if let output = filter.outputImage, let outCG = context.createCGImage(output, from: output.extent) {
                                let grayImage = NSImage(cgImage: outCG, size: image.size)
                                pasteboard.writeObjects([grayImage])
                            } else {
                                pasteboard.writeObjects([image])
                            }
                        } else {
                            pasteboard.writeObjects([image])
                        }
                    } else {
                        pasteboard.writeObjects([image])
                    }
                } else {
                    pasteboard.writeObjects([image])
                }
            }
        } else {
            let joined = items.map { item -> String in
                let plain = item.payload.plainText
                return textTransformer.transform(plain)
            }.joined(separator: "\n")
            
            pasteboard.setString(joined, forType: .string)
        }
        
        NSLog("Better Paste: clipboard set, yielding activation to target")

        if let targetApp {
            NSApp.yieldActivation(to: targetApp)
            targetApp.activate()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            if let targetApp, !targetApp.isActive {
                NSLog("Better Paste: target not active yet, retrying activation")
                NSApp.yieldActivation(to: targetApp)
                targetApp.activate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                NSLog("Better Paste: sending ⌘V now")
                self?.sendCommandV()
            }
        }

        guard shouldRestore, let previousText else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [pasteboard] in
            pasteboard.clearContents()
            pasteboard.setString(previousText, forType: .string)
            NSLog("Better Paste: previous clipboard restored")
        }
    }

    private func handleAction(_ action: ActionType, for items: [ClipboardItem]) {
        let text = items.map { $0.payload.plainText }.joined(separator: "\n")
        switch action {
        case .saveAs:
            showSavePanel(for: items)
        case .search(let engine):
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

        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = template.contains("%s") ? template.replacingOccurrences(of: "%s", with: encoded) : template + encoded
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
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
