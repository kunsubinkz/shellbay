import Foundation

public struct CPUTimes: Equatable, Sendable { public var total: UInt64; public var idle: UInt64 }
public struct MemInfo: Equatable, Sendable { public var totalKB: UInt64; public var availableKB: UInt64
    public var usedGiB: Double { Double(totalKB - min(availableKB, totalKB)) / 1_048_576 }
    public var totalGiB: Double { Double(totalKB) / 1_048_576 }
    public var percent: Double { totalKB == 0 ? 0 : Double(totalKB - min(availableKB, totalKB)) / Double(totalKB) * 100 }
}
public struct DiskInfo: Equatable, Sendable { public var totalBytes: UInt64; public var usedBytes: UInt64
    public var percent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }
}
public struct ProcRow: Identifiable, Equatable, Sendable { public var id: Int { pid }
    public var pid: Int; public var user: String; public var cpu: Double; public var mem: Double; public var command: String }

public struct MetricsSample: Sendable {
    public var cpu: CPUTimes; public var mem: MemInfo; public var uptime: TimeInterval
    public var disk: DiskInfo?; public var procs: [ProcRow]
}

public enum ProcParsers {
    /// Parses the aggregate `cpu ` line of /proc/stat.
    public static func parseCPU(_ text: String) -> CPUTimes? {
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("cpu ") }) else { return nil }
        let nums = line.split(separator: " ").dropFirst().compactMap { UInt64($0) }
        guard nums.count >= 4 else { return nil }
        let idle = nums[3] + (nums.count > 4 ? nums[4] : 0)
        return CPUTimes(total: nums.reduce(0, +), idle: idle)
    }

    /// CPU% between two readings of /proc/stat.
    public static func cpuPercent(prev: CPUTimes, cur: CPUTimes) -> Double {
        let dt = Double(cur.total &- prev.total), di = Double(cur.idle &- prev.idle)
        guard dt > 0 else { return 0 }
        return max(0, min(100, (dt - di) / dt * 100))
    }

    public static func parseMem(_ text: String) -> MemInfo? {
        func val(_ key: String) -> UInt64? {
            guard let l = text.split(separator: "\n").first(where: { $0.hasPrefix(key + ":") }) else { return nil }
            return l.split(separator: " ").dropFirst().first.flatMap { UInt64($0) }
        }
        guard let t = val("MemTotal") else { return nil }
        return MemInfo(totalKB: t, availableKB: val("MemAvailable") ?? val("MemFree") ?? 0)
    }

    public static func parseUptime(_ text: String) -> TimeInterval? {
        text.split(separator: "\n").lazy.compactMap { l -> TimeInterval? in
            let f = l.split(separator: " ")
            guard f.count == 2, let a = Double(f[0]), Double(f[1]) != nil else { return nil }
            return a
        }.first
    }

    /// Parses `df -B1 /` output.
    public static func parseDisk(_ text: String) -> DiskInfo? {
        for l in text.split(separator: "\n") {
            let f = l.split(separator: " ", omittingEmptySubsequences: true)
            if f.count >= 4, let t = UInt64(f[1]), let u = UInt64(f[2]) { return DiskInfo(totalBytes: t, usedBytes: u) }
        }
        return nil
    }

    /// Parses `ps -eo pid,user,%cpu,%mem,args --sort=-%cpu`.
    public static func parsePS(_ text: String, limit: Int = 8) -> [ProcRow] {
        var rows: [ProcRow] = []
        for l in text.split(separator: "\n") {
            let f = l.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard f.count == 5, let pid = Int(f[0]), let c = Double(f[2]), let m = Double(f[3]) else { continue }
            rows.append(ProcRow(pid: pid, user: String(f[1]), cpu: c, mem: m, command: String(f[4])))
        }
        return Array(rows.sorted { $0.cpu > $1.cpu }.prefix(limit))
    }

    /// Splits the combined output produced by `HostMetricsCommand`.
    public static func parseCombined(_ out: String) -> (cpu: CPUTimes, mem: MemInfo, uptime: TimeInterval, disk: DiskInfo?, procs: [ProcRow])? {
        let parts = out.components(separatedBy: "@@SB@@")
        guard parts.count >= 5, let cpu = parseCPU(parts[0]), let mem = parseMem(parts[1]), let up = parseUptime(parts[2]) else { return nil }
        return (cpu, mem, up, parseDisk(parts[3]), parsePS(parts[4]))
    }

    public static let metricsCommand = "cat /proc/stat; echo @@SB@@; cat /proc/meminfo; echo @@SB@@; cat /proc/uptime; echo @@SB@@; df -B1 / | tail -n +2; echo @@SB@@; ps -eo pid,user,%cpu,%mem,args --sort=-%cpu | head -9"

    public static func formatUptime(_ s: TimeInterval) -> String {
        let t = Int(s); let d = t / 86400, h = t % 86400 / 3600, m = t % 3600 / 60, sec = t % 60
        return d > 0 ? "\(d)d \(h)h \(m)m" : (h > 0 ? "\(h)h \(m)m \(sec)s" : "\(m)m \(sec)s")
    }
}
