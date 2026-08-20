import AppKit
let attrStr = NSAttributedString(string: "Hello", attributes: [.foregroundColor: NSColor.red])
let pb = NSPasteboard.general
pb.clearContents()
let success = pb.writeObjects([attrStr])
print("Write RTF success: \(success)")
if let types = pb.types {
    print("Types: \(types.map { $0.rawValue })")
}
