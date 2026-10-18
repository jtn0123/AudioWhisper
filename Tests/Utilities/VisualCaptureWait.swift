import XCTest

/// Do not write a named capture unless its expected state actually arrived.
@MainActor
func requireVisualState(
    _ description: String, timeout: Duration = .seconds(3),
    file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    _ = try XCTUnwrap(condition() ? true : nil, "\(description) did not arrive before capture", file: file, line: line)
}
