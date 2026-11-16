import Foundation
import CoreGraphics

// Both rectangles use Accessibility coordinates: origin at the primary display's top left.
enum DockGeometry {
    static func screen(for dock: CGRect?, screens: [CGRect], edge: String? = nil) -> CGRect? {
        guard let dock else { return screens.first }
        // A hidden Dock can sit just beyond the display edge. Nearest display wins
        // when no display intersects it; intersection breaks ties at shared edges.
        return screens.min { a, b in
            func distance(_ screen: CGRect) -> CGFloat {
                // Hidden Dock frames straddle an edge. Their center can land on
                // an adjacent display, so compare against the configured edge.
                if let edge {
                    let along: CGFloat
                    let across: CGFloat
                    switch edge {
                    case "left":
                        along = max(screen.minY - dock.midY, 0, dock.midY - screen.maxY)
                        across = min(abs(dock.minX - screen.minX), abs(dock.maxX - screen.minX))
                    case "right":
                        along = max(screen.minY - dock.midY, 0, dock.midY - screen.maxY)
                        across = min(abs(dock.minX - screen.maxX), abs(dock.maxX - screen.maxX))
                    default:
                        along = max(screen.minX - dock.midX, 0, dock.midX - screen.maxX)
                        across = min(abs(dock.minY - screen.maxY), abs(dock.maxY - screen.maxY))
                    }
                    return along * along + across * across
                }
                let dx = max(screen.minX - dock.midX, 0, dock.midX - screen.maxX)
                let dy = max(screen.minY - dock.midY, 0, dock.midY - screen.maxY)
                return dx * dx + dy * dy
            }
            let da = distance(a), db = distance(b)
            if da != db { return da < db }
            func area(_ screen: CGRect) -> CGFloat {
                let intersection = screen.intersection(dock)
                return intersection.isNull ? 0 : intersection.width * intersection.height
            }
            return area(a) > area(b)
        }
    }

    static func overlaps(window: CGRect, dock: CGRect) -> Bool {
        let intersection = window.intersection(dock)
        return !intersection.isNull && intersection.width > 1 && intersection.height > 1
    }

    static func shouldHide(windows: [CGRect], dock: CGRect, screen: CGRect,
                           workArea: CGRect, edge: String, gap: CGFloat) -> Bool {
        windows.contains {
            overlaps(window: $0, dock: dock) ||
            reachesBoundary(window: $0, screen: screen, workArea: workArea, edge: edge, tolerance: gap + 4)
        }
    }

    // Use the full reserved edge, including the space beside the Dock icons.
    static func reachesBoundary(window: CGRect, screen: CGRect, workArea: CGRect,
                                edge: String, tolerance: CGFloat = 4) -> Bool {
        guard window.intersects(screen) else { return false }
        switch edge {
        case "left":
            return window.minX <= workArea.minX + tolerance && window.maxX > screen.minX
        case "right":
            return window.maxX >= workArea.maxX - tolerance && window.minX < screen.maxX
        default:
            return window.maxY >= workArea.maxY - tolerance && window.minY < screen.maxY
        }
    }

    static func matches(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance &&
        abs(a.maxX - b.maxX) <= tolerance && abs(a.maxY - b.maxY) <= tolerance
    }

    // Expand only windows aligned with the reserved edge; leave overlapping,
    // already-expanded, or multi-display windows alone.
    static func expansionTarget(window: CGRect, workArea: CGRect, screen: CGRect,
                                edge: String, gap: CGFloat) -> CGRect? {
        guard !window.isEmpty, screen.insetBy(dx: -4, dy: -4).contains(window) else { return nil }
        let distance: CGFloat
        switch edge {
        case "left": distance = abs(window.minX - workArea.minX)
        case "right": distance = abs(window.maxX - workArea.maxX)
        default: distance = abs(window.maxY - workArea.maxY)
        }
        guard distance <= gap + 4 else { return nil }
        let target = expandedFrame(workArea: window, screen: screen.insetBy(dx: gap, dy: gap), edge: edge)
        let growth = edge == "bottom" ? target.height - window.height : target.width - window.width
        guard growth > 1 else { return nil }
        return target
    }

    static func expandedFrame(workArea: CGRect, screen: CGRect, edge: String) -> CGRect {
        switch edge {
        case "left":
            return CGRect(x: screen.minX, y: workArea.minY,
                          width: workArea.maxX - screen.minX, height: workArea.height)
        case "right":
            return CGRect(x: workArea.minX, y: workArea.minY,
                          width: screen.maxX - workArea.minX, height: workArea.height)
        default:
            return CGRect(x: workArea.minX, y: workArea.minY,
                          width: workArea.width, height: screen.maxY - workArea.minY)
        }
    }

    static func restingFrame(measured: CGRect?, screen: CGRect, edge: String, thickness: CGFloat) -> CGRect {
        let depth = max(16, min(thickness, min(screen.width, screen.height) / 3))
        switch edge {
        case "left":
            return CGRect(x: screen.minX, y: measured?.minY ?? screen.minY,
                          width: measured?.width ?? depth, height: measured?.height ?? screen.height)
        case "right":
            let width = measured?.width ?? depth
            return CGRect(x: screen.maxX - width, y: measured?.minY ?? screen.minY,
                          width: width, height: measured?.height ?? screen.height)
        default:
            let height = measured?.height ?? depth
            return CGRect(x: measured?.minX ?? screen.minX, y: screen.maxY - height,
                          width: measured?.width ?? screen.width, height: height)
        }
    }
}
