/// Fixed-capacity ring buffer holding the most recent `capacity` mono samples.
///
/// Audit item G1. The recorder previously kept the recent-sample window in a
/// plain `[Float]` and, on **every** audio callback, ran:
///
/// ```swift
/// sampleBuffer.append(contentsOf: monoSamples)
/// if sampleBuffer.count > sampleBufferSize {
///     sampleBuffer = Array(sampleBuffer.suffix(sampleBufferSize))  // allocates
/// }
/// let currentBuffer = sampleBuffer                                  // copies
/// ```
///
/// That is two ~8 KB heap allocations plus a full 2,048-element copy per
/// callback — roughly 94 times a second at a 512-frame buffer and 48 kHz — while
/// holding a lock the main actor also contends for. Crucially it ran
/// *unthrottled*, outside the 60 Hz publish gate, so it paid the cost even on
/// callbacks whose data was about to be discarded. Allocation on the realtime
/// audio thread is the classic source of dropouts under memory pressure; the
/// comment calling `suffix` "efficient" described the API, not the allocation.
///
/// Storage here is allocated once at init. Steady-state writes are plain
/// element assignments into that preallocated array — no allocation, no copy.
/// The one remaining allocation is `snapshot()`, which the recorder now calls
/// only when it actually publishes (60 Hz) rather than on every callback.
///
/// Not thread-safe on its own: the recorder guards it with `sampleBufferLock`,
/// exactly as it guarded the array before.
internal struct SampleRingBuffer {
    private var storage: [Float]
    /// Where the next sample is written. Once `filled == capacity` this is also
    /// the index of the OLDEST sample.
    private var writeIndex = 0
    private var filled = 0

    let capacity: Int

    init(capacity: Int) {
        precondition(capacity > 0, "SampleRingBuffer needs a positive capacity")
        self.capacity = capacity
        self.storage = [Float](repeating: 0, count: capacity)
    }

    /// Number of samples currently held (saturates at `capacity`).
    var count: Int { filled }

    var isEmpty: Bool { filled == 0 }

    /// Appends `samples`, overwriting the oldest entries once full.
    ///
    /// A single callback delivering more than `capacity` samples keeps only the
    /// last `capacity` of them — the same result the old `suffix` produced. The
    /// leading samples are skipped by index rather than sliced, so this stays
    /// allocation-free in that case too.
    mutating func append(contentsOf samples: [Float]) {
        let total = samples.count
        guard total > 0 else { return }

        let start = total > capacity ? total - capacity : 0
        for index in start..<total {
            storage[writeIndex] = samples[index]
            writeIndex += 1
            if writeIndex == capacity { writeIndex = 0 }
        }
        filled = min(filled + (total - start), capacity)
    }

    /// The held samples in oldest-to-newest order.
    ///
    /// This is the only allocating operation. Call it when the data is actually
    /// going to be used, not on every write.
    func snapshot() -> [Float] {
        guard filled > 0 else { return [] }

        // Not yet wrapped: samples sit contiguously at the front, and
        // `writeIndex` equals `filled`.
        guard filled == capacity else {
            return Array(storage[0..<filled])
        }

        // Wrapped: oldest sample is at `writeIndex`.
        var out = [Float]()
        out.reserveCapacity(capacity)
        out.append(contentsOf: storage[writeIndex..<capacity])
        out.append(contentsOf: storage[0..<writeIndex])
        return out
    }

    /// Drops all held samples. Leaves the storage allocated so the next
    /// recording session does not re-allocate.
    mutating func removeAll() {
        writeIndex = 0
        filled = 0
    }
}
