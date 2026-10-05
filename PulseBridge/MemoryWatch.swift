import Darwin
import Foundation

/// The app's memory footprint (what iOS uses to decide when to kill it), for the diagnostics log.
enum MemoryWatch {
    static func footprintMB() -> Int? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.phys_footprint / 1_048_576)
    }

    /// One line per minute while the app runs; `reason` lines for screen changes.
    @MainActor
    static func start(log: @escaping (String) -> Void) {
        Task {
            while !Task.isCancelled {
                if let mb = footprintMB() { log("memory \(mb) MB") }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
