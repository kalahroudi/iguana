import Foundation
import IOKit
import IguanaKit

struct StatsSample {
    var cpu: Double            // 0...1
    var ram: Double            // used / total
    var ramUsed: UInt64, ramTotal: UInt64
    var gpu: Double?           // 0...1, nil if the driver does not report it
    var vramUsed: UInt64?      // GPU memory in use (shared with RAM on Apple Silicon)
}

/// Cheap system counters, read straight from the kernel and the GPU driver. Only sampled while the popover is open.
final class StatsReader {
    private var lastTicks: CPUTicks?
    private let total = ProcessInfo.processInfo.physicalMemory

    func sample() -> StatsSample {
        let t = cpuTicks()
        let cpu = lastTicks.map { t.load(since: $0) } ?? 0
        lastTicks = t
        let used = ramUsed()
        let g = gpuStats()
        return StatsSample(cpu: cpu, ram: Double(used) / Double(total), ramUsed: used, ramTotal: total, gpu: g.util, vramUsed: g.mem)
    }

    private func cpuTicks() -> CPUTicks {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count) } }
        return CPUTicks(user: UInt64(info.cpu_ticks.0), system: UInt64(info.cpu_ticks.1), idle: UInt64(info.cpu_ticks.2), nice: UInt64(info.cpu_ticks.3))
    }

    /// App memory + wired + compressed: what Activity Monitor calls "Memory Used".
    private func ramUsed() -> UInt64 {
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        _ = withUnsafeMutablePointer(to: &vm) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) } }
        let pages = UInt64(vm.internal_page_count) - UInt64(vm.purgeable_count) + UInt64(vm.wire_count) + UInt64(vm.compressor_page_count)
        return pages * UInt64(vm_kernel_page_size)
    }

    private func gpuStats() -> (util: Double?, mem: UInt64?) {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return (nil, nil) }
        defer { IOObjectRelease(it) }
        var util: Double?, mem: UInt64?
        while case let svc = IOIteratorNext(it), svc != 0 {
            defer { IOObjectRelease(svc) }
            guard let props = IORegistryEntryCreateCFProperty(svc, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any] else { continue }
            if let u = (props["Device Utilization %"] ?? props["GPU Activity(%)"]) as? Int { util = max(util ?? 0, Double(u) / 100) }
            if let m = (props["In use system memory"] ?? props["vramUsedBytes"]) as? UInt64 { mem = max(mem ?? 0, m) }
            else if let m = (props["In use system memory"] ?? props["vramUsedBytes"]) as? Int { mem = max(mem ?? 0, UInt64(m)) }
        }
        return (util, mem)
    }
}

func formatBytes(_ b: UInt64) -> String {
    let g = Double(b) / 1_073_741_824
    return g >= 10 ? String(format: "%.0f GB", g) : g >= 1 ? String(format: "%.1f GB", g) : String(format: "%.0f MB", Double(b) / 1_048_576)
}
