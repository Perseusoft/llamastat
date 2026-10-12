import Darwin
import Foundation
import IOKit

struct MemorySnapshot: Sendable {
    var total: UInt64
    /// App + wired + compressed, the same "used" Activity Monitor and Stats show.
    var used: UInt64
    var wired: UInt64
    var compressed: UInt64
    var swapUsed: UInt64
    var swapTotal: UInt64
    var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

struct GPUSnapshot: Sendable {
    var utilization: Double
    /// Unified memory the GPU driver currently has allocated.
    var memoryInUse: UInt64?
}

enum SystemStats {
    static func memory() -> MemorySnapshot {
        var total: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &size, nil, 0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let page = UInt64(vm_kernel_page_size)
        var snapshot = MemorySnapshot(total: total, used: 0, wired: 0, compressed: 0, swapUsed: 0, swapTotal: 0)
        if result == KERN_SUCCESS {
            let app = UInt64(stats.internal_page_count - stats.purgeable_count) * page
            snapshot.wired = UInt64(stats.wire_count) * page
            snapshot.compressed = UInt64(stats.compressor_page_count) * page
            snapshot.used = app + snapshot.wired + snapshot.compressed
        }

        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            snapshot.swapUsed = swap.xsu_used
            snapshot.swapTotal = swap.xsu_total
        }
        return snapshot
    }

    /// Reads the Apple Silicon GPU's PerformanceStatistics from the IORegistry (no root needed).
    static func gpu() -> GPUSnapshot? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            let ok = IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS
            IOObjectRelease(service)
            if ok, let dict = props?.takeRetainedValue() as? [String: Any],
               let perf = dict["PerformanceStatistics"] as? [String: Any],
               let utilization = (perf["Device Utilization %"] as? NSNumber)?.doubleValue {
                let inUse = (perf["In use system memory"] as? NSNumber)?.uint64Value
                return GPUSnapshot(utilization: utilization / 100, memoryInUse: inUse)
            }
            service = IOIteratorNext(iterator)
        }
        return nil
    }
}

struct ProcessSample: Sendable {
    var pid: pid_t
    var residentBytes: UInt64
    var footprintBytes: UInt64
    /// Cumulative user+system CPU time in nanoseconds.
    var cpuNanos: UInt64
}

enum ProcessScanner {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    /// First process whose executable name matches and whose argv contains all the given strings, in order.
    static func find(_ match: ProcessMatch) -> ProcessSample? {
        for pid in allPIDs() where name(of: pid) == match.executableName {
            guard let args = arguments(of: pid), containsSequence(args, match.argumentContains) else { continue }
            return sample(pid)
        }
        return nil
    }

    static func sample(_ pid: pid_t) -> ProcessSample? {
        var usage = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) == 0
            }
        }
        guard ok else { return nil }
        var task = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.size)
        let resident = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, taskSize) == taskSize ? task.pti_resident_size : 0
        let ticks = usage.ri_user_time + usage.ri_system_time
        return ProcessSample(
            pid: pid,
            residentBytes: resident,
            footprintBytes: usage.ri_phys_footprint,
            cpuNanos: ticks * UInt64(timebase.numer) / UInt64(timebase.denom)
        )
    }

    private static func allPIDs() -> [pid_t] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        return Array(pids.prefix(Int(max(filled, 0))))
    }

    private static func name(of pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        return String(cString: buffer)
    }

    /// argv via KERN_PROCARGS2: [argc: Int32][exec path\0][padding \0...][argv0\0][argv1\0]...
    private static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }

        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // exec path
        while index < size, buffer[index] == 0 { index += 1 }   // padding

        var args: [String] = []
        var start = index
        while index < size, args.count < argc {
            if buffer[index] == 0 {
                args.append(String(decoding: buffer[start..<index], as: UTF8.self))
                start = index + 1
            }
            index += 1
        }
        return args
    }

    private static func containsSequence(_ args: [String], _ needles: [String]) -> Bool {
        guard let first = needles.first else { return true }
        if needles.count == 2, let i = args.firstIndex(of: first) {
            return i + 1 < args.count && args[i + 1] == needles[1]
        }
        return needles.allSatisfy { needle in args.contains { $0.contains(needle) } }
    }
}
