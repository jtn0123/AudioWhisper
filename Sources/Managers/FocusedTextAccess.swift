import ApplicationServices
import Foundation

/// What Accessibility exposes about the focused text control of one app.
struct FocusedTextState: Equatable, Sendable {
    /// Characters in the control, when it reports a value or a count.
    var length: Int?
    /// The selection, or the insertion point when its length is 0.
    var selection: NSRange?
    /// Up to `FocusedTextAX.contextLength` characters before the selection.
    /// Empty at the start of the field; `nil` when unreadable.
    var preceding: String?
}

/// A running count of change notifications from one focused control.
@MainActor
struct FocusedTextChanges {
    var count: () -> Int
    var stop: () -> Void
}

/// Read-only Accessibility access to the paste destination, plus the one
/// write the app ever performs there: pressing its own Edit ▸ Paste.
@MainActor
struct FocusedTextAccess {
    var read: (pid_t) -> FocusedTextState?
    var pressPasteMenuItem: (pid_t) -> Bool
    var watchChanges: (pid_t) -> FocusedTextChanges? = { _ in nil }

    static var live: Self {
        Self(
            read: FocusedTextAX.read(pid:), pressPasteMenuItem: FocusedTextAX.pressPasteMenuItem(pid:),
            watchChanges: { pid in
                FocusedTextChangeWatcher(pid: pid).map { watcher in
                    FocusedTextChanges(count: { watcher.count }, stop: watcher.stop)
                }
            })
    }
}

/// Counts value and selection notifications from the focused control.
///
/// Polling alone cannot see a paste that is applied and undone between two
/// reads, and web editors such as Google Docs do exactly that: they route
/// input through a hidden field and empty it at once. Read twice, the field
/// looks untouched, and falling back to Edit ▸ Paste would paste a second
/// copy. The notifications still fire, so they count as delivery.
@MainActor
final class FocusedTextChangeWatcher {
    private(set) var count = 0
    private let observer: AXObserver
    private let element: AXUIElement
    private static let notifications = [kAXValueChangedNotification, kAXSelectedTextChangedNotification]

    init?(pid: pid_t) {
        guard !AppEnvironment.isRunningTests, AXIsProcessTrusted(),
              let focused = FocusedTextAX.focusedTextElement(pid: pid) else { return nil }
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let watcher = Unmanaged<FocusedTextChangeWatcher>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { watcher.count += 1 }
        }, &created)
        guard status == .success, let created else { return nil }
        observer = created
        element = focused
        // Unretained: `stop()` removes every registration before release.
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            AXObserverAddNotification(observer, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func stop() {
        for name in Self.notifications {
            AXObserverRemoveNotification(observer, element, name as CFString)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// The Accessibility calls behind `FocusedTextAccess.live`. Nothing here runs
/// under tests or without the Accessibility grant Smart Paste already needs.
@MainActor
enum FocusedTextAX {
    static let contextLength = 64
    /// Keeps an unresponsive app from stalling delivery on the main thread.
    private static let messagingTimeout: Float = 0.25
    private static let textRoles: Set<String> = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole]

    /// The focused control when it is a text control. Password fields are
    /// never read.
    static func focusedTextElement(pid: pid_t) -> AXUIElement? {
        guard let focused = element(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
              let role = copy(focused, kAXRoleAttribute) as? String, textRoles.contains(role),
              copy(focused, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        return focused
    }

    static func read(pid: pid_t) -> FocusedTextState? {
        guard !AppEnvironment.isRunningTests, AXIsProcessTrusted(),
              let focused = focusedTextElement(pid: pid) else { return nil }
        let value = copy(focused, kAXValueAttribute) as? String
        let count = copy(focused, kAXNumberOfCharactersAttribute) as? Int
        let selection = range(focused, kAXSelectedTextRangeAttribute)
        guard value != nil || count != nil || selection != nil else { return nil }
        return FocusedTextState(
            length: count ?? value.map { ($0 as NSString).length }, selection: selection,
            preceding: selection.flatMap { preceding(focused, before: $0.location, value: value) })
    }

    /// Presses the menu item bound to plain ⌘V, matched by its key equivalent
    /// rather than its localized title. "Paste and Match Style" carries extra
    /// modifiers and is skipped.
    static func pressPasteMenuItem(pid: pid_t) -> Bool {
        guard !AppEnvironment.isRunningTests, AXIsProcessTrusted(),
              let menuBar = element(AXUIElementCreateApplication(pid), kAXMenuBarAttribute) else { return false }
        for menuTitle in children(menuBar) {
            for menu in children(menuTitle) {
                if let item = children(menu).first(where: isPlainPaste) {
                    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }

    private static func isPlainPaste(_ item: AXUIElement) -> Bool {
        guard (copy(item, kAXMenuItemCmdCharAttribute) as? String)?.uppercased() == "V",
              copy(item, kAXMenuItemCmdModifiersAttribute) as? Int == 0 else { return false }
        return copy(item, kAXEnabledAttribute) as? Bool ?? false
    }

    private static func preceding(_ element: AXUIElement, before location: Int, value: String?) -> String? {
        guard location > 0 else { return "" }
        let start = max(0, location - contextLength)
        var cfRange = CFRange(location: start, length: location - start)
        if let parameter = AXValueCreate(.cfRange, &cfRange) {
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            var result: CFTypeRef?
            let status = AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &result)
            if status == .success, let text = result as? String { return text }
        }
        guard let value, location <= (value as NSString).length else { return nil }
        return (value as NSString).substring(with: NSRange(location: start, length: location - start))
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        // The timeout is per element and local, so it is set on every element
        // queried; the 6 s default would let a hung app stall the main thread.
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        guard let values = copy(element, kAXChildrenAttribute) as? [CFTypeRef] else { return [] }
        return values.filter { CFGetTypeID($0) == AXUIElementGetTypeID() }.map { unsafeDowncast($0, to: AXUIElement.self) }
    }

    private static func range(_ element: AXUIElement, _ attribute: String) -> NSRange? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var cfRange = CFRange()
        guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &cfRange) else { return nil }
        return NSRange(location: cfRange.location, length: cfRange.length)
    }
}
