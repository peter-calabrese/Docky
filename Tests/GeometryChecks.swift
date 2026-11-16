import Foundation
import CoreGraphics

@main
struct GeometryChecks {
    static func main() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let hiddenDock = CGRect(x: 400, y: 899, width: 640, height: 64)
        let bottom = DockGeometry.restingFrame(measured: hiddenDock, screen: screen, edge: "bottom", thickness: 64)
        precondition(bottom == CGRect(x: 400, y: 836, width: 640, height: 64))
        precondition(DockGeometry.overlaps(window: CGRect(x: 500, y: 600, width: 400, height: 260), dock: bottom))
        precondition(!DockGeometry.overlaps(window: CGRect(x: 0, y: 0, width: 300, height: 900), dock: bottom))
        precondition(!DockGeometry.overlaps(window: CGRect(x: 400, y: 0, width: 640, height: 836), dock: bottom))
        let leftDisplay = CGRect(x: -1920, y: -180, width: 1920, height: 1080)
        let left = DockGeometry.restingFrame(measured: nil, screen: leftDisplay, edge: "left", thickness: 64)
        precondition(left.minX == -1920 && left.width == 64)
        let right = DockGeometry.restingFrame(measured: nil, screen: screen, edge: "right", thickness: 64)
        precondition(right.minX == 1376)
        precondition(DockGeometry.screen(for: nil, screens: [screen, leftDisplay]) == screen)
        precondition(DockGeometry.screen(for: hiddenDock, screens: [screen, leftDisplay]) == screen)
        let hiddenLeft = CGRect(x: -1982, y: 200, width: 64, height: 500)
        precondition(DockGeometry.screen(for: hiddenLeft, screens: [screen, leftDisplay]) == leftDisplay)
        let hiddenRight = CGRect(x: 1439, y: 200, width: 64, height: 500)
        let restoredRight = DockGeometry.restingFrame(measured: hiddenRight, screen: screen, edge: "right", thickness: 64)
        precondition(restoredRight == CGRect(x: 1376, y: 200, width: 64, height: 500))
        let restoredLeft = DockGeometry.restingFrame(measured: hiddenLeft, screen: leftDisplay, edge: "left", thickness: 64)
        precondition(restoredLeft == CGRect(x: -1920, y: 200, width: 64, height: 500))
        let upperDisplay = CGRect(x: 0, y: -1080, width: 1920, height: 1080)
        let upperDock = CGRect(x: 500, y: -1, width: 640, height: 64)
        precondition(DockGeometry.screen(for: upperDock, screens: [screen, upperDisplay], edge: "bottom") == upperDisplay)
        precondition(!DockGeometry.overlaps(window: CGRect(x: 500, y: 600, width: 400, height: 236.5), dock: bottom))
        let work = CGRect(x: 0, y: 25, width: 1440, height: 811)
        precondition(DockGeometry.reachesBoundary(window: work, screen: screen, workArea: work, edge: "bottom"))
        precondition(DockGeometry.reachesBoundary(window: CGRect(x: 0, y: 400, width: 300, height: 436), screen: screen, workArea: work, edge: "bottom"))
        precondition(!DockGeometry.reachesBoundary(window: CGRect(x: 0, y: 400, width: 300, height: 420), screen: screen, workArea: work, edge: "bottom"))
        precondition(!DockGeometry.reachesBoundary(window: CGRect(x: 1500, y: 25, width: 500, height: 811), screen: screen, workArea: work, edge: "bottom"))
        precondition(!DockGeometry.matches(CGRect(x: 0, y: 25, width: 720, height: 811), work))
        precondition(DockGeometry.matches(work.offsetBy(dx: 1, dy: 1), work))
        precondition(DockGeometry.expandedFrame(workArea: work, screen: screen, edge: "bottom") == CGRect(x: 0, y: 25, width: 1440, height: 875))
        let leftWork = CGRect(x: -1856, y: -155, width: 1856, height: 1055)
        precondition(DockGeometry.reachesBoundary(window: leftWork, screen: leftDisplay, workArea: leftWork, edge: "left"))
        precondition(DockGeometry.expandedFrame(workArea: leftWork, screen: leftDisplay, edge: "left") == CGRect(x: -1920, y: -155, width: 1920, height: 1055))
        let rightWork = CGRect(x: 0, y: 25, width: 1376, height: 875)
        precondition(DockGeometry.reachesBoundary(window: rightWork, screen: screen, workArea: rightWork, edge: "right"))
        precondition(DockGeometry.expandedFrame(workArea: rightWork, screen: screen, edge: "right") == CGRect(x: 0, y: 25, width: 1440, height: 875))
        let gap: CGFloat = 12
        let gapped = work.insetBy(dx: gap, dy: gap)
        precondition(!DockGeometry.reachesBoundary(window: gapped, screen: screen, workArea: work, edge: "bottom"))
        precondition(DockGeometry.reachesBoundary(window: gapped, screen: screen, workArea: work, edge: "bottom", tolerance: gap + 4))
        precondition(!DockGeometry.reachesBoundary(window: work.insetBy(dx: 25, dy: 25), screen: screen, workArea: work, edge: "bottom", tolerance: gap + 4))
        precondition(DockGeometry.matches(gapped, work, tolerance: gap + 4))
        precondition(!DockGeometry.matches(CGRect(x: 12, y: 37, width: 696, height: 787), work, tolerance: gap + 4))
        let expanded = DockGeometry.expandedFrame(workArea: gapped, screen: screen.insetBy(dx: gap, dy: gap), edge: "bottom")
        precondition(expanded == CGRect(x: 12, y: 37, width: 1416, height: 851))
        for edge in ["left", "right"] {
            let area = edge == "left" ? leftWork : rightWork
            let display = edge == "left" ? leftDisplay : screen
            let window = area.insetBy(dx: gap, dy: gap)
            precondition(DockGeometry.reachesBoundary(window: window, screen: display, workArea: area, edge: edge, tolerance: gap + 4))
            let target = DockGeometry.expandedFrame(workArea: window, screen: display.insetBy(dx: gap, dy: gap), edge: edge)
            precondition(target.minY == window.minY && target.height == window.height)
            precondition(edge == "left" ? target.minX == display.minX + gap : target.maxX == display.maxX - gap)
        }
        // Half-screen and quarter-screen tiles keep every non-Dock edge.
        for tile in [CGRect(x: 12, y: 37, width: 696, height: 787),
                     CGRect(x: 732, y: 440, width: 696, height: 384)] {
            let target = DockGeometry.expansionTarget(window: tile, workArea: work, screen: screen, edge: "bottom", gap: gap)!
            precondition(target.minX == tile.minX && target.width == tile.width && target.minY == tile.minY)
            precondition(target.maxY == screen.maxY - gap)
            precondition(DockGeometry.expansionTarget(window: target, workArea: work, screen: screen, edge: "bottom", gap: gap) == nil)
        }
        let zeroGapTile = CGRect(x: 720, y: 25, width: 720, height: 811)
        precondition(DockGeometry.expansionTarget(window: zeroGapTile, workArea: work, screen: screen, edge: "bottom", gap: 0) == CGRect(x: 720, y: 25, width: 720, height: 875))
        precondition(DockGeometry.expansionTarget(window: CGRect(x: 12, y: 37, width: 696, height: 350), workArea: work, screen: screen, edge: "bottom", gap: gap) == nil)
        precondition(DockGeometry.expansionTarget(window: CGRect(x: -100, y: 37, width: 800, height: 787), workArea: work, screen: screen, edge: "bottom", gap: gap) == nil)
        for edge in ["left", "right"] {
            let area = edge == "left" ? leftWork : rightWork
            let display = edge == "left" ? leftDisplay : screen
            let tile = CGRect(x: area.minX + gap, y: area.minY + gap, width: area.width - 2 * gap, height: 350)
            let target = DockGeometry.expansionTarget(window: tile, workArea: area, screen: display, edge: edge, gap: gap)!
            precondition(target.minY == tile.minY && target.height == tile.height)
            precondition(edge == "left" ? target.maxX == tile.maxX : target.minX == tile.minX)
            precondition(edge == "left" ? target.minX == display.minX + gap : target.maxX == display.maxX - gap)
        }
        // A clear focused window must not override a background window at the Dock.
        let clearWindow = CGRect(x: 20, y: 40, width: 500, height: 400)
        precondition(DockGeometry.shouldHide(windows: [clearWindow, gapped], dock: bottom, screen: screen, workArea: work, edge: "bottom", gap: gap))
        precondition(DockGeometry.shouldHide(windows: [gapped, clearWindow], dock: bottom, screen: screen, workArea: work, edge: "bottom", gap: gap))
        precondition(!DockGeometry.shouldHide(windows: [clearWindow], dock: bottom, screen: screen, workArea: work, edge: "bottom", gap: gap))
        precondition(!DockGeometry.shouldHide(windows: [], dock: bottom, screen: screen, workArea: work, edge: "bottom", gap: gap))
        precondition(!DockGeometry.shouldHide(windows: [CGRect(x: -1900, y: -150, width: 1800, height: 1000)], dock: bottom, screen: screen, workArea: work, edge: "bottom", gap: gap))
        print("Passed Dock geometry checks (overlap, boundaries, expansion, multiple displays)")
    }
}
