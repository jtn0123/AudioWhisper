import XCTest
@testable import AudioWhisper

/// Tests for the recorder's fixed-capacity sample window.
///
/// Audit item G1: this replaced an append-then-`Array(suffix(...))` pattern that
/// allocated twice per audio callback on the realtime thread. The behaviour that
/// must be preserved is exactly what `suffix` gave: keep the most recent
/// `capacity` samples, in order, and nothing older.
final class SampleRingBufferTests: XCTestCase {

    func testStartsEmpty() {
        let buffer = SampleRingBuffer(capacity: 4)
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.count, 0)
        XCTAssertEqual(buffer.snapshot(), [])
    }

    func testHoldsSamplesInOrderBeforeWrapping() {
        var buffer = SampleRingBuffer(capacity: 4)
        buffer.append(contentsOf: [1, 2, 3])

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.snapshot(), [1, 2, 3])
    }

    func testFillingExactlyToCapacityKeepsEverything() {
        var buffer = SampleRingBuffer(capacity: 4)
        buffer.append(contentsOf: [1, 2, 3, 4])

        XCTAssertEqual(buffer.count, 4)
        XCTAssertEqual(buffer.snapshot(), [1, 2, 3, 4])
    }

    /// The core contract: oldest samples fall off, order is preserved.
    func testWrappingDropsOldestAndPreservesOrder() {
        var buffer = SampleRingBuffer(capacity: 4)
        buffer.append(contentsOf: [1, 2, 3, 4])
        buffer.append(contentsOf: [5, 6])

        XCTAssertEqual(buffer.count, 4, "count saturates at capacity")
        XCTAssertEqual(buffer.snapshot(), [3, 4, 5, 6])
    }

    /// A single write larger than the whole buffer must keep only its tail —
    /// matching what `Array(samples.suffix(capacity))` produced.
    func testWriteLargerThanCapacityKeepsOnlyTheMostRecentSamples() {
        var buffer = SampleRingBuffer(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3, 4, 5, 6, 7])

        XCTAssertEqual(buffer.count, 3)
        XCTAssertEqual(buffer.snapshot(), [5, 6, 7])
    }

    func testWriteLargerThanCapacityOverAnAlreadyFullBuffer() {
        var buffer = SampleRingBuffer(capacity: 3)
        buffer.append(contentsOf: [1, 2, 3])
        buffer.append(contentsOf: [4, 5, 6, 7, 8])

        XCTAssertEqual(buffer.snapshot(), [6, 7, 8])
    }

    func testManySmallWritesBehaveLikeASlidingWindow() {
        var buffer = SampleRingBuffer(capacity: 5)
        for value in 1...20 {
            buffer.append(contentsOf: [Float(value)])
        }
        XCTAssertEqual(buffer.snapshot(), [16, 17, 18, 19, 20])
    }

    /// Equivalence check against the implementation this replaced, across write
    /// sizes that do and do not divide the capacity.
    func testMatchesTheSuffixSemanticsItReplaced() {
        for chunkSize in [1, 3, 7, 16] {
            let capacity = 8
            var buffer = SampleRingBuffer(capacity: capacity)
            var reference: [Float] = []

            var next: Float = 0
            for _ in 0..<10 {
                let chunk = (0..<chunkSize).map { _ -> Float in next += 1; return next }
                buffer.append(contentsOf: chunk)
                reference.append(contentsOf: chunk)
                if reference.count > capacity {
                    reference = Array(reference.suffix(capacity))
                }
            }

            XCTAssertEqual(buffer.snapshot(), reference,
                           "ring buffer diverged from suffix semantics at chunkSize \(chunkSize)")
        }
    }

    func testEmptyWriteIsANoOp() {
        var buffer = SampleRingBuffer(capacity: 4)
        buffer.append(contentsOf: [1, 2])
        buffer.append(contentsOf: [])

        XCTAssertEqual(buffer.snapshot(), [1, 2])
    }

    func testRemoveAllDropsEverythingAndAllowsReuse() {
        var buffer = SampleRingBuffer(capacity: 4)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])
        buffer.removeAll()

        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.snapshot(), [])

        // Reuse after clearing must not resurrect stale samples from storage.
        buffer.append(contentsOf: [9, 8])
        XCTAssertEqual(buffer.snapshot(), [9, 8])
    }

    /// Snapshotting must not consume: the recorder reads at 60 Hz while the
    /// audio thread keeps writing.
    func testSnapshotIsNonDestructive() {
        var buffer = SampleRingBuffer(capacity: 4)
        buffer.append(contentsOf: [1, 2, 3, 4, 5])

        let first = buffer.snapshot()
        let second = buffer.snapshot()

        XCTAssertEqual(first, second)
        XCTAssertEqual(buffer.count, 4)
    }

    /// The recorder's real capacity, exercised with a realistic callback size.
    func testRealisticCapacityAndCallbackSize() {
        var buffer = SampleRingBuffer(capacity: 2048)
        var next: Float = 0
        for _ in 0..<20 {
            let chunk = (0..<512).map { _ -> Float in next += 1; return next }
            buffer.append(contentsOf: chunk)
        }

        let snapshot = buffer.snapshot()
        XCTAssertEqual(snapshot.count, 2048)
        XCTAssertEqual(snapshot.last, next, "newest sample must be last")
        XCTAssertEqual(snapshot.first, next - 2047, "oldest retained sample must be first")
    }
}
