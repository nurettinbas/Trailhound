import SwiftUI
import UIKit

enum SideColumnChromeID {
    static let notifications = "trips.notifications"
    static let merge = "trips.merge"
    static let newJournal = "trips.journal.new"
}

/// Where the bell and the Trips trailing action draw.
/// Toolbar and the side column read this together, so a rotation cannot show both.
enum SideColumnChromePlacement: Equatable {
    case toolbar
    /// Rotation or a missing platter. The toolbar keeps the buttons until the next platter.
    case pending
    /// `stackFrame` is in window coordinates. `below` is true when the camera
    /// would have covered the stack above the platter.
    case sideColumn(stackFrame: CGRect, below: Bool)

    var showsToolbarChrome: Bool {
        if case .toolbar = self { return true }
        return false
    }
}

struct SideColumnChromeMetrics: Equatable {
    var windowSize: CGSize
    var safeInsets: UIEdgeInsets
    var tabBarFrame: CGRect?
    var layoutDirection: LayoutDirection
    var buttonCount: Int
    var isTransitioning: Bool
}

/// Pure placement for the side-column bell and merge (or new-travel) stack.
enum SideColumnChromeResolver {
    static func resolve(_ metrics: SideColumnChromeMetrics) -> SideColumnChromePlacement {
        if metrics.isTransitioning { return .pending }
        // The platter frame is already in window coordinates. RTL does not mirror it.
        _ = metrics.layoutDirection
        guard let bar = metrics.tabBarFrame, bar.width > 1, bar.height > 1 else { return .pending }
        guard isSideTabBar(bar) else { return .toolbar }
        guard metrics.buttonCount > 0 else {
            return .sideColumn(stackFrame: .zero, below: false)
        }

        let side = GlassTokens.toolbarControlCircleSide
        let gap = GlassTokens.sideColumnChromeGap
        let stackHeight = side * CGFloat(metrics.buttonCount) + gap * CGFloat(metrics.buttonCount - 1)
        let x = min(max(bar.midX - side / 2, 0), max(metrics.windowSize.width - side, 0))
        let above = CGRect(x: x, y: bar.minY - gap - stackHeight, width: side, height: stackHeight)
        let camera = cameraRegion(windowSize: metrics.windowSize, safeInsets: metrics.safeInsets, column: bar)
        if fits(above, in: metrics.windowSize, avoiding: camera) {
            return .sideColumn(stackFrame: above, below: false)
        }
        let below = CGRect(x: x, y: bar.maxY + gap, width: side, height: stackHeight)
        if fits(below, in: metrics.windowSize, avoiding: camera) {
            return .sideColumn(stackFrame: below, below: true)
        }
        // A full-height side bar has no room above or below it. Park the stack in the
        // column, under the camera, and keep every point inside the window.
        let parkedY = min(
            max((camera.height > 1 ? camera.maxY : 0) + gap, 0),
            max(metrics.windowSize.height - stackHeight, 0)
        )
        let parked = CGRect(x: x, y: parkedY, width: side, height: stackHeight)
        return .sideColumn(stackFrame: parked, below: false)
    }

    /// Square at the top of the column when that column is the camera edge.
    /// Height is `max(safeTop, column inset)`. The opposite edge has no camera rect.
    static func cameraRegion(windowSize: CGSize, safeInsets: UIEdgeInsets, column: CGRect) -> CGRect {
        guard windowSize.width > 1, windowSize.height > 1, column.width > 1 else { return .zero }
        let onLeft = column.midX < windowSize.width * 0.5
        let columnInset = onLeft ? safeInsets.left : safeInsets.right
        let otherInset = onLeft ? safeInsets.right : safeInsets.left
        let top = safeInsets.top
        let cameraOnThisSide = columnInset > 20 && columnInset + 0.5 >= otherInset
        let topCameraOnly = top > 20 && columnInset <= 20 && otherInset <= 20
        guard cameraOnThisSide || topCameraOnly else { return .zero }
        let depth = max(top, columnInset)
        guard depth > 20 else { return .zero }
        let x = onLeft ? 0 : windowSize.width - depth
        return CGRect(x: x, y: 0, width: depth, height: depth)
    }

    static func isSideTabBar(_ frame: CGRect) -> Bool {
        frame.width >= 44 && frame.height > 80 && frame.height > frame.width * 1.4
    }

    private static func fits(_ frame: CGRect, in window: CGSize, avoiding camera: CGRect) -> Bool {
        frame.minY >= 0
            && frame.maxY <= window.height
            && frame.minX >= 0
            && frame.maxX <= window.width
            && !frame.intersects(camera)
    }
}

/// One measurement of the tab platter. Toolbar items and the side-column overlay both read it.
@MainActor
@Observable
final class SideColumnChromeState {
    static let shared = SideColumnChromeState()

    private(set) var isTransitioning = false
    private(set) var windowSize: CGSize = .zero
    private(set) var safeInsets: UIEdgeInsets = .zero
    private(set) var tabBarFrame: CGRect?
    private(set) var layoutDirection: LayoutDirection = .leftToRight

    func beginTransition() {
        isTransitioning = true
    }

    func endTransition() {
        isTransitioning = false
    }

    func update(
        windowSize: CGSize,
        safeInsets: UIEdgeInsets,
        tabBarFrame: CGRect?,
        layoutDirection: LayoutDirection
    ) {
        if self.windowSize != windowSize { self.windowSize = windowSize }
        if self.safeInsets != safeInsets { self.safeInsets = safeInsets }
        if !sameFrame(self.tabBarFrame, tabBarFrame) { self.tabBarFrame = tabBarFrame }
        if self.layoutDirection != layoutDirection { self.layoutDirection = layoutDirection }
    }

    private func sameFrame(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return abs(lhs.minX - rhs.minX) < 0.5
                && abs(lhs.minY - rhs.minY) < 0.5
                && abs(lhs.width - rhs.width) < 0.5
                && abs(lhs.height - rhs.height) < 0.5
        default:
            return false
        }
    }

    func placement(buttonCount: Int) -> SideColumnChromePlacement {
        SideColumnChromeResolver.resolve(
            SideColumnChromeMetrics(
                windowSize: windowSize,
                safeInsets: safeInsets,
                tabBarFrame: tabBarFrame,
                layoutDirection: layoutDirection,
                buttonCount: buttonCount,
                isTransitioning: isTransitioning
            )
        )
    }

    /// Pending keeps the toolbar copy. Hiding both is how the buttons vanished.
    var showsToolbarChrome: Bool {
        switch placement(buttonCount: 1) {
        case .toolbar, .pending:
            return true
        case .sideColumn:
            return false
        }
    }
}
