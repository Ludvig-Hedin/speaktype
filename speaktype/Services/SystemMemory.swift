import Darwin
import Foundation

/// Lightweight wrapper around Mach VM statistics for memory-aware decisions.
///
/// **Why:** On low-RAM Macs we want to decide *at runtime* whether to keep the Whisper
/// model resident in memory or load it lazily. That requires knowing how much physical
/// memory is actually free right now, not just the total installed RAM.
enum SystemMemory {
    /// Total installed physical memory, in gigabytes (cached — it never changes).
    static let totalMemoryGB: Double = {
        Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824.0
    }()

    /// Approximate physically free + reclaimable memory, in gigabytes.
    ///
    /// Sums free, inactive and purgeable pages — memory the kernel can hand to a fresh
    /// allocation without paging out an active working set. Returns 0 if the Mach call fails,
    /// which callers treat as "no headroom" (the safe, low-memory branch).
    static func availableMemoryGB() -> Double {
        let host = mach_host_self()
        // `mach_host_self()` hands back a send right that must be balanced, or each call
        // leaks a port reference. This is invoked at launch and on every keep-resident check.
        defer { mach_port_deallocate(mach_task_self_, host) }

        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS else { return 0 }

        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )

        let result = withUnsafeMutablePointer(to: &stats) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPointer in
                host_statistics64(host, HOST_VM_INFO64, intPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let reclaimablePages = Double(stats.free_count)
            + Double(stats.inactive_count)
            + Double(stats.purgeable_count)
        let bytes = reclaimablePages * Double(pageSize)
        return bytes / 1_073_741_824.0
    }
}
