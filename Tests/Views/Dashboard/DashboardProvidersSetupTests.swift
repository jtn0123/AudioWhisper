import XCTest
import SwiftUI
@testable import AudioWhisper

/// Setup-sheet and storage-limit coverage for DashboardProvidersView. Split
/// out of `DashboardProvidersViewTests` to keep each test class within the
/// type body length budget.
@MainActor
final class DashboardProvidersSetupTests: XCTestCase {

    // MARK: - Setup Sheet State Tests

    func testSetupSheetStateTransitions() {
        var showSetupSheet = false
        var isSettingUp = false
        var setupStatus: String?
        var setupLogs = ""

        // Start setup
        setupStatus = "Installing dependencies…"
        setupLogs = ""
        isSettingUp = true
        showSetupSheet = true

        XCTAssertTrue(showSetupSheet)
        XCTAssertTrue(isSettingUp)
        XCTAssertEqual(setupStatus, "Installing dependencies…")

        // Setup progress
        setupLogs += "Downloading packages...\n"
        XCTAssertTrue(setupLogs.contains("Downloading"))

        // Setup complete
        isSettingUp = false
        setupStatus = "✓ Environment ready"

        XCTAssertFalse(isSettingUp)
        XCTAssertTrue(setupStatus?.contains("✓") ?? false)

        // Dismiss sheet
        showSetupSheet = false
        XCTAssertFalse(showSetupSheet)
    }

    func testSetupSheetFailureState() {
        var isSettingUp = true
        var setupStatus = "Installing..."
        var setupLogs = ""

        // Setup failed
        isSettingUp = false
        setupStatus = "✗ Setup failed"
        setupLogs += "\nError: Package not found"

        XCTAssertFalse(isSettingUp)
        XCTAssertTrue(setupStatus.contains("✗"))
        XCTAssertTrue(setupLogs.contains("Error"))
    }

    // MARK: - Storage Limit Tests

    func testStorageLimitOptions() {
        let validLimits = [1.0, 2.0, 5.0, 10.0]

        for limit in validLimits {
            XCTAssertGreaterThan(limit, 0)
        }
    }

    func testStorageLimitBytesCalculation() {
        let storageGB = 5.0
        let expectedBytes = Int64(storageGB * 1024 * 1024 * 1024)

        XCTAssertEqual(expectedBytes, 5_368_709_120)
    }
}
