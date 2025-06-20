// MemoryUtils.swift
// Utility for reporting resident (real) memory usage in MB, matching Xcode profiler

import Foundation
import MachO

struct MemoryUtils {
    /// Returns the resident (physical) memory used by the process, in bytes
    static func residentMemoryBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }
    /// Returns a formatted string for MB usage, or nil if unavailable
    static func residentMemoryMBString() -> String? {
        guard let bytes = residentMemoryBytes() else { return nil }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "App uses %.2f MB", mb)
    }
}
