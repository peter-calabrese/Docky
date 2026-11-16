import Foundation

// Window IDs, rather than frames or stacking order, determine AX subscription repair.
enum MonitoringPolicy {
    static func changedOwners(previous: [Int32: Set<UInt32>], current: [Int32: Set<UInt32>]) -> Set<Int32> {
        Set(previous.keys).union(current.keys).filter { previous[$0, default: []] != current[$0, default: []] }
    }
}

struct MonitoringSleepState {
    var systemSleeping = false
    var displaysSleeping = false
    var isSuspended: Bool { systemSleeping || displaysSleeping }
}
