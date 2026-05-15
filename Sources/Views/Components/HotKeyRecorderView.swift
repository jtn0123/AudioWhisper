import SwiftUI
import AppKit

internal struct HotKeyRecorderView: View {
    @Binding var isRecording: Bool
    @Binding var recordedModifiers: NSEvent.ModifierFlags
    @Binding var recordedKey: Key?
    let onComplete: (String) -> Void
    
    @State private var displayText = "Press keys..."
    @State private var eventMonitor: Any?
    
    private var accentColor: Color { DashboardTheme.accent }
    
    var body: some View {
        HStack {
            Text(displayText)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .onAppear {
                    startRecording()
                }
                .onDisappear {
                    stopRecording()
                }
            
            Button("Cancel") {
                stopRecording()
                isRecording = false
            }
            .buttonStyle(.bordered)
        }
    }
    
    private func startRecording() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handleKeyEvent(event)
            return nil // Consume the event
        }
    }
    
    private func stopRecording() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            recordedModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            updateDisplayText()
        } else if event.type == .keyDown {
            if let key = keyFromKeyCode(event.keyCode) {
                recordedKey = key
                
                // Complete the recording if we have both modifiers and a key
                if (recordedKey != nil && !recordedModifiers.isEmpty) ||
                   (recordedKey != nil && isFunctionKey(key) && recordedModifiers.isEmpty) {
                    if isValidHotkey(modifiers: recordedModifiers, key: key) {
                        let hotkeyString = formatHotkey(modifiers: recordedModifiers, key: key)
                        stopRecording()
                        onComplete(hotkeyString)
                        isRecording = false
                    } else {
                        // Invalid hotkey, show error briefly
                        displayText = "Invalid combination"
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            recordedModifiers = []
                            recordedKey = nil
                            displayText = "Press keys..."
                        }
                    }
                }
            }
        }
    }
    
    private func updateDisplayText() {
        var parts: [String] = []
        
        if recordedModifiers.contains(.command) { parts.append("⌘") }
        if recordedModifiers.contains(.shift) { parts.append("⇧") }
        if recordedModifiers.contains(.option) { parts.append("⌥") }
        if recordedModifiers.contains(.control) { parts.append("⌃") }
        
        if let key = recordedKey {
            parts.append(keyToString(key))
        }
        
        displayText = parts.isEmpty ? "Press keys..." : parts.joined()
    }
    
    private func formatHotkey(modifiers: NSEvent.ModifierFlags, key: Key) -> String {
        var parts: [String] = []
        
        if modifiers.contains(.command) { parts.append("⌘") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.control) { parts.append("⌃") }
        
        parts.append(keyToString(key))
        
        return parts.joined()
    }
    
    private func isValidHotkey(modifiers: NSEvent.ModifierFlags, key: Key) -> Bool {
        // Allow function keys with no modifiers
        if modifiers.isEmpty {
            return isFunctionKey(key)
        }
        
        // Some keys should not be used as hotkeys (like escape, which is used to cancel)
        let forbiddenKeys: [Key] = [.escape, .delete, .return, .tab]
        if forbiddenKeys.contains(key) {
            return false
        }
        
        // Single modifier keys (like just shift) should require Command or Control
        if modifiers == .shift || modifiers == .option {
            return false
        }
        
        return true
    }

    private func isFunctionKey(_ key: Key) -> Bool {
        switch key {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return true
        default:
            return false
        }
    }
    
    private func keyFromKeyCode(_ keyCode: UInt16) -> Key? {
        Self.keyCodeMap[keyCode]
    }

    private func keyToString(_ key: Key) -> String {
        Self.keyDisplayNames[key] ?? ""
    }

    /// Maps macOS virtual key codes to `Key` values.
    private static let keyCodeMap: [UInt16: Key] = [
        0: .a, 1: .s, 2: .d, 3: .f, 4: .h, 5: .g, 6: .z, 7: .x, 8: .c, 9: .v,
        11: .b, 12: .q, 13: .w, 14: .e, 15: .r, 16: .y, 17: .t, 18: .one, 19: .two,
        20: .three, 21: .four, 22: .six, 23: .five, 24: .equal, 25: .nine, 26: .seven,
        27: .minus, 28: .eight, 29: .zero, 30: .rightBracket, 31: .o, 32: .u,
        33: .leftBracket, 34: .i, 35: .p, 36: .return, 37: .l, 38: .j, 39: .quote,
        40: .k, 41: .semicolon, 42: .backslash, 43: .comma, 44: .slash, 45: .n,
        46: .m, 47: .period, 48: .tab, 49: .space, 50: .grave, 51: .delete, 53: .escape,
        122: .f1, 120: .f2, 99: .f3, 118: .f4, 96: .f5, 97: .f6, 98: .f7, 100: .f8,
        101: .f9, 109: .f10, 103: .f11, 111: .f12, 105: .f13, 107: .f14, 113: .f15,
        106: .f16, 64: .f17, 79: .f18, 80: .f19, 90: .f20,
        126: .upArrow, 125: .downArrow, 123: .leftArrow, 124: .rightArrow
    ]

    /// Maps `Key` values to their display strings.
    private static let keyDisplayNames: [Key: String] = [
        .f1: "F1", .f2: "F2", .f3: "F3", .f4: "F4", .f5: "F5", .f6: "F6", .f7: "F7",
        .f8: "F8", .f9: "F9", .f10: "F10", .f11: "F11", .f12: "F12", .f13: "F13",
        .f14: "F14", .f15: "F15", .f16: "F16", .f17: "F17", .f18: "F18", .f19: "F19",
        .f20: "F20", .a: "A", .s: "S", .d: "D", .f: "F", .h: "H", .g: "G", .z: "Z",
        .x: "X", .c: "C", .v: "V", .b: "B", .q: "Q", .w: "W", .e: "E", .r: "R",
        .y: "Y", .t: "T", .one: "1", .two: "2", .three: "3", .four: "4", .six: "6",
        .five: "5", .equal: "=", .nine: "9", .seven: "7", .minus: "-", .eight: "8",
        .zero: "0", .rightBracket: "]", .o: "O", .u: "U", .leftBracket: "[", .i: "I",
        .p: "P", .return: "⏎", .l: "L", .j: "J", .quote: "'", .k: "K", .semicolon: ";",
        .backslash: "\\", .comma: ",", .slash: "/", .n: "N", .m: "M", .period: ".",
        .tab: "⇥", .space: "Space", .grave: "`", .delete: "⌫", .escape: "⎋",
        .upArrow: "↑", .downArrow: "↓", .leftArrow: "←", .rightArrow: "→"
    ]
}
