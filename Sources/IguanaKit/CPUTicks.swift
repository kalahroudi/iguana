import Foundation

/// Cumulative CPU time counters. Load between two samples is busy / elapsed.
public struct CPUTicks: Equatable, Sendable {
    public var user, system, idle, nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) { self.user = user; self.system = system; self.idle = idle; self.nice = nice }
    var total: UInt64 { user + system + idle + nice }
    public func load(since old: CPUTicks) -> Double {
        let dt = total &- old.total
        guard dt > 0 else { return 0 }
        let dIdle = idle &- old.idle
        return Double(dt - min(dIdle, dt)) / Double(dt)
    }
}
