import CoreLocation
import XCTest
@testable import Trailhound

final class LiveFollowCameraTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 5_000)
    private let frame: TimeInterval = 1.0 / 60.0

    func testLowSpeedHoldsHeading() {
        var camera = LiveFollowCamera()
        let moving = location(lat: 41.0, lon: 29.0, speedMps: 15, course: 90, courseAccuracy: 5)
        camera.ingest(location: moving, isPaused: false, now: baseDate)
        XCTAssertTrue(camera.tick(dt: frame, now: baseDate))
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)

        let crawling = location(lat: 41.0001, lon: 29.0, speedMps: 1, course: 180, courseAccuracy: 5)
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: crawling, isPaused: false, now: later)
        XCTAssertTrue(camera.tick(dt: frame, now: later))
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)
    }

    func testBadCourseAccuracyHoldsHeading() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 8)
        camera.ingest(location: good, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)

        let badCourse = location(
            lat: 41.0002,
            lon: 29.0,
            speedMps: 20,
            course: 200,
            courseAccuracy: -1
        )
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: badCourse, isPaused: false, now: later)
        _ = camera.tick(dt: frame, now: later)
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)
    }

    func testPauseFreezesCameraUpdates() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 18, course: 10, courseAccuracy: 4)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        let frozenHeading = camera.headingDegrees
        let frozenLat = camera.center?.latitude

        let next = location(lat: 41.01, lon: 29.01, speedMps: 18, course: 90, courseAccuracy: 4)
        camera.ingest(location: next, isPaused: true, now: baseDate.addingTimeInterval(0.3))
        XCTAssertFalse(camera.tick(dt: frame, now: baseDate.addingTimeInterval(0.3)))
        XCTAssertTrue(camera.isFrozen)
        XCTAssertEqual(camera.headingDegrees, frozenHeading, accuracy: 0.01)
        XCTAssertEqual(camera.center?.latitude, frozenLat)
    }

    func testHeadingApproachesTargetOverTicks() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.headingDegrees, 0, accuracy: 0.01)

        let second = location(lat: 41.0003, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        let t1 = baseDate.addingTimeInterval(1)
        camera.ingest(location: second, isPaused: false, now: t1)

        var previous = camera.headingDegrees
        for step in 1...12 {
            let now = t1.addingTimeInterval(Double(step) * frame)
            XCTAssertTrue(camera.tick(dt: frame, now: now))
            XCTAssertGreaterThanOrEqual(camera.headingDegrees, previous - 0.001)
            previous = camera.headingDegrees
        }
        XCTAssertGreaterThan(camera.headingDegrees, 5)
        XCTAssertLessThan(camera.headingDegrees, 90)
    }

    func testOneHzGPSWithDisplayTicksIsMonotonic() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )

        var lastLat = camera.center?.latitude ?? -1
        for second in 0..<3 {
            let fixAt = baseDate.addingTimeInterval(Double(second))
            let lat = 41.0 + Double(second) * 0.0002
            camera.ingest(
                location: location(lat: lat, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
                isPaused: false,
                now: fixAt
            )
            for frameIndex in 0..<60 {
                let now = fixAt.addingTimeInterval(Double(frameIndex) * frame)
                XCTAssertTrue(camera.tick(dt: frame, now: now))
                let current = camera.center?.latitude ?? -1
                XCTAssertGreaterThanOrEqual(current, lastLat - 0.000_000_1)
                lastLat = current
            }
        }
    }

    func testDeadReckonCapsAfterMaxAge() {
        var camera = LiveFollowCamera()
        let fix = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: fix, isPaused: false, now: baseDate)

        let atCap = baseDate.addingTimeInterval(LiveFollowCamera.maxDeadReckonSeconds)
        for _ in 0..<90 {
            _ = camera.tick(dt: frame, now: atCap)
        }
        let latAtCap = camera.center?.latitude ?? -1

        let later = baseDate.addingTimeInterval(LiveFollowCamera.maxDeadReckonSeconds + 2)
        for _ in 0..<30 {
            _ = camera.tick(dt: frame, now: later)
        }
        XCTAssertEqual(camera.center?.latitude ?? -1, latAtCap, accuracy: 0.000_000_1)
    }

    func testForceRecenterUpdatesImmediately() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 30, courseAccuracy: 5)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let jumped = location(lat: 42.0, lon: 30.0, speedMps: 16, course: 120, courseAccuracy: 5)
        camera.forceRecenter(location: jumped, now: baseDate.addingTimeInterval(0.05))
        XCTAssertEqual(camera.center?.latitude ?? -1, 42.0, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 120, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
    }

    func testSmoothedHeadingTakesShortestArc() {
        let blended = LiveFollowCamera.smoothedHeading(from: 350, toward: 10, factor: 0.5)
        XCTAssertEqual(blended, 0, accuracy: 0.01)
    }

    func testHeadingWrapsShortestArcAcrossNorth() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 350, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)

        camera.ingest(
            location: location(lat: 41.0001, lon: 29.0, speedMps: 20, course: 10, courseAccuracy: 5),
            isPaused: false,
            now: baseDate.addingTimeInterval(1)
        )
        for step in 1...30 {
            _ = camera.tick(
                dt: frame,
                now: baseDate.addingTimeInterval(1 + Double(step) * frame)
            )
        }
        // Should approach 10 via 0, never go the long way through 180.
        XCTAssertLessThan(camera.headingDegrees, 20)
        XCTAssertTrue(camera.headingDegrees < 90 || camera.headingDegrees > 340)
    }

    func testPoseCentersOnVehicleIn3D() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        guard let pose = camera.pose else {
            return XCTFail("expected pose")
        }
        XCTAssertEqual(pose.center.latitude, 41.0, accuracy: 0.00001)
        XCTAssertEqual(pose.center.longitude, 29.0, accuracy: 0.00001)
        XCTAssertEqual(pose.pitchDegrees, LiveFollowCamera.pitch3D, accuracy: 0.5)
        XCTAssertEqual(pose.distanceMeters, LiveFollowCamera.distance3D, accuracy: 1)
    }

    func testPoseFlattensIn2D() {
        var camera = LiveFollowCamera()
        camera.uses3D = false
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        guard let pose = camera.pose else {
            return XCTFail("expected pose")
        }
        XCTAssertEqual(pose.pitchDegrees, 0, accuracy: 0.5)
        XCTAssertEqual(pose.distanceMeters, LiveFollowCamera.distance2D, accuracy: 1)
        XCTAssertEqual(pose.center.latitude, 41.0, accuracy: 0.00001)
        XCTAssertEqual(pose.center.longitude, 29.0, accuracy: 0.00001)
    }

    func testSnapDimensionModeJumpsWithoutLerp() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, LiveFollowCamera.pitch3D, accuracy: 0.5)

        camera.uses3D = false
        camera.snapDimensionMode()
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, LiveFollowCamera.pitch2D, accuracy: 0.01)
        XCTAssertEqual(camera.pose?.distanceMeters ?? -1, LiveFollowCamera.distance2D, accuracy: 0.01)
    }

    func testModeLerpBlendsPitchWhenSwitching2D3D() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, LiveFollowCamera.pitch3D, accuracy: 0.5)

        camera.uses3D = false
        _ = camera.tick(dt: frame, now: baseDate.addingTimeInterval(frame))
        let mid = camera.pose?.pitchDegrees ?? -1
        XCTAssertGreaterThan(mid, 0)
        XCTAssertLessThan(mid, LiveFollowCamera.pitch3D)

        for step in 1...90 {
            _ = camera.tick(dt: frame, now: baseDate.addingTimeInterval(Double(step) * frame))
        }
        XCTAssertEqual(camera.pose?.pitchDegrees ?? -1, 0, accuracy: 1)
    }

    func testLookAheadCoordinateNorth() {
        let origin = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let ahead = LiveFollowCamera.coordinate(from: origin, headingDegrees: 0, distanceMeters: 100)
        XCTAssertGreaterThan(ahead.latitude, origin.latitude)
        XCTAssertEqual(ahead.longitude, origin.longitude, accuracy: 0.0002)
    }

    func testPoseNilUntilFirstUpdate() {
        let camera = LiveFollowCamera()
        XCTAssertNil(camera.pose)
        XCTAssertNil(camera.center)
    }

    func testResetClearsPoseAndHeading() {
        var camera = LiveFollowCamera()
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 5)
        camera.ingest(location: start, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        XCTAssertNotNil(camera.pose)

        camera.reset()
        XCTAssertNil(camera.center)
        XCTAssertNil(camera.pose)
        XCTAssertEqual(camera.headingDegrees, 0, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
    }

    func testResumeAfterPauseUnfreezesAndUpdates() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 18, course: 10, courseAccuracy: 4)
        camera.ingest(location: first, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        camera.ingest(
            location: location(lat: 41.01, lon: 29.01, speedMps: 18, course: 90, courseAccuracy: 4),
            isPaused: true,
            now: baseDate.addingTimeInterval(0.3)
        )
        XCTAssertTrue(camera.isFrozen)

        let resumed = location(lat: 41.02, lon: 29.02, speedMps: 18, course: 90, courseAccuracy: 4)
        let later = baseDate.addingTimeInterval(0.6)
        camera.ingest(location: resumed, isPaused: false, now: later)
        XCTAssertTrue(camera.tick(dt: frame, now: later))
        XCTAssertFalse(camera.isFrozen)
        XCTAssertEqual(camera.center?.latitude ?? -1, 41.02, accuracy: 0.0001)
    }

    func testNegativeCourseHoldsHeading() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 5)
        camera.ingest(location: good, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let unavailable = location(
            lat: 41.0002,
            lon: 29.0,
            speedMps: 20,
            course: -1,
            courseAccuracy: 5
        )
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: unavailable, isPaused: false, now: later)
        _ = camera.tick(dt: frame, now: later)
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)
        let lat = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(lat, 41.0)
        XCTAssertLessThanOrEqual(lat, 41.0002)
    }

    func testReingestSameFixDoesNotResetDeadReckon() {
        var camera = LiveFollowCamera()
        let fix = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        camera.ingest(location: fix, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)
        let afterFirst = camera.center?.latitude ?? -1

        for step in 1...30 {
            let now = baseDate.addingTimeInterval(Double(step) * frame)
            camera.ingest(location: fix, isPaused: false, now: now)
            _ = camera.tick(dt: frame, now: now)
        }
        let afterReplay = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(afterReplay, afterFirst)
    }

    func testPublishedCenterEasesTowardNewFix() {
        var camera = LiveFollowCamera()
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 0.2, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        _ = camera.tick(dt: frame, now: baseDate)

        let jumped = location(lat: 41.01, lon: 29.0, speedMps: 0.2, course: 0, courseAccuracy: 5)
        let later = baseDate.addingTimeInterval(1)
        camera.ingest(location: jumped, isPaused: false, now: later)
        _ = camera.tick(dt: frame, now: later)
        let mid = camera.center?.latitude ?? -1
        XCTAssertGreaterThan(mid, 41.0)
        XCTAssertLessThan(mid, 41.01)
    }

    func testForceRecenterAtLowSpeedKeepsHeading() {
        var camera = LiveFollowCamera()
        let moving = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 30, courseAccuracy: 5)
        camera.ingest(location: moving, isPaused: false, now: baseDate)
        _ = camera.tick(dt: frame, now: baseDate)

        let crawling = location(lat: 42.0, lon: 30.0, speedMps: 0.5, course: 200, courseAccuracy: 5)
        camera.forceRecenter(location: crawling, now: baseDate.addingTimeInterval(0.05))
        XCTAssertEqual(camera.center?.latitude ?? -1, 42.0, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 30, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
    }

    func testReduceMotionSnapsToTarget() {
        var camera = LiveFollowCamera()
        camera.reduceMotion = true
        camera.ingest(
            location: location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5),
            isPaused: false,
            now: baseDate
        )
        camera.ingest(
            location: location(lat: 41.01, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5),
            isPaused: false,
            now: baseDate.addingTimeInterval(1)
        )
        XCTAssertTrue(camera.tick(dt: frame, now: baseDate.addingTimeInterval(1)))
        XCTAssertEqual(camera.center?.latitude ?? -1, 41.01, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)
    }

    func testNormalizedHeadingWraps() {
        XCTAssertEqual(LiveFollowCamera.normalizedHeading(360), 0, accuracy: 0.01)
        XCTAssertEqual(LiveFollowCamera.normalizedHeading(-90), 270, accuracy: 0.01)
        XCTAssertEqual(LiveFollowCamera.normalizedHeading(450), 90, accuracy: 0.01)
    }

    private func location(
        lat: Double,
        lon: Double,
        speedMps: Double,
        course: Double,
        courseAccuracy: Double
    ) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
            altitude: 0,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            courseAccuracy: courseAccuracy,
            speed: speedMps,
            speedAccuracy: 1,
            timestamp: baseDate
        )
    }
}
