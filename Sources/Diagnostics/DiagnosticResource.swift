import Darwin
import Foundation

struct DiagnosticResource: Codable, Equatable, Sendable {
    enum Scope: String, Codable, Sendable { case application, modelWorker }
    var scope: Scope
    var elapsedMilliseconds: Double
    var cpuSeconds: Double
    var residentBytes: UInt64
    var thermalState: Int
    var cpuIsCumulative = true
    var memoryIsPeak = false

    static func application(since start: TimeInterval) -> Self? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let seconds = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return .init(scope: .application,
                     elapsedMilliseconds: max(0, (ProcessInfo.processInfo.systemUptime - start) * 1_000),
                     cpuSeconds: seconds, residentBytes: info.resident_size,
                     thermalState: ProcessInfo.processInfo.thermalState.rawValue)
    }
}
