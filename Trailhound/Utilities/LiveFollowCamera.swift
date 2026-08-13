import CoreLocation
import Foundation

/// Pure camera pose for the live follow map — no MapKit view ownership.
///
/// Heading only advances when GPS course is trustworthy and speed is high enough;
/// otherwise the last good heading is held so the map does not spin at a light.
/// Camera center is nudged ahead of the vehicle so more road sits above the puck
/// (CarPlay-style driving feel).
struct LiveFollowCamera {
    /// Below this, `course` is too noisy — keep the last accepted heading.
    static let minimumSpeedForHeadingMps: Double = 5.0 / 3.6
    /// Blend toward new course each accepted sample (0…1). Lower = less seasick.
    static let headingSmoothing: Double = 0.34

    /// Closer than overview maps — “on the road” nav feel (Apple Maps follow).
    static let pitch3D: Double = 62
    static let pitch2D: Double = 0
    static let distance3D: CLLocationDistance = 220
    static let distance2D: CLLocationDistance = 520
    /// How far ahead of the car the camera looks (meters along heading).
    static let lookAhead3DMeters: CLLocationDistance = 36
    static let lookAhead2DMeters: CLLocationDistance = 55

    /// Legacy aliases used by call sites / bootstrap.
    static var pitchDegrees: Double { pitch3D }
    static var distanceMeters: CLLocationDistance { distance3D }

    struct Pose: Equatable {
        var center: CLLocationCoordinate2D
        var headingDegrees: CLLocationDirection
        var distanceMeters: CLLocationDistance
        var pitchDegrees: Double

        static func == (lhs: Pose, rhs: Pose) -> Bool {
            lhs.center.latitude == rhs.center.latitude
                && lhs.center.longitude == rhs.center.longitude
                && lhs.headingDegrees == rhs.headingDegrees
                && lhs.distanceMeters == rhs.distanceMeters
                && lhs.pitchDegrees == rhs.pitchDegrees
        }
    }

    private(set) var center: CLLocationCoordinate2D?
    private(set) var headingDegrees: CLLocationDirection = 0
    private(set) var isFrozen: Bool = false
    /// When false, pitch stays flat and the camera sits higher.
    var uses3D: Bool = true

    private var sampler = RecordingDisplaySampler(minimumInterval: 0.25)
    private var hasAcceptedHeading = false

    var pose: Pose? {
        guard let center else { return nil }
        let lookAhead = uses3D ? Self.lookAhead3DMeters : Self.lookAhead2DMeters
        let cameraCenter = Self.coordinate(
            from: center,
            headingDegrees: headingDegrees,
            distanceMeters: lookAhead
        )
        return Pose(
            center: cameraCenter,
            headingDegrees: headingDegrees,
            distanceMeters: uses3D ? Self.distance3D : Self.distance2D,
            pitchDegrees: uses3D ? Self.pitch3D : Self.pitch2D
        )
    }

    /// Apply a location sample. Returns `true` when the published pose changed.
    mutating func update(
        location: CLLocation,
        isPaused: Bool,
        now: Date = Date()
    ) -> Bool {
        if isPaused {
            if !isFrozen {
                isFrozen = true
            }
            return false
        }
        isFrozen = false

        guard sampler.shouldPublish(now: now) else { return false }

        center = location.coordinate
        if shouldAcceptCourse(from: location) {
            let raw = Self.normalizedHeading(location.course)
            if hasAcceptedHeading {
                headingDegrees = Self.smoothedHeading(
                    from: headingDegrees,
                    toward: raw,
                    factor: Self.headingSmoothing
                )
            } else {
                headingDegrees = raw
                hasAcceptedHeading = true
            }
        }
        return true
    }

    /// Jump to the current fix and resume follow (recenter control).
    mutating func forceRecenter(location: CLLocation, now: Date = Date()) {
        isFrozen = false
        sampler.markPublished(now: now)
        center = location.coordinate
        if shouldAcceptCourse(from: location) {
            headingDegrees = Self.normalizedHeading(location.course)
            hasAcceptedHeading = true
        }
    }

    mutating func reset() {
        center = nil
        headingDegrees = 0
        isFrozen = false
        hasAcceptedHeading = false
        sampler.reset()
    }

    private func shouldAcceptCourse(from location: CLLocation) -> Bool {
        guard location.courseAccuracy >= 0 else { return false }
        guard location.speed >= Self.minimumSpeedForHeadingMps else { return false }
        // Core Location uses negative course when unavailable.
        guard location.course >= 0 else { return false }
        return true
    }

    static func normalizedHeading(_ degrees: CLLocationDirection) -> CLLocationDirection {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// Shortest-arc blend between two compass headings.
    static func smoothedHeading(
        from current: CLLocationDirection,
        toward target: CLLocationDirection,
        factor: Double
    ) -> CLLocationDirection {
        let t = min(1, max(0, factor))
        var delta = target - current
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return normalizedHeading(current + delta * t)
    }

    /// Destination `distanceMeters` along `headingDegrees` from `from` (WGS84 approx).
    static func coordinate(
        from: CLLocationCoordinate2D,
        headingDegrees: CLLocationDirection,
        distanceMeters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        guard distanceMeters > 0 else { return from }
        let earthRadius = 6_378_137.0
        let bearing = headingDegrees * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let angular = distanceMeters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
}
