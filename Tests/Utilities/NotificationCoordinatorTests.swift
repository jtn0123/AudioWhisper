import XCTest
@testable import AudioWhisper

/// Tests for NotificationCoordinator utility
@MainActor
final class NotificationCoordinatorTests: XCTestCase {
    private var coordinator: NotificationCoordinator!
    private let testNotificationName = Notification.Name("TestNotification")

    override func setUp() async throws {
        try await super.setUp()
        coordinator = NotificationCoordinator()
    }

    override func tearDown() async throws {
        coordinator?.removeAll()
        coordinator = nil
        try await super.tearDown()
    }

    // MARK: - Basic Observer Tests

    func testObserveReceivesNotifications() async throws {
        let expectation = XCTestExpectation(description: "Notification received")

        coordinator.observe(testNotificationName) { _ in
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: testNotificationName, object: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testObserveOnMainActorReceivesNotifications() async throws {
        let expectation = XCTestExpectation(description: "Notification received on MainActor")

        coordinator.observeOnMainActor(testNotificationName) { _ in
            // This runs on MainActor
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }

        NotificationCenter.default.post(name: testNotificationName, object: nil)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    func testObserveReceivesNotificationPayload() async throws {
        let expectation = XCTestExpectation(description: "Notification with payload received")
        let testPayload = "Test Message"

        coordinator.observe(testNotificationName) { notification in
            if let message = notification.object as? String {
                XCTAssertEqual(message, testPayload)
                expectation.fulfill()
            }
        }

        NotificationCenter.default.post(name: testNotificationName, object: testPayload)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - Observer Management Tests

    func testIsObservingReturnsTrueForActiveObserver() async throws {
        XCTAssertFalse(coordinator.isObserving(testNotificationName))

        coordinator.observe(testNotificationName) { _ in }

        XCTAssertTrue(coordinator.isObserving(testNotificationName))
    }

    func testObserverCountReflectsActiveObservers() async throws {
        XCTAssertEqual(coordinator.observerCount, 0)

        coordinator.observe(testNotificationName) { _ in }
        XCTAssertEqual(coordinator.observerCount, 1)

        let secondNotification = Notification.Name("SecondNotification")
        coordinator.observe(secondNotification) { _ in }
        XCTAssertEqual(coordinator.observerCount, 2)
    }

    func testRemoveForNameStopsObserving() async throws {
        coordinator.observe(testNotificationName) { _ in }
        XCTAssertTrue(coordinator.isObserving(testNotificationName))

        coordinator.remove(for: testNotificationName)
        XCTAssertFalse(coordinator.isObserving(testNotificationName))
    }

    func testRemoveAllClearsAllObservers() async throws {
        coordinator.observe(testNotificationName) { _ in }
        coordinator.observe(Notification.Name("Second")) { _ in }
        coordinator.observe(Notification.Name("Third")) { _ in }

        XCTAssertEqual(coordinator.observerCount, 3)

        coordinator.removeAll()

        XCTAssertEqual(coordinator.observerCount, 0)
    }

    // MARK: - Duplicate Observer Tests

    func testObservingSameNameReplacesExistingObserver() async throws {
        let firstExpectation = XCTestExpectation(description: "First observer called")
        firstExpectation.isInverted = true // Should NOT be fulfilled
        let secondExpectation = XCTestExpectation(description: "Second observer called")

        coordinator.observe(testNotificationName) { _ in
            firstExpectation.fulfill()
        }

        // Replace with new observer
        coordinator.observe(testNotificationName) { _ in
            secondExpectation.fulfill()
        }

        XCTAssertEqual(coordinator.observerCount, 1)

        NotificationCenter.default.post(name: testNotificationName, object: nil)

        // Wait for expectations
        await fulfillment(of: [secondExpectation], timeout: 0.5)
        await fulfillment(of: [firstExpectation], timeout: 0.1)
    }

    // MARK: - Cleanup Tests

    func testRemovedObserverDoesNotReceiveNotifications() async throws {
        let expectation = XCTestExpectation(description: "Notification received")
        expectation.isInverted = true // Should NOT be fulfilled

        coordinator.observe(testNotificationName) { _ in
            expectation.fulfill()
        }

        coordinator.remove(for: testNotificationName)

        NotificationCenter.default.post(name: testNotificationName, object: nil)

        await fulfillment(of: [expectation], timeout: 0.1)
    }

    // MARK: - In-flight Handler Task Cancellation (bug #36)

    func testRemoveAllCancelsInFlightHandlerTask() async throws {
        let started = XCTestExpectation(description: "Handler started")
        let mutatedAfterTeardown = XCTestExpectation(description: "Handler mutated state after teardown")
        mutatedAfterTeardown.isInverted = true // Should NOT happen — task must be cancelled

        coordinator.observeOnMainActor(testNotificationName) { _ in
            started.fulfill()
            // Simulate a slow handler still running when teardown happens.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                // Cancelled — expected. Bail out before mutating state.
                return
            }
            mutatedAfterTeardown.fulfill()
        }

        NotificationCenter.default.post(name: testNotificationName, object: nil)
        await fulfillment(of: [started], timeout: 1.0)

        // Tear down while the handler is mid-flight.
        coordinator.removeAll()

        // The in-flight handler must have been cancelled and never reach the
        // post-sleep mutation.
        await fulfillment(of: [mutatedAfterTeardown], timeout: 1.0)
    }

    func testRemoveForNameCancelsInFlightHandlerTask() async throws {
        let started = XCTestExpectation(description: "Handler started")
        let completed = XCTestExpectation(description: "Handler completed past sleep")
        completed.isInverted = true

        coordinator.observeOnMainActor(testNotificationName) { _ in
            started.fulfill()
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            completed.fulfill()
        }

        NotificationCenter.default.post(name: testNotificationName, object: nil)
        await fulfillment(of: [started], timeout: 1.0)

        coordinator.remove(for: testNotificationName)

        await fulfillment(of: [completed], timeout: 1.0)
    }

    func testCompletedHandlerTasksDoNotAccumulate() async throws {
        // Fire several quick handlers; once they finish, no handler tasks
        // should linger (observerCount only tracks observers/streams, so we
        // assert behaviorally: a subsequent removeAll is clean and the
        // coordinator can keep observing).
        let received = XCTestExpectation(description: "All handlers ran")
        received.expectedFulfillmentCount = 3

        coordinator.observeOnMainActor(testNotificationName) { _ in
            received.fulfill()
        }

        for _ in 0..<3 {
            NotificationCenter.default.post(name: testNotificationName, object: nil)
        }

        await fulfillment(of: [received], timeout: 2.0)

        // Give self-removal a beat to run, then tear down cleanly.
        try await Task.sleep(for: .milliseconds(100))
        coordinator.removeAll()
        XCTAssertEqual(coordinator.observerCount, 0)
    }

    func testRemoveAllPreventsAllNotifications() async throws {
        let expectation1 = XCTestExpectation(description: "First notification received")
        expectation1.isInverted = true // Should NOT be fulfilled
        let expectation2 = XCTestExpectation(description: "Second notification received")
        expectation2.isInverted = true // Should NOT be fulfilled

        coordinator.observe(testNotificationName) { _ in
            expectation1.fulfill()
        }
        coordinator.observe(Notification.Name("Second")) { _ in
            expectation2.fulfill()
        }

        coordinator.removeAll()

        NotificationCenter.default.post(name: testNotificationName, object: nil)
        NotificationCenter.default.post(name: Notification.Name("Second"), object: nil)

        await fulfillment(of: [expectation1, expectation2], timeout: 0.1)
    }
}
