import XCTest
@testable import Trailhound

final class RecordingMovementPolicyTests: XCTestCase {
    func testSmallDeltaIsIgnored() {
        let decision = RecordingMovementPolicy.decision(delta: 1.5, timeDelta: 1, speed: 10)
        XCTAssertEqual(decision, .ignore)
    }

    func testStationaryJitterIsIgnored() {
        let decision = RecordingMovementPolicy.decision(delta: 3, timeDelta: 2, speed: 0.2)
        XCTAssertEqual(decision, .ignore)
    }

    func testNormalCitySegmentAccumulates() {
        let decision = RecordingMovementPolicy.decision(delta: 80, timeDelta: 5, speed: 16)
        XCTAssertEqual(decision, .accumulate)
    }

    func testTimeScaledSegmentAccumulates() {
        let decision = RecordingMovementPolicy.decision(delta: 400, timeDelta: 20, speed: 20)
        XCTAssertEqual(decision, .accumulate)
    }

    func testImpossibleJumpIsGapResume() {
        let decision = RecordingMovementPolicy.decision(delta: 800, timeDelta: 2, speed: 30)
        XCTAssertEqual(decision, .gapResume)
    }

    func testModerateGapAfterOutageAccumulatesInsteadOfSticking() {
        let decision = RecordingMovementPolicy.decision(delta: 600, timeDelta: 30, speed: 20)
        XCTAssertEqual(decision, .accumulate)
    }

    func testSparseCoastalGapAccumulatesDistance() {
        // 8 km in 10 min ≈ 13 m/s — real driving with sparse GPS; must count toward distance.
        let decision = RecordingMovementPolicy.decision(delta: 8000, timeDelta: 600, speed: 20)
        XCTAssertEqual(decision, .accumulate)
    }

    func testImpliedSpeedTooHighIsGapResume() {
        let decision = RecordingMovementPolicy.decision(delta: 400, timeDelta: 5, speed: 40)
        XCTAssertEqual(decision, .gapResume)
    }

    func testPlausibleRecordedSpeedBounds() {
        XCTAssertFalse(RecordingMovementPolicy.isPlausibleRecordedSpeed(0))
        XCTAssertFalse(RecordingMovementPolicy.isPlausibleRecordedSpeed(-1))
        XCTAssertTrue(RecordingMovementPolicy.isPlausibleRecordedSpeed(36.4)) // ~131 km/h
        XCTAssertFalse(RecordingMovementPolicy.isPlausibleRecordedSpeed(71))
    }

    func testSparseGapCountsDistanceButDoesNotDrawMapChord() {
        XCTAssertTrue(
            RecordingMovementPolicy.decision(delta: 8000, timeDelta: 600, speed: 20) == .accumulate
        )
        XCTAssertFalse(
            RecordingMovementPolicy.shouldDrawMapSegment(delta: 8000, timeDelta: 600, speed: 20)
        )
    }

    func testShortSegmentDrawsOnMap() {
        XCTAssertTrue(
            RecordingMovementPolicy.shouldDrawMapSegment(delta: 120, timeDelta: 8, speed: 16)
        )
    }

    func testEffectiveSpeedUsesImpliedWhenGPSSpeedInvalid() {
        let implied = RecordingMovementPolicy.effectiveSpeedMps(
            locationSpeedMps: -1,
            delta: 100,
            timeDelta: 5
        )
        XCTAssertEqual(implied ?? 0, 20, accuracy: 0.01)
    }
}
