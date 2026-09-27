import AppKit
import Foundation

enum ClipboardFormats {
    static func jsonString(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes]),
              let result = String(data: data, encoding: .utf8) else { return text }
        return result
    }

    static func markdown(_ payload: ClipboardPayload) -> String {
        guard case .richText(let attributed, _) = payload else { return payload.plainText }
        var result = ""
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let piece = (attributed.string as NSString).substring(with: range)
            let escaped = piece.replacingOccurrences(of: "\\", with: "\\\\")
            let bold = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true
            let italic = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true
            let mark = bold && italic ? "***" : bold ? "**" : italic ? "*" : ""
            var formatted = mark.isEmpty || escaped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? escaped : mark + escaped + mark
            if let link = attributes[.link] as? URL {
                formatted = "[\(escaped)](\(link.absoluteString))"
            }
            result += formatted
        }
        return result
    }

    static func html(_ payload: ClipboardPayload) -> Data? {
        switch payload {
        case .richText(let attributed, _):
            return try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html])
        case .text(let text):
            let escaped = text.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            return ("<meta charset=\"utf-8\"><pre>\(escaped)</pre>").data(using: .utf8)
        case .image, .file:
            return nil
        }
    }
}
