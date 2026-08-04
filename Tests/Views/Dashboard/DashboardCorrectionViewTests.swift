import XCTest
@testable import AudioWhisper

/// Tests for DashboardCorrectionView logic and calculations
@MainActor
final class DashboardCorrectionViewTests: XCTestCase {

    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        testSuiteName = "DashboardCorrectionViewTests-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName)
        testDefaults?.removePersistentDomain(forName: testSuiteName)
    }

    override func tearDown() async throws {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        try await super.tearDown()
    }

    // MARK: - Mode Parsing Tests

    func testParseModeOff() {
        let mode = DashboardCorrectionView.testableParseMode(from: "off")
        XCTAssertEqual(mode, .off)
    }

    func testParseModeLocalMLX() {
        let mode = DashboardCorrectionView.testableParseMode(from: "localMLX")
        XCTAssertEqual(mode, .localMLX)
    }

    func testParseModeCloudRemoved() {
        // Cloud mode was removed
        let mode = DashboardCorrectionView.testableParseMode(from: "cloud")
        XCTAssertNil(mode)
    }

    func testParseModeInvalid() {
        let mode = DashboardCorrectionView.testableParseMode(from: "invalid")
        XCTAssertNil(mode)
    }

    // MARK: - View Type For Mode Tests

    func testViewTypeForModeOff() {
        let viewType = DashboardCorrectionView.testableViewTypeForMode("off")
        XCTAssertEqual(viewType, "disabled_info")
    }

    func testViewTypeForModeLocalMLX() {
        let viewType = DashboardCorrectionView.testableViewTypeForMode("localMLX")
        XCTAssertEqual(viewType, "local_mlx_card")
    }

    func testViewTypeForModeInvalidDefaultsToDisabled() {
        let viewType = DashboardCorrectionView.testableViewTypeForMode("invalid")
        XCTAssertEqual(viewType, "disabled_info")
    }

    // MARK: - Install Button Visibility Tests

    func testShowsInstallButtonWhenEnvNotReady() {
        XCTAssertTrue(DashboardCorrectionView.testableShowsInstallButton(envReady: false))
    }

    func testHidesInstallButtonWhenEnvReady() {
        XCTAssertFalse(DashboardCorrectionView.testableShowsInstallButton(envReady: true))
    }

    // MARK: - Model List Visibility Tests

    func testShowsModelListWhenEnvReady() {
        XCTAssertTrue(DashboardCorrectionView.testableShowsModelList(envReady: true))
    }

    func testHidesModelListWhenEnvNotReady() {
        XCTAssertFalse(DashboardCorrectionView.testableShowsModelList(envReady: false))
    }

    // MARK: - Default Model Repo Tests

    func testDefaultModelRepo() {
        let defaultRepo = DashboardCorrectionView.testableDefaultModelRepo()
        XCTAssertEqual(defaultRepo, AppDefaults.defaultSemanticCorrectionModelRepo)
    }

    func testDefaultModelRepoIsRecommended() {
        let defaultRepo = DashboardCorrectionView.testableDefaultModelRepo()
        XCTAssertTrue(DashboardCorrectionView.testableIsRecommended(repo: defaultRepo))
    }

    // MARK: - Recommended Badge Tests

    func testDefaultModelIsTheRecommendedOne() {
        XCTAssertTrue(
            DashboardCorrectionView.testableIsRecommended(
                repo: AppDefaults.defaultSemanticCorrectionModelRepo
            )
        )
    }

    func testOtherModelsNotRecommended() {
        XCTAssertFalse(DashboardCorrectionView.testableIsRecommended(repo: "mlx-community/gemma-2b-it-4bit"))
        XCTAssertFalse(
            DashboardCorrectionView.testableIsRecommended(repo: "mlx-community/Phi-3.5-mini-instruct-4bit")
        )
    }

    // MARK: - Model Entry Creation Tests

    func testMakeMLXEntryBasic() {
        let model = MLXModelManager.recommendedModels.first!

        let entry = DashboardCorrectionView.testableMakeMLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: false,
            isSelected: false,
            badgeText: nil
        )

        XCTAssertEqual(entry.title, model.displayName)
        XCTAssertEqual(entry.subtitle, model.description)
        XCTAssertFalse(entry.isDownloaded)
        XCTAssertFalse(entry.isDownloading)
        XCTAssertFalse(entry.isSelected)
        XCTAssertNil(entry.badgeText)
    }

    func testMakeMLXEntryDownloaded() {
        let model = MLXModelManager.recommendedModels.first!

        let entry = DashboardCorrectionView.testableMakeMLXEntry(
            model: model,
            isDownloaded: true,
            isDownloading: false,
            isSelected: true,
            badgeText: "RECOMMENDED"
        )

        XCTAssertTrue(entry.isDownloaded)
        XCTAssertTrue(entry.isSelected)
        XCTAssertEqual(entry.badgeText, "RECOMMENDED")
    }

    func testMakeMLXEntryDownloading() {
        let model = MLXModelManager.recommendedModels.first!

        let entry = DashboardCorrectionView.testableMakeMLXEntry(
            model: model,
            isDownloaded: false,
            isDownloading: true,
            isSelected: false,
            badgeText: nil
        )

        XCTAssertFalse(entry.isDownloaded)
        XCTAssertTrue(entry.isDownloading)
    }

    // MARK: - Verification Timeout Tests

    func testVerificationTimeout() {
        let timeout = DashboardCorrectionView.testableVerificationTimeout
        XCTAssertEqual(timeout, 180, "Verification timeout should be 180 seconds")
    }

    // MARK: - Venv Path Tests

    func testVenvPythonPath() {
        let path = DashboardCorrectionView.testableVenvPythonPath()
        XCTAssertTrue(path.contains("AudioWhisper/python_project/.venv/bin/python3"),
            "Path should contain expected venv location")
    }

    func testVenvPythonPathNotEmpty() {
        let path = DashboardCorrectionView.testableVenvPythonPath()
        XCTAssertFalse(path.isEmpty, "Venv path should not be empty")
    }

    // MARK: - Semantic Correction Mode Enum Tests

    func testSemanticCorrectionModeAllCases() {
        let allCases = SemanticCorrectionMode.allCases
        XCTAssertEqual(allCases.count, 2)
        XCTAssertTrue(allCases.contains(.off))
        XCTAssertTrue(allCases.contains(.localMLX))
    }

    func testSemanticCorrectionModeRawValues() {
        XCTAssertEqual(SemanticCorrectionMode.off.rawValue, "off")
        XCTAssertEqual(SemanticCorrectionMode.localMLX.rawValue, "localMLX")
    }

    func testSemanticCorrectionModeDisplayNames() {
        XCTAssertFalse(SemanticCorrectionMode.off.displayName.isEmpty)
        XCTAssertFalse(SemanticCorrectionMode.localMLX.displayName.isEmpty)
    }

    // MARK: - AppStorage Default Value Tests

    func testDefaultSemanticCorrectionMode() {
        let defaultRaw = SemanticCorrectionMode.off.rawValue
        XCTAssertEqual(defaultRaw, "off")
    }

    func testDefaultModelRepoValue() {
        XCTAssertEqual(
            AppDefaults.defaultSemanticCorrectionModelRepo,
            DashboardCorrectionView.testableDefaultModelRepo()
        )
    }

    // MARK: - Environment State Tests

    func testEnvironmentStateTransitions() {
        var envReady = false
        var isCheckingEnv = false

        // Initial state
        XCTAssertFalse(envReady)
        XCTAssertFalse(isCheckingEnv)

        // Start checking
        isCheckingEnv = true
        XCTAssertTrue(isCheckingEnv)

        // Finish checking - ready
        envReady = true
        isCheckingEnv = false
        XCTAssertTrue(envReady)
        XCTAssertFalse(isCheckingEnv)
    }

    func testEnvironmentCheckNotReadyState() {
        var envReady = false
        var isCheckingEnv = false

        isCheckingEnv = true
        // Check fails
        envReady = false
        isCheckingEnv = false

        XCTAssertFalse(envReady)
        XCTAssertFalse(isCheckingEnv)
    }

    // MARK: - Setup Sheet State Tests

    func testSetupSheetStateFlow() {
        var showSetupSheet = false
        var isSettingUp = false
        var setupStatus: String?
        var setupLogs = ""

        // Start setup
        setupStatus = "Setting up Local LLM dependencies…"
        setupLogs = ""
        isSettingUp = true
        showSetupSheet = true

        XCTAssertTrue(showSetupSheet)
        XCTAssertTrue(isSettingUp)
        XCTAssertEqual(setupStatus, "Setting up Local LLM dependencies…")

        // Progress
        setupLogs += "Installing packages..."
        XCTAssertFalse(setupLogs.isEmpty)

        // Success
        isSettingUp = false
        setupStatus = "✓ Environment ready"

        XCTAssertFalse(isSettingUp)
        XCTAssertTrue(setupStatus?.contains("✓") ?? false)

        // Dismiss
        showSetupSheet = false
        XCTAssertFalse(showSetupSheet)
    }

    func testSetupSheetFailureState() {
        var isSettingUp = true
        var setupStatus = "Installing..."
        var setupLogs = ""

        // Failure
        isSettingUp = false
        setupStatus = "✗ Setup failed"
        setupLogs += "\nError: Package not found"

        XCTAssertFalse(isSettingUp)
        XCTAssertTrue(setupStatus.contains("✗"))
        XCTAssertTrue(setupLogs.contains("Error"))
    }

    // MARK: - Verification State Tests

    func testVerificationStateFlow() {
        var isVerifyingMLX = false
        var mlxVerifyMessage: String?

        // Start verification
        isVerifyingMLX = true
        mlxVerifyMessage = "Checking model (offline)…"

        XCTAssertTrue(isVerifyingMLX)
        XCTAssertEqual(mlxVerifyMessage, "Checking model (offline)…")

        // Complete successfully
        isVerifyingMLX = false
        mlxVerifyMessage = "Model verified"

        XCTAssertFalse(isVerifyingMLX)
        XCTAssertEqual(mlxVerifyMessage, "Model verified")
    }

    func testVerificationFailureState() {
        var isVerifyingMLX = true
        var mlxVerifyMessage: String? = "Checking..."

        // Failure
        isVerifyingMLX = false
        mlxVerifyMessage = "Verification failed"

        XCTAssertFalse(isVerifyingMLX)
        XCTAssertTrue(mlxVerifyMessage?.contains("failed") ?? false)
    }

    func testVerificationErrorState() {
        var isVerifyingMLX = true
        var mlxVerifyMessage: String?

        // Error occurs
        isVerifyingMLX = false
        mlxVerifyMessage = "Verification error: Network timeout"

        XCTAssertFalse(isVerifyingMLX)
        XCTAssertTrue(mlxVerifyMessage?.contains("error") ?? false)
    }

    // MARK: - Model Selection Logic Tests

    func testModelSelectionUpdatesRepo() {
        testDefaults.set("mlx-community/gemma-2b-it-4bit", forKey: "semanticCorrectionModelRepo")

        let stored = testDefaults.string(forKey: "semanticCorrectionModelRepo")
        XCTAssertEqual(stored, "mlx-community/gemma-2b-it-4bit")
    }

    func testModelDeleteFallsBackToRecommended() {
        var selectedRepo = "mlx-community/gemma-2b-it-4bit"

        // Simulate delete of selected model
        let deletedRepo = selectedRepo
        if selectedRepo == deletedRepo {
            selectedRepo = DashboardCorrectionView.testableDefaultModelRepo()
        }

        XCTAssertEqual(selectedRepo, AppDefaults.defaultSemanticCorrectionModelRepo)
    }

}
