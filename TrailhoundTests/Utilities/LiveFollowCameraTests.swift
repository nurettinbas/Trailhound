import CoreLocation
import XCTest
@testable import Trailhound

final class LiveFollowCameraTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 5_000)

    func testLowSpeedHoldsHeading() {
        var camera = LiveFollowCamera()
        let moving = location(lat: 41.0, lon: 29.0, speedMps: 15, course: 90, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: moving, isPaused: false, now: baseDate))
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)

        let crawling = location(lat: 41.0001, lon: 29.0, speedMps: 1, course: 180, courseAccuracy: 5)
        XCTAssertTrue(
            camera.update(location: crawling, isPaused: false, now: baseDate.addingTimeInterval(0.3))
        )
        XCTAssertEqual(camera.headingDegrees, 90, accuracy: 0.01)
    }

    func testBadCourseAccuracyHoldsHeading() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 8)
        XCTAssertTrue(camera.update(location: good, isPaused: false, now: baseDate))
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)

        let badCourse = location(
            lat: 41.0002,
            lon: 29.0,
            speedMps: 20,
            course: 200,
            courseAccuracy: -1
        )
        XCTAssertTrue(
            camera.update(location: badCourse, isPaused: false, now: baseDate.addingTimeInterval(0.3))
        )
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)
    }

    func testPauseFreezesCameraUpdates() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 18, course: 10, courseAccuracy: 4)
        XCTAssertTrue(camera.update(location: first, isPaused: false, now: baseDate))
        let frozenHeading = camera.headingDegrees
        let frozenLat = camera.center?.latitude

        let next = location(lat: 41.01, lon: 29.01, speedMps: 18, course: 90, courseAccuracy: 4)
        XCTAssertFalse(
            camera.update(location: next, isPaused: true, now: baseDate.addingTimeInterval(0.3))
        )
        XCTAssertTrue(camera.isFrozen)
        XCTAssertEqual(camera.headingDegrees, frozenHeading, accuracy: 0.01)
        XCTAssertEqual(camera.center?.latitude, frozenLat)
    }

    func testHeadingSmoothingBlendsTowardNewCourse() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: first, isPaused: false, now: baseDate))

        let second = location(lat: 41.0003, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        XCTAssertTrue(
            camera.update(location: second, isPaused: false, now: baseDate.addingTimeInterval(0.3))
        )
        // First accept sets 0; second blends with headingSmoothing, not a hard jump to 90.
        XCTAssertGreaterThan(camera.headingDegrees, 0)
        XCTAssertLessThan(camera.headingDegrees, 90)
        XCTAssertEqual(
            camera.headingDegrees,
            LiveFollowCamera.smoothedHeading(from: 0, toward: 90, factor: LiveFollowCamera.headingSmoothing),
            accuracy: 0.01
        )
    }

    func testSamplerRateLimitsUpdates() {
        var camera = LiveFollowCamera()
        let a = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 0, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: a, isPaused: false, now: baseDate))
        let b = location(lat: 41.0001, lon: 29.0, speedMps: 16, course: 10, courseAccuracy: 5)
        XCTAssertFalse(camera.update(location: b, isPaused: false, now: baseDate.addingTimeInterval(0.1)))
    }

    func testForceRecenterUpdatesImmediately() {
        var camera = LiveFollowCamera()
        let first = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 30, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: first, isPaused: false, now: baseDate))

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

    func testPoseLooksAheadAlongHeadingIn3D() {
        var camera = LiveFollowCamera()
        camera.uses3D = true
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 0, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: start, isPaused: false, now: baseDate))

        guard let pose = camera.pose else {
            return XCTFail("expected pose")
        }
        // Course 0 = north → camera center should be north of the vehicle.
        XCTAssertGreaterThan(pose.center.latitude, 41.0)
        XCTAssertEqual(pose.center.longitude, 29.0, accuracy: 0.0005)
        XCTAssertEqual(pose.pitchDegrees, LiveFollowCamera.pitch3D, accuracy: 0.01)
        XCTAssertEqual(pose.distanceMeters, LiveFollowCamera.distance3D, accuracy: 0.01)
    }

    func testPoseFlattensIn2D() {
        var camera = LiveFollowCamera()
        camera.uses3D = false
        let start = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 90, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: start, isPaused: false, now: baseDate))

        guard let pose = camera.pose else {
            return XCTFail("expected pose")
        }
        XCTAssertEqual(pose.pitchDegrees, 0, accuracy: 0.01)
        XCTAssertEqual(pose.distanceMeters, LiveFollowCamera.distance2D, accuracy: 0.01)
        // Course 90 = east → camera center east of the vehicle.
        XCTAssertGreaterThan(pose.center.longitude, 29.0)
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
        XCTAssertTrue(camera.update(location: start, isPaused: false, now: baseDate))
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
        XCTAssertTrue(camera.update(location: first, isPaused: false, now: baseDate))
        XCTAssertFalse(
            camera.update(
                location: location(lat: 41.01, lon: 29.01, speedMps: 18, course: 90, courseAccuracy: 4),
                isPaused: true,
                now: baseDate.addingTimeInterval(0.3)
            )
        )
        XCTAssertTrue(camera.isFrozen)

        let resumed = location(lat: 41.02, lon: 29.02, speedMps: 18, course: 90, courseAccuracy: 4)
        XCTAssertTrue(
            camera.update(location: resumed, isPaused: false, now: baseDate.addingTimeInterval(0.6))
        )
        XCTAssertFalse(camera.isFrozen)
        XCTAssertEqual(camera.center?.latitude ?? -1, 41.02, accuracy: 0.0001)
    }

    func testNegativeCourseHoldsHeading() {
        var camera = LiveFollowCamera()
        let good = location(lat: 41.0, lon: 29.0, speedMps: 20, course: 45, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: good, isPaused: false, now: baseDate))

        let unavailable = location(
            lat: 41.0002,
            lon: 29.0,
            speedMps: 20,
            course: -1,
            courseAccuracy: 5
        )
        XCTAssertTrue(
            camera.update(location: unavailable, isPaused: false, now: baseDate.addingTimeInterval(0.3))
        )
        XCTAssertEqual(camera.headingDegrees, 45, accuracy: 0.01)
        XCTAssertEqual(camera.center?.latitude ?? -1, 41.0002, accuracy: 0.0001)
    }

    func testForceRecenterAtLowSpeedKeepsHeading() {
        var camera = LiveFollowCamera()
        let moving = location(lat: 41.0, lon: 29.0, speedMps: 16, course: 30, courseAccuracy: 5)
        XCTAssertTrue(camera.update(location: moving, isPaused: false, now: baseDate))

        let crawling = location(lat: 42.0, lon: 30.0, speedMps: 0.5, course: 200, courseAccuracy: 5)
        camera.forceRecenter(location: crawling, now: baseDate.addingTimeInterval(0.05))
        XCTAssertEqual(camera.center?.latitude ?? -1, 42.0, accuracy: 0.0001)
        XCTAssertEqual(camera.headingDegrees, 30, accuracy: 0.01)
        XCTAssertFalse(camera.isFrozen)
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
