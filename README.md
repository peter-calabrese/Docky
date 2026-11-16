# Docky

A macOS 14+ menu bar prototype that enables native Dock auto-hide when any on-screen app window overlaps the Dock or reaches the edge of its reserved screen space. When all windows move clear, it disables auto-hide. Native screen-edge hover still reveals a hidden Dock.

## Run

Open `Docky.xcodeproj`, choose the Docky scheme and My Mac, then Run. Click the Dock icon in the menu bar and enable **Smart Dock**. Allow Docky in System Settings → Privacy & Security → Accessibility, then enable it again. Allow the Automation request to control System Events.

The app starts disabled. Accessibility observers react to window movement, resizing, creation, destruction, minimization, and focus changes. Workspace notifications handle application lifecycle and Space changes. Events are coalesced over 20 ms; showing still waits for 350 ms of clearance. A two-second fallback checks on-screen window bounds for apps that miss notifications, reusing that same snapshot’s window IDs to repair only apps whose on-screen windows changed. App activation and lifecycle notifications also target the affected app; unchanged apps no longer have their AX window trees rescanned every ten seconds. Optional expansion waits for 100 ms of stable window geometry and affects only the focused window.

Dock visibility uses Core Graphics window metadata, not screenshots, filtered to nontransparent, normal-layer, on-screen windows excluding desktop elements and Docky. Background windows count even when another app is selected; minimized, hidden, and other-Space windows are excluded by the on-screen list. Dock geometry is cached for up to five seconds and invalidated on Dock movement events, Dock relaunch, Space changes, display changes, and wake; Dock orientation and size changes are also checked before cache reuse. While the system or displays sleep, the fallback timer and scheduled evaluations are canceled and AX observer run-loop sources are detached. Both system and display sleep state must clear before monitoring resumes. No continuous 100 ms polling remains. Idle timer checks fall from ten per second to one every two seconds; battery impact has not been measured. Apps that omit movement notifications may take up to the fallback interval to trigger a change.

App Sandbox is disabled because Docky reads other apps’ Accessibility elements and automates a system preference. The Apple Events entitlement and usage description are included. This is a locally run utility, with no App Store distribution setup.

## Verify on your Mac

- Move a window across the Dock: it should react to the movement notification, plus Automation and macOS animation time. Apps that omit events may take up to the two-second fallback interval.
- Maximize with Raycast or another window manager: reaching the Dock boundary should hide the Dock without a special shortcut.
- Leave that window at the old boundary: the Dock should remain hidden without flickering.
- Select another clear window: the Dock should stay hidden while the background window remains at the boundary. Move or minimize every obstructing window: the Dock should return.
- Enable **Expand windows into freed Dock space**, then maximize or tile a window with the Dock visible: Docky should extend only its Dock-facing edge into the released space. A half-screen window should keep its other edges and configured outer gap.
- Try snapping to full size after a half-screen snap while the Dock is already hidden, and try animated snapping: Docky should expand the final stable frame. Moving a window away from the boundary or switching focus should cancel its pending expansion.
- While hidden, hover the Dock edge: macOS should reveal it normally.
- Switch between apps, hide/unhide apps, open/close/minimize windows, and switch Spaces. Only on-screen windows should keep the Dock hidden.
- Try bottom, left, and right Dock positions and multiple displays.
- Put the displays to sleep, then wake them: monitoring should pause during sleep and refresh immediately on wake. Try system sleep as well, and disable/enable after waking.
- With windows stationary, verify low CPU/wakeups in Activity Monitor. Test Dock placement/size changes, Dock relaunch, and moving the Dock to a different display; the geometry cache should refresh.
- Disable Docky or quit through its menu: the original auto-hide setting should return.

Set **Window gap (px)** to your window manager’s outer gap (0–200, default 0). It extends boundary detection by that amount and preserves the gap when expanding. Values use macOS screen coordinates, matching window managers’ logical pixels.

Optional expansion defaults to off and also handles snapping while the Dock is already hidden. It handles maximized and tiled windows aligned with the reserved Dock edge, preserves their other edges and the configured gap, skips native full-screen and multi-display windows, and rechecks window identity and position before resizing. Apps may enforce size restrictions; Docky does not repeatedly force their size or restore expanded window sizes when disabled. If auto-hide is already enabled at startup, Docky estimates the reserved boundary until it observes the Dock visible.

Full-screen apps and Spaces retain macOS’s own Dock rules. Multi-display Dock migration and window managers need live testing. If the Dock does not expose its Accessibility rectangle, Docky estimates a full-length edge region on the primary display using the configured tile size; this can hide the Dock for windows beside its actual footprint. Apps without an accessible focused window still participate in visibility decisions through their on-screen bounds, but cannot be expanded.

The original auto-hide setting is saved before the first change. After a crash or force quit, reopen Docky and choose **Restore Original Dock Setting** or quit through its menu. If restoration fails, Docky stays open and shows the error with a retry button. Stopping in Xcode bypasses normal quit restoration.

## Geometry checks

```sh
swiftc -module-cache-path /tmp/Docky-swift-cache Docky/DockGeometry.swift Tests/GeometryChecks.swift -o /tmp/Docky-geometry-checks
/tmp/Docky-geometry-checks
swiftc -module-cache-path /tmp/Docky-swift-cache Docky/MonitoringPolicy.swift Tests/MonitoringChecks.swift -o /tmp/Docky-monitoring-checks
/tmp/Docky-monitoring-checks
```


## Development guidance

SwiftUI changes were reviewed using [Paul Hudson’s SwiftUI Pro skill](https://github.com/twostraws/SwiftUI-Agent-Skill/blob/main/swiftui-pro/SKILL.md), including its data flow, accessibility, and Swift concurrency references. The existing macOS 14 deployment target is preserved.

## App icon

The icon uses a frosted-glass app window above a pale-blue Dock with three white tiles, separated by a small blue gap and framed with outer padding, on a blue gradient inspired by the supplied Dock / Latte Dock reference. It is installed in `Docky/Assets.xcassets/AppIcon.appiconset` and selected as the app icon. Artwork and the built-in image generation prompt are saved in `Design/DockyIcon-glass-spaced-source.png` and `Design/IconPrompt-glass-spaced.md`. Earlier variants are preserved in `Design`.
# Docky
# Docky
# Docky
# Docky
