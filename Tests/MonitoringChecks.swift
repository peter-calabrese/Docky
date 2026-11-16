import Foundation

@main
struct MonitoringChecks {
    static func main() {
        let before: [Int32: Set<UInt32>] = [101: [1, 2], 202: [3]]
        // Switching focus/reordering the same windows must do no subscription work.
        precondition(MonitoringPolicy.changedOwners(previous: before, current: [202: [3], 101: [2, 1]]).isEmpty)
        // New, closed, minimized, and restored windows repair only affected owners.
        precondition(MonitoringPolicy.changedOwners(previous: before, current: [101: [1, 2, 4], 202: [3]]) == [101])
        precondition(MonitoringPolicy.changedOwners(previous: before, current: [101: [1, 2]]) == [202])
        precondition(MonitoringPolicy.changedOwners(previous: before, current: [101: [1, 2], 202: [3], 303: [5]]) == [303])
        precondition(MonitoringPolicy.changedOwners(previous: [101: []], current: [:]).isEmpty)
        precondition(MonitoringPolicy.changedOwners(previous: [:], current: before) == [101, 202])
        // A system wake must not resume polling before the displays wake, or vice versa.
        var sleep = MonitoringSleepState()
        precondition(!sleep.isSuspended)
        sleep.displaysSleeping = true
        precondition(sleep.isSuspended)
        sleep.systemSleeping = true
        sleep.displaysSleeping = false
        precondition(sleep.isSuspended)
        sleep.systemSleeping = false
        precondition(!sleep.isSuspended)
        sleep.systemSleeping = true
        sleep.displaysSleeping = true
        sleep.systemSleeping = false
        precondition(sleep.isSuspended)
        sleep.displaysSleeping = false
        precondition(!sleep.isSuspended)
        print("Passed monitoring checks (targeted repairs and sleep/wake ordering)")
    }
}
