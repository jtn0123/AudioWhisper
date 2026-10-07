import XCTest
@testable import AudioWhisper

final class UvSecurityPolicyTests: XCTestCase {
    func testAffectedInstallerVersionsAreRejectedByRuntimeFloor() {
        // GHSA-4gg8-gxpx-9rph is fixed in 0.11.15. PATH and per-user
        // installers must meet this floor as well as the packaged installer.
        for affected in ["0.8.5", "0.9.5", "0.11.14"] {
            XCTAssertFalse(
                UvBootstrap.isVersionForTesting(affected, greaterOrEqualThan: UvBootstrap.minUvVersion),
                "Affected installer \(affected) must not be eligible for execution"
            )
        }
        XCTAssertTrue(UvBootstrap.isVersionForTesting("0.12.23", greaterOrEqualThan: UvBootstrap.minUvVersion))
    }
}
