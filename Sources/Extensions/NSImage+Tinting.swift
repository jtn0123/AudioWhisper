import Cocoa

internal extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        guard let image = self.copy() as? NSImage else { return self }
        image.lockFocus()
        
        color.set()
        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)
        
        image.unlockFocus()
        return image
    }
}