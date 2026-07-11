import Darwin
import Foundation

/// CPU-pressure companion to `SystemMemory`, used by `auto` mode to decide whether the machine
/// is busy enough that offloading transcription to a remote provider is worthwhile.
extension SystemMemory {
    /// 1-minute load average normalized per active core (≈ utilization; 1.0 ≈ fully loaded).
    ///
    /// Returns `0` on failure — the safe, privacy-biased branch: "not busy" keeps work local
    /// rather than silently uploading audio because a syscall failed.
    static func loadAveragePerCore() -> Double {
        var loads = [Double](repeating: 0, count: 3)
        let sampled = getloadavg(&loads, 3)
        guard sampled > 0 else { return 0 }
        let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
        return loads[0] / Double(cores)
    }
}
