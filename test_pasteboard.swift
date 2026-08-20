import AppKit
let image = NSImage(size: NSSize(width: 100, height: 100))
image.lockFocus()
NSColor.red.set()
NSRect(x: 0, y: 0, width: 100, height: 100).fill()
image.unlockFocus()

let pb = NSPasteboard.general
pb.clearContents()
let success = pb.writeObjects([image])
print("Write success: \(success)")
if let types = pb.types {
    print("Types: \(types.map { $0.rawValue })")
}
