// Synthetic input inside the disposable VM only. This is not physical-key proof.
import AppKit
import CoreGraphics
import Foundation

guard FileManager.default.fileExists(atPath: "/Volumes/My Shared Files/qa/probe"),
      NSUserName() == "admin" else {
    fputs("This helper is restricted to the prepared QA guest.\n", stderr)
    exit(1)
}
let args = CommandLine.arguments
if args.count == 4, args[1] == "click", let x = Double(args[2]), let y = Double(args[3]) {
    let point = CGPoint(x: x, y: y)
    for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
} else {
    fputs("Usage: input click <guest-logical-x> <guest-logical-y>\n", stderr)
    exit(1)
}
