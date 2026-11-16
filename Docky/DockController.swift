import AppKit
import ApplicationServices
import Combine

@MainActor
final class DockController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Ready — enable Smart Dock to begin"
    @Published private(set) var error: String?
    @Published private(set) var hasSavedSetting = UserDefaults.standard.object(forKey: "originalDockAutohide") != nil
    @Published var expandWindowsIntoDockSpace = UserDefaults.standard.bool(forKey: "expandMaximizedWindows") {
        didSet { UserDefaults.standard.set(expandWindowsIntoDockSpace, forKey: "expandMaximizedWindows"); requestEvaluation() }
    }
    @Published var windowGap = min(200, max(0, UserDefaults.standard.integer(forKey: "windowGap"))) {
        didSet { UserDefaults.standard.set(windowGap, forKey: "windowGap"); requestEvaluation() }
    }
    // Retain visible-Dock work areas while hidden to avoid a hide/show feedback loop.
    private var reservedWorkAreas: [String: CGRect] = [:]
    private var generation = 0
    private let automation = DockAutomation()
    private var timer: Timer?
    private var monitoringSuspended = false
    private let dockPreferences = UserDefaults(suiteName: "com.apple.dock")
    private struct CachedDockGeometry {
        let measured: CGRect?
        let screens: [CGRect]
        let edge: String
        let thickness: CGFloat
        let capturedAt: Date
    }
    private var cachedDockGeometry: CachedDockGeometry?
    private let windowMonitor = WindowMonitor()
    private var evaluationTask: Task<Void, Never>?
    private var evaluationDeadline: Date?
    private var needsEvaluation = false
    private var evaluating = false
    private var expansionCandidate: (window: AXUIElement, frame: CGRect, target: CGRect, since: Date)?
    private var lastExpansionAttempt: (window: AXUIElement, frame: CGRect)?
    private var lastHidden: Bool?
    private var pendingDecision: Bool?
    private var decisionSince = Date.distantPast
    private let recoveryKey = "originalDockAutohide"

    func setEnabled(_ value: Bool) async {
        guard !busy else { return }
        if !value { await stop(); return }
        guard !enabled else { return }
        guard AXIsProcessTrusted() else {
            error = "Allow Docky in Accessibility, then enable Smart Dock again."
            openAccessibility()
            return
        }
        generation += 1
        let operation = generation
        busy = true
        error = nil
        do {
            let original = try await automation.read()
            guard operation == generation else { return }
            // Keep a recovery record across a crash or force quit.
            if UserDefaults.standard.object(forKey: recoveryKey) == nil {
                UserDefaults.standard.set(original, forKey: recoveryKey)
            }
            hasSavedSetting = true
            lastHidden = original
            pendingDecision = nil
            reservedWorkAreas.removeAll()
            expansionCandidate = nil
            lastExpansionAttempt = nil
            enabled = true
            cachedDockGeometry = nil
            monitoringSuspended = false
            windowMonitor.onChange = { [weak self] in self?.requestEvaluation() }
            windowMonitor.onEnvironmentChange = { [weak self] in
                self?.cachedDockGeometry = nil
                self?.requestEvaluation()
            }
            windowMonitor.onSleepChange = { [weak self] suspended in self?.setMonitoringSuspended(suspended) }
            windowMonitor.start()
            startFallbackTimer()
            status = "Watching on-screen windows"
            requestEvaluation()
        } catch {
            guard operation == generation else { return }
            self.error = error.localizedDescription
        }
        busy = false
    }

    func stop() async {
        generation += 1
        let operation = generation
        // A Dock change already in flight is serialized before restoration by the actor.
        enabled = false
        stopMonitoring()
        busy = true
        error = nil
        if let original = UserDefaults.standard.object(forKey: recoveryKey) as? Bool {
            do {
                try await automation.write(original)
                guard operation == generation else { return }
                UserDefaults.standard.removeObject(forKey: recoveryKey)
                hasSavedSetting = false
                lastHidden = nil
            } catch {
                guard operation == generation else { return }
                self.error = "Could not restore your Dock setting. \(error.localizedDescription) Retry by disabling or quitting Docky again."
            }
        }
        guard operation == generation else { return }
        pendingDecision = nil
        expansionCandidate = nil
        lastExpansionAttempt = nil
        status = error == nil ? "Smart Dock is off" : "Paused — restore your Dock setting"
        busy = false
    }

    private func evaluate() async {
        guard enabled, !busy, !monitoringSuspended else { return }
        guard !evaluating else { needsEvaluation = true; return }
        guard AXIsProcessTrusted() else {
            await stop()
            error = "Accessibility permission was removed. Allow Docky and enable it again."
            return
        }
        let operation = generation
        evaluating = true
        defer {
            evaluating = false
            if needsEvaluation { needsEvaluation = false; requestEvaluation() }
        }
        let edge = dockPreferences?.string(forKey: "orientation") ?? "bottom"
        let thickness = CGFloat(dockPreferences?.double(forKey: "tilesize") ?? 48) + 16
        let screens = accessibilityScreens()
        let canReuseGeometry = cachedDockGeometry.map {
            $0.screens == screens && $0.edge == edge && $0.thickness == thickness &&
            Date().timeIntervalSince($0.capturedAt) < 5
        } ?? false
        if !canReuseGeometry {
            cachedDockGeometry = CachedDockGeometry(measured: measuredDockFrame(), screens: screens,
                                                    edge: edge, thickness: thickness, capturedAt: Date())
        }
        let dockFrame = cachedDockGeometry?.measured
        // Dock may migrate between displays. Prefer its current AX frame when available.
        let screen = DockGeometry.screen(for: dockFrame, screens: screens, edge: edge) ?? .zero
        guard !screen.isEmpty else { return }
        let resting = DockGeometry.restingFrame(measured: dockFrame, screen: screen, edge: edge, thickness: thickness)
        let key = "\(screen)-\(edge)"
        let visible = visibleWorkArea(for: screen) ?? screen
        if lastHidden == false { reservedWorkAreas[key] = visible }
        // If enabled with auto-hide already on, estimate only the Dock edge.
        let workArea = reservedWorkAreas[key] ?? estimatedWorkArea(visible: visible, dock: resting, edge: edge)
        let gap = CGFloat(min(200, max(0, windowGap)))
        guard let windows = onScreenWindowFrames() else { return }
        let hide = DockGeometry.shouldHide(windows: windows, dock: resting, screen: screen,
                                           workArea: workArea, edge: edge, gap: gap)
        if pendingDecision != hide {
            pendingDecision = hide
            decisionSince = Date()
        }
        // Hide on the first matching sample. Only showing needs a stability delay:
        // briefly crossing the boundary must not flash the Dock back on screen.
        let clearanceTime = Date().timeIntervalSince(decisionSince)
        guard hide || clearanceTime >= 0.35 else {
            requestEvaluation(after: 0.36 - clearanceTime)
            return
        }
        guard hide != lastHidden else {
            status = hide ? "Dock auto-hides — window reaches Dock area" : "Dock visible — all windows are clear"
            if hide { considerExpansion(workArea: workArea, screen: screen, edge: edge, gap: gap) }
            else { expansionCandidate = nil; lastExpansionAttempt = nil }
            return
        }
        do {
            try await automation.write(hide)
            guard operation == generation else { return }
            lastHidden = hide
            guard !monitoringSuspended else { return }
            if enabled { status = hide ? "Dock auto-hides — window reaches Dock area" : "Dock visible — all windows are clear" }
            if hide { considerExpansion(workArea: workArea, screen: screen, edge: edge, gap: gap) }
            else { expansionCandidate = nil; lastExpansionAttempt = nil }
        } catch {
            guard operation == generation else { return }
            enabled = false
            stopMonitoring()
            self.error = error.localizedDescription
            status = "Paused — Dock control failed"
        }
    }

    private func requestEvaluation(after delay: TimeInterval = 0.02) {
        guard enabled, !monitoringSuspended else { return }
        let deadline = Date().addingTimeInterval(delay)
        if let existing = evaluationDeadline, existing <= deadline { return }
        evaluationTask?.cancel()
        evaluationDeadline = deadline
        evaluationTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.evaluationDeadline = nil
            self.evaluationTask = nil
            await self.evaluate()
        }
    }

    private func startFallbackTimer() {
        guard enabled, !monitoringSuspended else { return }
        timer?.invalidate()
        let watcher = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.enabled, !self.monitoringSuspended else { return }
                self.windowMonitor.refreshApplications()
                self.requestEvaluation()
            }
        }
        watcher.tolerance = 0.5
        RunLoop.main.add(watcher, forMode: .common)
        timer = watcher
    }

    private func cancelScheduledEvaluations() {
        timer?.invalidate()
        timer = nil
        evaluationTask?.cancel()
        evaluationTask = nil
        evaluationDeadline = nil
        needsEvaluation = false
        expansionCandidate = nil
    }

    private func setMonitoringSuspended(_ suspended: Bool) {
        guard enabled, monitoringSuspended != suspended else { return }
        monitoringSuspended = suspended
        cachedDockGeometry = nil
        cancelScheduledEvaluations()
        if suspended { status = "Paused while displays sleep" }
        else {
            pendingDecision = nil
            lastExpansionAttempt = nil
            startFallbackTimer()
            requestEvaluation()
        }
    }

    private func stopMonitoring() {
        cancelScheduledEvaluations()
        windowMonitor.stop()
        monitoringSuspended = false
        cachedDockGeometry = nil
    }

    private func onScreenWindowFrames() -> [CGRect]? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var frames: [CGRect] = []
        var windowIDs: [Int32: Set<UInt32>] = [:]
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 1, rect.height > 1 else { continue }
            frames.append(rect)
            if let id = info[kCGWindowNumber as String] as? UInt32 { windowIDs[pid, default: []].insert(id) }
        }
        windowMonitor.reconcileWindowIDs(windowIDs)
        return frames
    }

    private func considerExpansion(workArea: CGRect, screen: CGRect, edge: String, gap: CGFloat) {
        // Snapping can still be animating when the Dock hides. Track the latest
        // geometry until stable, including snaps performed while already hidden.
        guard expandWindowsIntoDockSpace,
              let element = focusedWindowElement(),
              attribute(element, "AXFullScreen") as? Bool != true,
              let currentFrame = frame(element),
              let target = DockGeometry.expansionTarget(window: currentFrame, workArea: workArea,
                                                        screen: screen, edge: edge, gap: gap) else {
            expansionCandidate = nil
            lastExpansionAttempt = nil
            return
        }
        if let attempt = lastExpansionAttempt, CFEqual(attempt.window, element),
           DockGeometry.matches(attempt.frame, currentFrame, tolerance: 1) { return }
        guard let candidate = expansionCandidate, CFEqual(candidate.window, element),
              DockGeometry.matches(candidate.frame, currentFrame, tolerance: 1),
              DockGeometry.matches(candidate.target, target, tolerance: 1) else {
            expansionCandidate = (element, currentFrame, target, Date())
            requestEvaluation(after: 0.12)
            return
        }
        let stableTime = Date().timeIntervalSince(candidate.since)
        guard stableTime >= 0.1 else {
            requestEvaluation(after: 0.12 - stableTime)
            return
        }
        lastExpansionAttempt = (element, currentFrame)
        expansionCandidate = nil
        expand(element, to: target)
    }

    private func focusedWindowElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              app.bundleIdentifier != "com.apple.dock" else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.15)
        guard let window = attribute(element, kAXFocusedWindowAttribute) else { return nil }
        return (window as! AXUIElement)
    }

    private func visibleWorkArea(for screen: CGRect) -> CGRect? {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.first {
            CGRect(x: $0.frame.minX, y: top - $0.frame.maxY,
                   width: $0.frame.width, height: $0.frame.height) == screen
        }.map {
            let rect = $0.visibleFrame
            return CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
    }

    private func estimatedWorkArea(visible: CGRect, dock: CGRect, edge: String) -> CGRect {
        switch edge {
        case "left":
            return CGRect(x: dock.maxX, y: visible.minY,
                          width: max(0, visible.maxX - dock.maxX), height: visible.height)
        case "right":
            return CGRect(x: visible.minX, y: visible.minY,
                          width: max(0, dock.minX - visible.minX), height: visible.height)
        default:
            return CGRect(x: visible.minX, y: visible.minY,
                          width: visible.width, height: max(0, dock.minY - visible.minY))
        }
    }

    private func expand(_ window: AXUIElement, to target: CGRect) {
        var positionSettable = DarwinBoolean(false)
        var sizeSettable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(window, kAXPositionAttribute as CFString, &positionSettable) == .success,
              AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &sizeSettable) == .success,
              positionSettable.boolValue, sizeSettable.boolValue else { return }
        var point = target.origin
        var size = target.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        let moved = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        let resized = moved == .success
            ? AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions) : moved
        if resized != .success { status = "Dock hidden — this app could not expand its window" }
    }

    private func measuredDockFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let children = attribute(app, kAXChildrenAttribute) as? [AXUIElement] else { return nil }
        for child in children where attribute(child, kAXRoleAttribute) as? String == kAXListRole {
            if let rect = frame(child), rect.width > 1, rect.height > 1 { return rect }
        }
        return nil
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = attribute(element, kAXPositionAttribute), CFGetTypeID(p) == AXValueGetTypeID(),
              let s = attribute(element, kAXSizeAttribute), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point),
              AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private func accessibilityScreens() -> [CGRect] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSScreen.screens.map { CGRect(x: $0.frame.minX, y: top - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
    }

    func openAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    func openAutomation() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }
}
