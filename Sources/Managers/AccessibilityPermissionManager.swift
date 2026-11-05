import ApplicationServices

/// Dedicated manager for handling Accessibility permissions
internal class AccessibilityPermissionManager {
    private let permissionCheck: () -> Bool

    init(permissionCheck: @escaping () -> Bool = { AXIsProcessTrustedWithOptions(nil) }) {
        self.permissionCheck = permissionCheck
    }

    /// Checks if the app has Accessibility permission without prompting the user
    /// - Returns: true if permission is granted, false otherwise
    func checkPermission() -> Bool {
        return permissionCheck()
    }

    /// Returns a user-friendly status message for the current permission state
    var permissionStatusMessage: String {
        if checkPermission() {
            return "Accessibility permission granted - SmartPaste is enabled"
        } else {
            return "Accessibility permission required for SmartPaste functionality"
        }
    }

    /// Detailed status information for debugging and user support.
    struct DetailedPermissionStatus {
        let isGranted: Bool
        let statusMessage: String
        let troubleshootingInfo: String?
    }

    /// Returns detailed status information for debugging and user support
    var detailedPermissionStatus: DetailedPermissionStatus {
        let isGranted = checkPermission()

        if isGranted {
            return DetailedPermissionStatus(
                isGranted: true,
                statusMessage: "Accessibility permission is properly configured",
                troubleshootingInfo: nil
            )
        } else {
            return DetailedPermissionStatus(
                isGranted: false,
                statusMessage: "Accessibility permission is not granted",
                troubleshootingInfo: """
                To enable SmartPaste:
                1. Open System Settings → Privacy & Security → Accessibility
                2. Add AudioWhisper to the list (using + button if needed)
                3. Toggle the switch to enable AudioWhisper
                4. Restart AudioWhisper if needed
                """
            )
        }
    }
}
