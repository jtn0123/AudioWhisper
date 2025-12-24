import XCTest
@testable import AudioWhisper

final class KeychainServiceTests: XCTestCase {
    // Use MockKeychainService for testing to avoid actual Keychain operations
    private var keychainService: MockKeychainService!
    private let testService = "com.audiowhisper.test"
    private let testAccount = "test-account"
    private let testAccount2 = "test-account-2"

    override func setUp() {
        super.setUp()
        keychainService = MockKeychainService()
    }

    override func tearDown() {
        keychainService = nil
        super.tearDown()
    }

    // MARK: - Save and Retrieve Tests

    func testSaveAndRetrieve() throws {
        let key = "test-api-key-12345"
        try keychainService.save(key, service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, key)
    }

    func testSaveEmptyKeyDeletes() throws {
        // First save a value
        try keychainService.save("some-key", service: testService, account: testAccount)
        XCTAssertNotNil(try keychainService.get(service: testService, account: testAccount))

        // Saving empty string should delete
        try keychainService.save("", service: testService, account: testAccount)
        XCTAssertNil(try keychainService.get(service: testService, account: testAccount))
    }

    func testDeleteRemovesKey() throws {
        let key = "test-key-to-delete"
        try keychainService.save(key, service: testService, account: testAccount)
        try keychainService.delete(service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertNil(retrieved)
    }

    func testGetNonExistentReturnsNil() throws {
        let retrieved = try keychainService.get(service: "nonexistent", account: "none")
        XCTAssertNil(retrieved)
    }

    func testUpdateExistingKey() throws {
        let original = "original-api-key"
        let updated = "updated-api-key"
        try keychainService.save(original, service: testService, account: testAccount)
        try keychainService.save(updated, service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, updated)
    }

    // MARK: - Special Characters Tests

    func testSpecialCharactersInKey() throws {
        let key = "key-with-special-chars!@#$%^&*()"
        try keychainService.save(key, service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, key)
    }

    func testUnicodeCharactersInKey() throws {
        let key = "key-with-unicode-\u{1F511}-and-\u{4E2D}\u{6587}"
        try keychainService.save(key, service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, key)
    }

    // MARK: - Multiple Accounts Tests

    func testMultipleAccountsAreIndependent() throws {
        let key1 = "key-for-account-1"
        let key2 = "key-for-account-2"
        try keychainService.save(key1, service: testService, account: testAccount)
        try keychainService.save(key2, service: testService, account: testAccount2)
        let retrieved1 = try keychainService.get(service: testService, account: testAccount)
        let retrieved2 = try keychainService.get(service: testService, account: testAccount2)
        XCTAssertEqual(retrieved1, key1)
        XCTAssertEqual(retrieved2, key2)
    }

    func testDeleteOneAccountDoesNotAffectOther() throws {
        let key1 = "key-for-account-1"
        let key2 = "key-for-account-2"
        try keychainService.save(key1, service: testService, account: testAccount)
        try keychainService.save(key2, service: testService, account: testAccount2)

        try keychainService.delete(service: testService, account: testAccount)

        XCTAssertNil(try keychainService.get(service: testService, account: testAccount))
        XCTAssertEqual(try keychainService.get(service: testService, account: testAccount2), key2)
    }

    // MARK: - Long Value Tests

    func testLongKeyValue() throws {
        let longKey = String(repeating: "a", count: 200)
        try keychainService.save(longKey, service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, longKey)
    }

    func testVeryLongKeyValue() throws {
        let veryLongKey = String(repeating: "x", count: 10000)
        try keychainService.save(veryLongKey, service: testService, account: testAccount)
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, veryLongKey)
    }

    // MARK: - Quiet Methods Tests

    func testSaveQuietlyDoesNotThrow() {
        keychainService.saveQuietly("test-key", service: testService, account: testAccount)
        XCTAssertEqual(keychainService.getQuietly(service: testService, account: testAccount), "test-key")
    }

    func testGetQuietlyReturnsNilForNonExistent() {
        let result = keychainService.getQuietly(service: "nonexistent", account: "none")
        XCTAssertNil(result)
    }

    func testDeleteQuietlyDoesNotThrow() {
        keychainService.saveQuietly("test-key", service: testService, account: testAccount)
        keychainService.deleteQuietly(service: testService, account: testAccount)
        XCTAssertNil(keychainService.getQuietly(service: testService, account: testAccount))
    }

    // MARK: - Thread Safety Tests

    func testConcurrentAccess() {
        let group = DispatchGroup()
        let iterations = 100

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                self.keychainService.saveQuietly("key-\(i)", service: self.testService, account: "account-\(i)")
                _ = self.keychainService.getQuietly(service: self.testService, account: "account-\(i)")
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5.0)
        XCTAssertEqual(result, .success, "Concurrent access should complete without deadlock")
    }

    // MARK: - Protocol Conformance Tests

    func testProtocolConformance() {
        let service: KeychainServiceProtocol = keychainService
        XCTAssertNotNil(service)

        // Verify protocol methods work
        service.saveQuietly("test", service: testService, account: testAccount)
        XCTAssertEqual(service.getQuietly(service: testService, account: testAccount), "test")
        service.deleteQuietly(service: testService, account: testAccount)
        XCTAssertNil(service.getQuietly(service: testService, account: testAccount))
    }

    // MARK: - Error Cases

    func testDeleteNonExistentDoesNotThrow() {
        XCTAssertNoThrow(try keychainService.delete(service: "nonexistent", account: "none"))
    }

    func testMultipleSavesToSameKey() throws {
        for i in 0..<10 {
            try keychainService.save("value-\(i)", service: testService, account: testAccount)
        }
        let retrieved = try keychainService.get(service: testService, account: testAccount)
        XCTAssertEqual(retrieved, "value-9", "Last save should be the stored value")
    }
}
