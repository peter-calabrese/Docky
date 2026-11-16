import AppKit
import ApplicationServices

@MainActor
final class WindowMonitor {
    private struct Subscription {
        let observer: AXObserver
        let application: AXUIElement
        var windows: [AXUIElement]
    }
    private var isRunning = false
    private var subscriptions: [pid_t: Subscription] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var displayToken: NSObjectProtocol?
    private var windowIDs: [Int32: Set<UInt32>] = [:]
    private var pendingRepairs: Set<pid_t> = []
    private var lastRepair: [pid_t: Date] = [:]
    private var dockPID: pid_t?
    private var sleepState = MonitoringSleepState()
    var onChange: (() -> Void)?
    var onEnvironmentChange: (() -> Void)?
    var onSleepChange: ((Bool) -> Void)?
    private(set) var isSuspended = false

    func start() {
        stop()
        isRunning = true
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let event = note.name
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                Task { @MainActor [weak self] in self?.workspaceChanged(event, pid: pid) }
            })
        }
        displayToken = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                             object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, !self.isSuspended else { return }
                self.onEnvironmentChange?()
                self.onChange?()
            }
        }
        refreshApplications()
    }

    func stop() {
        isRunning = false
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        if let displayToken { NotificationCenter.default.removeObserver(displayToken) }
        displayToken = nil
        for subscription in subscriptions.values {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(subscription.observer), .commonModes)
        }
        subscriptions.removeAll()
        windowIDs.removeAll()
        pendingRepairs.removeAll()
        lastRepair.removeAll()
        dockPID = nil
        sleepState = MonitoringSleepState()
        isSuspended = false
    }

    private func workspaceChanged(_ name: Notification.Name, pid: pid_t?) {
        guard isRunning else { return }
        switch name {
        case NSWorkspace.willSleepNotification: sleepState.systemSleeping = true
        case NSWorkspace.didWakeNotification: sleepState.systemSleeping = false
        case NSWorkspace.screensDidSleepNotification: sleepState.displaysSleeping = true
        case NSWorkspace.screensDidWakeNotification: sleepState.displaysSleeping = false
        default: break
        }
        let suspended = sleepState.isSuspended
        if suspended != isSuspended {
            isSuspended = suspended
            for subscription in subscriptions.values {
                let source = AXObserverGetRunLoopSource(subscription.observer)
                if suspended { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
                else { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
            }
            if !suspended {
                windowIDs.removeAll()
                lastRepair.removeAll()
            }
            onSleepChange?(suspended)
        }
        guard isRunning, !isSuspended else { return }
        refreshApplications()
        if let pid, subscriptions[pid] != nil {
            pendingRepairs.insert(pid)
            repairPendingWindows()
        }
        if name == NSWorkspace.activeSpaceDidChangeNotification ||
           name == NSWorkspace.didWakeNotification || name == NSWorkspace.screensDidWakeNotification {
            onEnvironmentChange?()
        }
        onChange?()
    }

    func refreshApplications() {
        guard isRunning, !isSuspended else { return }
        let applications = NSWorkspace.shared.runningApplications.filter {
            ($0.activationPolicy == .regular || $0.bundleIdentifier == "com.apple.dock") &&
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        let live = Set(applications.map(\.processIdentifier))
        for pid in Array(subscriptions.keys) where !live.contains(pid) {
            if let subscription = subscriptions.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(subscription.observer), .commonModes)
            }
            pendingRepairs.remove(pid)
            lastRepair.removeValue(forKey: pid)
            windowIDs.removeValue(forKey: pid)
        }
        let currentDockPID = applications.first { $0.bundleIdentifier == "com.apple.dock" }?.processIdentifier
        if currentDockPID != dockPID { dockPID = currentDockPID; onEnvironmentChange?() }
        for application in applications where subscriptions[application.processIdentifier] == nil {
            let pid = application.processIdentifier
            var observer: AXObserver?
            guard AXObserverCreate(pid, { _, element, notification, context in
                guard let context else { return }
                let monitor = Unmanaged<WindowMonitor>.fromOpaque(context).takeUnretainedValue()
                let name = notification as String
                var owner: pid_t = 0
                AXUIElementGetPid(element, &owner)
                let ownerPID = owner
                Task { @MainActor [weak monitor] in monitor?.windowChanged(name, pid: ownerPID) }
            }, &observer) == .success, let observer else { continue }
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 0.05)
            subscriptions[pid] = Subscription(observer: observer, application: element, windows: [])
            let context = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification,
                         kAXApplicationHiddenNotification, kAXApplicationShownNotification] {
                AXObserverAddNotification(observer, element, name as CFString, context)
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
            pendingRepairs.insert(pid)
        }
        repairPendingWindows()
    }

    private func windowChanged(_ name: String, pid: pid_t) {
        guard isRunning, !isSuspended, subscriptions[pid] != nil else { return }
        if name == kAXWindowCreatedNotification || name == kAXUIElementDestroyedNotification {
            pendingRepairs.insert(pid)
            repairPendingWindows()
        }
        if pid == dockPID { onEnvironmentChange?() }
        onChange?()
    }

    // Reuse the controller's existing Core Graphics snapshot. An unchanged window
    // list does no AX repair work, regardless of movement or front-to-back order.
    func reconcileWindowIDs(_ current: [Int32: Set<UInt32>]) {
        guard isRunning, !isSuspended else { return }
        pendingRepairs.formUnion(MonitoringPolicy.changedOwners(previous: windowIDs, current: current)
            .filter { subscriptions[$0] != nil })
        windowIDs = current
        repairPendingWindows()
    }

    private func repairPendingWindows() {
        guard isRunning, !isSuspended else { return }
        for pid in Array(pendingRepairs) {
            guard Date().timeIntervalSince(lastRepair[pid] ?? .distantPast) >= 2 else { continue }
            lastRepair[pid] = Date()
            if refreshWindows(for: pid) { pendingRepairs.remove(pid) }
        }
    }

    private func refreshWindows(for pid: pid_t) -> Bool {
        guard var subscription = subscriptions[pid] else { return true }
        var value: CFTypeRef?
        let attributeName = pid == dockPID ? kAXChildrenAttribute : kAXWindowsAttribute
        guard AXUIElementCopyAttributeValue(subscription.application, attributeName as CFString, &value) == .success,
              var windows = value as? [AXUIElement] else { return false }
        if pid == dockPID {
            windows = windows.filter { element in
                var role: CFTypeRef?
                return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role) == .success &&
                    role as? String == kAXListRole
            }
        }
        let names = [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification]
        for old in subscription.windows where !windows.contains(where: { CFEqual($0, old) }) {
            for name in names { AXObserverRemoveNotification(subscription.observer, old, name as CFString) }
        }
        for window in windows where !subscription.windows.contains(where: { CFEqual($0, window) }) {
            AXUIElementSetMessagingTimeout(window, 0.05)
            for name in names {
                AXObserverAddNotification(subscription.observer, window, name as CFString,
                                          Unmanaged.passUnretained(self).toOpaque())
            }
        }
        subscription.windows = windows
        subscriptions[pid] = subscription
        return true
    }
}
