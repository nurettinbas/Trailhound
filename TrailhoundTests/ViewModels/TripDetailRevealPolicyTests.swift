import XCTest
@testable import Trailhound

final class TripDetailRevealPolicyTests: XCTestCase {
    func testLongRouteSkipsAnimation() {
        let plan = TripDetailRevealPolicy.animationPlan(
            pointCount: TripDetailRevealPolicy.animatedRouteMaxPoints + 1,
            reduceMotion: false
        )
        XCTAssertFalse(plan.shouldAnimate)
        XCTAssertEqual(plan.tickCount, 0)
    }

    func testShortRouteUsesSixteenTicks() {
        let plan = TripDetailRevealPolicy.animationPlan(
            pointCount: TripDetailRevealPolicy.shortRouteMaxPoints,
            reduceMotion: false
        )
        XCTAssertTrue(plan.shouldAnimate)
        XCTAssertEqual(plan.tickCount, 16)
        XCTAssertFalse(plan.useCheapMapDuringReveal)
    }

    func testMediumRouteUsesCheapMap() {
        let plan = TripDetailRevealPolicy.animationPlan(
            pointCount: TripDetailRevealPolicy.shortRouteMaxPoints + 50,
            reduceMotion: false
        )
        XCTAssertTrue(plan.shouldAnimate)
        XCTAssertEqual(plan.tickCount, 12)
        XCTAssertTrue(plan.useCheapMapDuringReveal)
    }

    func testReduceMotionSkipsAnimation() {
        let plan = TripDetailRevealPolicy.animationPlan(pointCount: 10, reduceMotion: true)
        XCTAssertFalse(plan.shouldAnimate)
    }

    func testQuantizedProgressSteps() {
        let progress = TripDetailRevealPolicy.quantizedProgress(rawProgress: 0.9, tick: 8, tickCount: 16)
        XCTAssertEqual(progress, 0.5, accuracy: 0.0001)
    }
}
