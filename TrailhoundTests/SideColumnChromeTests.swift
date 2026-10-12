import SwiftUI
import UIKit
import XCTest
@testable import Trailhound

final class SideColumnChromeTests: XCTestCase {
    private let buttonSide = GlassTokens.toolbarControlCircleSide
    private let gap = GlassTokens.sideColumnChromeGap

    func testLeadingColumnCentersOnThePlatter() {
        let bar = CGRect(x: 12, y: 160, width: 64, height: 220)
        let placement = SideColumnChromeResolver.resolve(metrics(tabBar: bar, safe: .zero, buttons: 2))
        guard case .sideColumn(let frame, let below) = placement else {
            return XCTFail("Expected the stack above a side platter")
        }
        XCTAssertFalse(below)
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(bar.minY - frame.maxY, gap, accuracy: 0.5)
        XCTAssertEqual(frame.height, buttonSide * 2 + gap, accuracy: 0.5)
        XCTAssertEqual(frame.width, buttonSide, accuracy: 0.5)
    }

    func testTrailingColumnUsesTheSameGapBelowTheCamera() {
        let window = CGSize(width: 900, height: 420)
        let bar = CGRect(x: window.width - 76, y: 88, width: 64, height: 200)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 59)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2, direction: .rightToLeft)
        )
        guard case .sideColumn(let frame, let below) = placement else {
            return XCTFail("Expected the stack under the platter")
        }
        XCTAssertTrue(below)
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(frame.minY - bar.maxY, gap, accuracy: 0.5)
        let camera = SideColumnChromeResolver.cameraRegion(windowSize: window, safeInsets: safe, column: bar)
        XCTAssertFalse(camera.isEmpty)
        XCTAssertFalse(frame.intersects(camera))
    }

    func testCameraOnTheOtherEdgeLeavesTheStackAboveThePlatter() {
        let window = CGSize(width: 900, height: 420)
        let bar = CGRect(x: 12, y: 140, width: 64, height: 180)
        let safe = UIEdgeInsets(top: 0, left: 0, bottom: 21, right: 59)
        let placement = SideColumnChromeResolver.resolve(metrics(window: window, tabBar: bar, safe: safe, buttons: 1))
        guard case .sideColumn(let frame, let below) = placement else {
            return XCTFail("Expected the stack above the platter")
        }
        XCTAssertFalse(below)
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertEqual(bar.minY - frame.maxY, gap, accuracy: 0.5)
        let camera = SideColumnChromeResolver.cameraRegion(windowSize: window, safeInsets: safe, column: bar)
        XCTAssertTrue(camera.isEmpty)
        XCTAssertFalse(frame.intersects(camera))
    }

    func testBottomTabBarStaysInTheToolbar() {
        let bar = CGRect(x: 80, y: 760, width: 230, height: 56)
        let placement = SideColumnChromeResolver.resolve(metrics(tabBar: bar, safe: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0), buttons: 2))
        XCTAssertEqual(placement, .toolbar)
    }

    func testMissingPlatterStaysPending() {
        let placement = SideColumnChromeResolver.resolve(metrics(tabBar: nil, safe: .zero, buttons: 1))
        XCTAssertEqual(placement, .pending)
    }

    func testFullHeightColumnKeepsTheStackOnScreenUnderTheCamera() {
        let window = CGSize(width: 900, height: 420)
        let bar = CGRect(x: 0, y: 0, width: 64, height: window.height)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 0)
        let placement = SideColumnChromeResolver.resolve(
            metrics(window: window, tabBar: bar, safe: safe, buttons: 2)
        )
        guard case .sideColumn(let frame, _) = placement else {
            return XCTFail("Expected the stack to stay in the side column")
        }
        XCTAssertEqual(frame.midX, bar.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(frame.minY, 0)
        XCTAssertLessThanOrEqual(frame.maxY, window.height)
        let camera = SideColumnChromeResolver.cameraRegion(windowSize: window, safeInsets: safe, column: bar)
        XCTAssertFalse(frame.intersects(camera))
        XCTAssertEqual(frame.minY - camera.maxY, gap, accuracy: 0.5)
    }

    func testRotationStaysPendingUntilTheNextPlatter() {
        var metrics = metrics(tabBar: CGRect(x: 12, y: 96, width: 64, height: 220), safe: .zero, buttons: 2)
        metrics.isTransitioning = true
        XCTAssertEqual(SideColumnChromeResolver.resolve(metrics), .pending)
    }

    @MainActor
    func testStatePublishesPendingOnlyWhileTransitioning() {
        let state = SideColumnChromeState()
        state.update(
            windowSize: CGSize(width: 900, height: 420),
            safeInsets: .zero,
            tabBarFrame: CGRect(x: 12, y: 96, width: 64, height: 220),
            layoutDirection: .leftToRight
        )
        XCTAssertTrue(state.showsToolbarChrome == false)
        state.beginTransition()
        XCTAssertEqual(state.placement(buttonCount: 2), .pending)
        XCTAssertTrue(state.showsToolbarChrome)
        state.endTransition()
        guard case .sideColumn = state.placement(buttonCount: 2) else {
            return XCTFail("Expected the side column after the transition")
        }
    }

    private func metrics(
        window: CGSize = CGSize(width: 900, height: 700),
        tabBar: CGRect?,
        safe: UIEdgeInsets,
        buttons: Int,
        direction: LayoutDirection = .leftToRight
    ) -> SideColumnChromeMetrics {
        SideColumnChromeMetrics(
            windowSize: window,
            safeInsets: safe,
            tabBarFrame: tabBar,
            layoutDirection: direction,
            buttonCount: buttons,
            isTransitioning: false
        )
    }
}
