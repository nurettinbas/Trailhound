import XCTest
@testable import Trailhound

final class LiveFollowPresentationTests: XCTestCase {
    private let container = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let source = CGRect(x: 16, y: 120, width: 358, height: 220)

    func testLerpRectEndpoints() {
        let mid = LiveFollowPresentation.lerpRect(from: source, to: container, progress: 0.5)
        XCTAssertEqual(mid.minX, 8, accuracy: 0.01)
        XCTAssertEqual(mid.minY, 60, accuracy: 0.01)
        XCTAssertEqual(mid.width, 374, accuracy: 0.01)
        XCTAssertEqual(mid.height, 532, accuracy: 0.01)

        XCTAssertEqual(
            LiveFollowPresentation.lerpRect(from: source, to: container, progress: 0),
            source
        )
        XCTAssertEqual(
            LiveFollowPresentation.lerpRect(from: source, to: container, progress: 1),
            container
        )
    }

    func testProgressClamped() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container)
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: -1),
            source
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: 2),
            settled
        )
    }

    func testSettledHUDRectCenteredBottom() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 148)
        XCTAssertEqual(settled.width, 390 * 8 / 12, accuracy: 0.01)
        XCTAssertEqual(settled.height, 148, accuracy: 0.01)
        XCTAssertEqual(settled.midX, container.midX, accuracy: 0.01)
        XCTAssertEqual(
            settled.maxY,
            container.maxY - LiveFollowPresentation.settledBottomPadding,
            accuracy: 0.01
        )
    }

    func testHUDRectEndpoints() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container)
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: 0),
            source
        )
        XCTAssertEqual(
            LiveFollowPresentation.hudRect(source: source, settled: settled, progress: 1),
            settled
        )
    }

    func testSourceRectUsesAnchorWhenValid() {
        let anchor = RecordingCardAnchor(minX: 10, minY: 20, width: 300, height: 200)
        XCTAssertEqual(
            LiveFollowPresentation.sourceRect(from: anchor, fallbackContainer: container),
            CGRect(x: 10, y: 20, width: 300, height: 200)
        )
    }

    func testSourceRectFallsBackWhenAnchorEmpty() {
        let fallback = LiveFollowPresentation.sourceRect(
            from: RecordingCardAnchor(),
            fallbackContainer: container
        )
        XCTAssertGreaterThan(fallback.width, 1)
        XCTAssertGreaterThan(fallback.height, 1)
        XCTAssertTrue(container.contains(fallback.origin) || fallback.intersects(container))
    }

    func testReduceMotionStartsSettled() {
        XCTAssertEqual(LiveFollowPresentation.initialProgress(reduceMotion: true), 1)
        XCTAssertEqual(LiveFollowPresentation.initialProgress(reduceMotion: false), 0)
    }

    func testHeroSourcePrefersCarFrame() {
        let anchor = RecordingCardAnchor(
            minX: 10,
            minY: 20,
            width: 300,
            height: 200,
            carMinX: 40,
            carMinY: 60,
            carWidth: 100,
            carHeight: 50
        )
        XCTAssertEqual(
            LiveFollowPresentation.heroSourceRect(from: anchor, cardFallback: source),
            CGRect(x: 40, y: 60, width: 100, height: 50)
        )
    }

    func testHeroDestSitsInLowerHalfForFollowCamera() {
        let dest3D = LiveFollowPresentation.heroDestCenter(
            in: CGSize(width: 390, height: 844),
            uses3D: true
        )
        XCTAssertEqual(dest3D.x, 195, accuracy: 0.01)
        XCTAssertEqual(dest3D.y, 844 * 0.64, accuracy: 0.01)
        XCTAssertGreaterThan(dest3D.y, 844 * 0.5)

        let dest2D = LiveFollowPresentation.heroDestCenter(
            in: CGSize(width: 390, height: 844),
            uses3D: false
        )
        XCTAssertEqual(dest2D.y, 844 * 0.56, accuracy: 0.01)
    }

    func testPuckCircleCenterAppliesAnnotationOffsetAndBadgeLayout() {
        let projected = CGPoint(x: 200, y: 500)
        let circle = LiveFollowPresentation.puckCircleCenter(fromProjectedAnnotationPoint: projected)
        let offset = LiveFollowPresentation.puckAnnotationCenterOffset
        let viewCenterY = projected.y + offset.y
        let circleVsView =
            LiveFollowPresentation.puckCircleSize / 2
            - LiveFollowPresentation.puckAnnotationFrameHeight / 2
        XCTAssertEqual(circle.x, projected.x + offset.x, accuracy: 0.01)
        XCTAssertEqual(circle.y, viewCenterY + circleVsView, accuracy: 0.01)
        // Circle sits above the projected annotation point (chevron hangs below).
        XCTAssertLessThan(circle.y, projected.y)
    }

    func testPuckAnnotationCenterOffsetMatchesLegacyLayout() {
        XCTAssertEqual(
            LiveFollowPresentation.puckAnnotationCenterOffset.y,
            -LiveFollowPresentation.puckCircleSize / 2 + 8,
            accuracy: 0.01
        )
        XCTAssertEqual(LiveFollowPresentation.puckAnnotationCenterOffset.x, 0, accuracy: 0.01)
    }

    func testHeroFlightArcEndpointsAndBulge() {
        let from = CGPoint(x: 195, y: 160)
        let to = CGPoint(x: 195, y: 540)
        XCTAssertEqual(
            LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: 0),
            from
        )
        XCTAssertEqual(
            LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: 1),
            to
        )
        let midArc = LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: 0.5)
        let midStraight = LiveFollowPresentation.lerpPoint(from: from, to: to, progress: 0.5)
        // Side-sweep must leave the vertical chord by a readable amount.
        XCTAssertGreaterThan(abs(midArc.x - midStraight.x), 40)
        XCTAssertLessThan(midArc.x, midStraight.x) // bows leading / left
        XCTAssertLessThan(midArc.y, midStraight.y) // slight upward peak before descent
    }

    func testCloseHudExpandsAtBottomThenRises() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 148)
        let start = LiveFollowPresentation.closeHudRect(
            source: source,
            settled: settled,
            expandProgress: 0,
            riseProgress: 0
        )
        XCTAssertEqual(start, settled)

        let expanded = LiveFollowPresentation.closeHudRect(
            source: source,
            settled: settled,
            expandProgress: 1,
            riseProgress: 0
        )
        XCTAssertEqual(expanded.width, source.width, accuracy: 0.01)
        XCTAssertEqual(expanded.height, source.height, accuracy: 0.01)
        XCTAssertEqual(expanded.maxY, settled.maxY, accuracy: 0.01)

        let risen = LiveFollowPresentation.closeHudRect(
            source: source,
            settled: settled,
            expandProgress: 1,
            riseProgress: 1
        )
        XCTAssertEqual(risen, source)
    }

    func testHeroSourceFallsBackWhenCarFrameMissing() {
        let fallback = LiveFollowPresentation.heroSourceRect(
            from: RecordingCardAnchor(minX: 10, minY: 20, width: 300, height: 200),
            cardFallback: source
        )
        XCTAssertGreaterThan(fallback.width, 1)
        XCTAssertGreaterThan(fallback.height, 1)
        XCTAssertEqual(fallback.midX, source.midX, accuracy: 0.01)
        XCTAssertGreaterThan(fallback.minY, source.minY)
    }

    func testExpandedAtBottomPinsMaxY() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 148)
        let expanded = LiveFollowPresentation.expandedAtBottomRect(source: source, settled: settled)
        XCTAssertEqual(expanded.width, source.width, accuracy: 0.01)
        XCTAssertEqual(expanded.height, source.height, accuracy: 0.01)
        XCTAssertEqual(expanded.maxY, settled.maxY, accuracy: 0.01)
        XCTAssertEqual(expanded.midX, settled.midX, accuracy: 0.01)
    }

    func testQuadraticBezierEndpoints() {
        let from = CGPoint(x: 0, y: 0)
        let to = CGPoint(x: 100, y: 100)
        let control = CGPoint(x: 0, y: 100)
        XCTAssertEqual(
            LiveFollowPresentation.quadraticBezier(from: from, control: control, to: to, progress: 0),
            from
        )
        XCTAssertEqual(
            LiveFollowPresentation.quadraticBezier(from: from, control: control, to: to, progress: 1),
            to
        )
        let mid = LiveFollowPresentation.quadraticBezier(
            from: from,
            control: control,
            to: to,
            progress: 0.5
        )
        XCTAssertEqual(mid.x, 25, accuracy: 0.01)
        XCTAssertEqual(mid.y, 75, accuracy: 0.01)
    }

    func testCloseHudClampsOutOfRangeProgress() {
        let settled = LiveFollowPresentation.settledHUDRect(in: container, hudHeight: 148)
        XCTAssertEqual(
            LiveFollowPresentation.closeHudRect(
                source: source,
                settled: settled,
                expandProgress: -1,
                riseProgress: -2
            ),
            settled
        )
        XCTAssertEqual(
            LiveFollowPresentation.closeHudRect(
                source: source,
                settled: settled,
                expandProgress: 4,
                riseProgress: 9
            ),
            source
        )
    }

    func testRecordingCardAnchorCarFrameGate() {
        var anchor = RecordingCardAnchor(minX: 10, minY: 20, width: 300, height: 180)
        XCTAssertFalse(anchor.hasCarFrame)
        XCTAssertEqual(anchor.rect, CGRect(x: 10, y: 20, width: 300, height: 180))

        anchor.carMinX = 40
        anchor.carMinY = 60
        anchor.carWidth = 1
        anchor.carHeight = 50
        XCTAssertFalse(anchor.hasCarFrame)

        anchor.carWidth = 80
        XCTAssertTrue(anchor.hasCarFrame)
        XCTAssertEqual(anchor.carRect, CGRect(x: 40, y: 60, width: 80, height: 50))
    }
}
