// Read-only guest state for VM acceptance; never run against the host desktop.
import AppKit
import CoreGraphics
import Foundation

guard NSUserName() == "admin", FileManager.default.fileExists(atPath: "/Volumes/My Shared Files/qa") else {
    fputs("This probe is restricted to the prepared QA guest.\n", stderr)
    exit(1)
}
let info = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let windows = info.filter {
    ($0[kCGWindowOwnerName as String] as? String)?.contains("AudioWhisper") == true
}.map { item -> [String: Any] in
    ["id": item[kCGWindowNumber as String] ?? 0,
     "bounds": item[kCGWindowBounds as String] ?? [:],
     "visible": item[kCGWindowIsOnscreen as String] ?? false]
}
let result: [String: Any] = [
    "frontmost": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
    "modifierFlags": NSEvent.modifierFlags.rawValue,
    "clipboard": NSPasteboard.general.string(forType: .string) ?? "",
    "screens": NSScreen.screens.map { screen in
        ["frame": [screen.frame.minX, screen.frame.minY, screen.frame.width, screen.frame.height],
         "visible": [screen.visibleFrame.minX, screen.visibleFrame.minY,
                      screen.visibleFrame.width, screen.visibleFrame.height],
         "scale": screen.backingScaleFactor]
    },
    "windows": windows
]
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]))
