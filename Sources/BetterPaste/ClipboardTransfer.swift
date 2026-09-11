import AppKit
import CoreImage

@MainActor
enum ClipboardTransfer {
    static var ignoredChangeCount: Int?

    nonisolated static func encodeQuery(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")) ?? ""
    }

    static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    static func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
        ignoredChangeCount = pasteboard.changeCount
    }

    static func restoreIfUnchanged(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard, expectedChangeCount: Int) {
        guard pasteboard.changeCount == expectedChangeCount else { return }
        restore(items, to: pasteboard)
    }

    static func objects(for items: [ClipboardItem], textTransformer: TextTransformer, imageTransformer: ImageTransformer) -> [NSPasteboardItem] {
        let hasImages = items.contains { if case .image = $0.payload { return true }; return false }
        if items.count > 1 && !hasImages {
            let result = NSPasteboardItem()
            result.setString(items.map { textTransformer.transform($0.payload.plainText) }.joined(separator: "\n"), forType: .string)
            return [result]
        }
        return items.compactMap { item in
            let result = NSPasteboardItem()
            switch item.payload {
            case .text(let text):
                result.setString(textTransformer.transform(text), forType: .string)
            case .richText(let rich, let plain):
                result.setString(textTransformer.transform(plain), forType: .string)
                if textTransformer == .none, let rtf = try? rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
                    result.setData(rtf, forType: .rtf)
                }
            case .image(let original, _):
                var image = original
                if imageTransformer == .grayscale,
                   let cg = original.cgImage(forProposedRect: nil, context: nil, hints: nil),
                   let filter = CIFilter(name: "CIColorControls") {
                    filter.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
                    filter.setValue(0, forKey: kCIInputSaturationKey)
                    if let output = filter.outputImage,
                       let gray = CIContext().createCGImage(output, from: output.extent) {
                        image = NSImage(cgImage: gray, size: original.size)
                    }
                }
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
                result.setData(tiff, forType: .tiff)
                result.setData(png, forType: .png)
            }
            return result
        }
    }
}
