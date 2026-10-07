import AppKit
import ApplicationServices
import Foundation

// Read only; refuse the user's host even when accidentally invoked there.
guard NSUserName() == "admin",
      FileManager.default.fileExists(atPath: "/Volumes/My Shared Files/qa") else {
    fatalError("Run only in the disposable AudioWhisper QA guest")
}
guard let app = NSWorkspace.shared.runningApplications.first(where: {
    $0.bundleIdentifier == "com.audiowhisper.rebuild"
}) else { fatalError("AudioWhisper Rebuild is not running") }

func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func label(_ element: AXUIElement, _ name: String) -> String? {
    let value = attribute(element, name)
    if let attributed = value as? NSAttributedString { return attributed.string }
    return value as? String
}

var buttons: [[String: Any]] = []
func inspect(_ element: AXUIElement, depth: Int = 0) {
    guard depth < 12 else { return }
    if label(element, kAXRoleAttribute) == kAXButtonRole {
        var row: [String: Any] = [:]
        for name in [kAXTitleAttribute, kAXDescriptionAttribute, "AXAttributedDescription", kAXHelpAttribute] {
            if let text = label(element, name) { row[name] = text }
        }
        if let selected = attribute(element, kAXSelectedAttribute) as? Bool { row["selected"] = selected }
        if let focused = attribute(element, kAXFocusedAttribute) as? Bool { row["focused"] = focused }
        if let enabled = attribute(element, kAXEnabledAttribute) as? Bool { row["enabled"] = enabled }
        for (key, attr) in [("position", kAXPositionAttribute), ("size", kAXSizeAttribute)] {
            if let v = attribute(element, attr), CFGetTypeID(v) == AXValueGetTypeID() {
                let ax = v as! AXValue
                var p = CGPoint.zero
                var z = CGSize.zero
                if AXValueGetValue(ax, .cgPoint, &p) { row[key] = [p.x, p.y] }
                if AXValueGetValue(ax, .cgSize, &z) { row[key] = [z.width, z.height] }
            }
        }
        buttons.append(row)
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        inspect(child, depth: depth + 1)
    }
}

let application = AXUIElementCreateApplication(app.processIdentifier)
for window in attribute(application, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
    inspect(window)
}
let data = try JSONSerialization.data(withJSONObject: buttons, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
