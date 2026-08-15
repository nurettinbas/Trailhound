import CoreLocation
import Foundation

/// Pure camera pose for the live follow map — no MapKit view ownership.
///
/// Two layers:
/// 1. **Target** — updated on each GPS sample (`ingest`). Course only advances when
///    trustworthy and speed is high enough; otherwise the last good heading is held.
/// 2. **Published** — advanced every display tick (`tick`) with dead-reckoning and
///    time-constant heading/pitch/distance so the map stays smooth between ~1 Hz fixes.
///
/// Camera center is nudged ahead of the vehicle along the *published* heading so more
/// road sits above the puck (Maps / CarPlay-style driving feel).
struct LiveFollowCamera {
    /// Below this, `course` is too noisy — keep the last accepted heading.
    static let minimumSpeedForHeadingMps: Double = 5.0 / 3.6
    /// Legacy per-sample blend factor (tests / helpers). Prefer `headingTauSeconds` at runtime.
    static let headingSmoothing: Double = 0.34
    /// Time constant for heading (and 2D/3D) exponential approach toward the target.
    static let headingTauSeconds: TimeInterval = 0.20
    static let modeTauSeconds: TimeInterval = 0.20
    /// Cap dead-reckoning so a lost fix does not fly the puck forever.
    static let maxDeadReckonSeconds: TimeInterval = 1.2
    /// Ignore absurd frame gaps (app backgrounded, debugger pause).
    static let maxTickDeltaSeconds: TimeInterval = 0.05

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

    /// Published vehicle position (puck). Camera look-ahead is applied in `pose`.
    private(set) var center: CLLocationCoordinate2D?
    private(set) var headingDegrees: CLLocationDirection = 0
    private(set) var isFrozen: Bool = false
    /// When false, pitch stays flat and the camera sits higher.
    var uses3D: Bool = true
    /// Skip interpolation — published pose snaps to the GPS target each tick.
    var reduceMotion: Bool = false

    private var targetCoordinate: CLLocationCoordinate2D?
    private var targetHeadingDegrees: CLLocationDirection = 0
    private var targetSpeedMps: Double = 0
    private var lastFixAt: Date?
    private var hasAcceptedHeading = false
    private var publishedPitchDegrees: Double = pitch3D
    private var publishedDistanceMeters: CLLocationDistance = distance3D

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
            distanceMeters: publishedDistanceMeters,
            pitchDegrees: publishedPitchDegrees
        )
    }

    /// Update the GPS target. Does not publish a new camera pose by itself — call `tick`.
    /// First fix (and `forceRecenter`) snap the published state immediately.
    mutating func ingest(
        location: CLLocation,
        isPaused: Bool,
        now: Date = Date()
    ) {
        if isPaused {
            isFrozen = true
            return
        }
        isFrozen = false

        let isFirstFix = center == nil
        targetCoordinate = location.coordinate
        targetSpeedMps = max(0, location.speed)
        lastFixAt = now

        if shouldAcceptCourse(from: location) {
            let raw = Self.normalizedHeading(location.course)
            targetHeadingDegrees = raw
            if !hasAcceptedHeading {
                headingDegrees = raw
                hasAcceptedHeading = true
            }
        }

        if isFirstFix {
            snapPublished(to: location.coordinate)
        }
    }

    /// Advance the published pose by `dt` seconds. Returns `true` when a pose is available
    /// and should be written to the map (frozen sessions return `false`).
    @discardableResult
    mutating func tick(dt: TimeInterval, now: Date = Date()) -> Bool {
        guard !isFrozen else { return false }
        guard let target = targetCoordinate, let fixAt = lastFixAt else { return false }

        if reduceMotion {
            snapPublished(to: target)
            if hasAcceptedHeading {
                headingDegrees = targetHeadingDegrees
            }
            return true
        }

        let clampedDt = min(max(dt, 0), Self.maxTickDeltaSeconds)
        let age = max(0, now.timeIntervalSince(fixAt))
        let reckonAge = min(age, Self.maxDeadReckonSeconds)

        var vehicle = target
        if targetSpeedMps > 0.5, hasAcceptedHeading, reckonAge > 0 {
            vehicle = Self.coordinate(
                from: target,
                headingDegrees: targetHeadingDegrees,
                distanceMeters: targetSpeedMps * reckonAge
            )
        }
        center = vehicle

        if hasAcceptedHeading {
            let alpha = 1 - exp(-clampedDt / Self.headingTauSeconds)
            headingDegrees = Self.smoothedHeading(
                from: headingDegrees,
                toward: targetHeadingDegrees,
                factor: alpha
            )
        }

        let targetPitch = uses3D ? Self.pitch3D : Self.pitch2D
        let targetDistance = uses3D ? Self.distance3D : Self.distance2D
        let modeAlpha = 1 - exp(-clampedDt / Self.modeTauSeconds)
        publishedPitchDegrees += (targetPitch - publishedPitchDegrees) * modeAlpha
        publishedDistanceMeters += (targetDistance - publishedDistanceMeters) * modeAlpha

        return true
    }

    /// Apply a location sample and immediately publish (bootstrap / tests without a display link).
    @discardableResult
    mutating func update(
        location: CLLocation,
        isPaused: Bool,
        now: Date = Date()
    ) -> Bool {
        let before = pose
        ingest(location: location, isPaused: isPaused, now: now)
        guard !isFrozen else { return false }
        _ = tick(dt: Self.headingTauSeconds * 4, now: now)
        return pose != before
    }

    /// Jump to the current fix and resume follow (recenter control).
    mutating func forceRecenter(location: CLLocation, now: Date = Date()) {
        isFrozen = false
        reduceMotion = false
        targetCoordinate = location.coordinate
        targetSpeedMps = max(0, location.speed)
        lastFixAt = now
        if shouldAcceptCourse(from: location) {
            let raw = Self.normalizedHeading(location.course)
            targetHeadingDegrees = raw
            headingDegrees = raw
            hasAcceptedHeading = true
        }
        snapPublished(to: location.coordinate)
    }

    mutating func reset() {
        center = nil
        headingDegrees = 0
        isFrozen = false
        hasAcceptedHeading = false
        targetCoordinate = nil
        targetHeadingDegrees = 0
        targetSpeedMps = 0
        lastFixAt = nil
        publishedPitchDegrees = Self.pitch3D
        publishedDistanceMeters = Self.distance3D
    }

    private mutating func snapPublished(to coordinate: CLLocationCoordinate2D) {
        center = coordinate
        publishedPitchDegrees = uses3D ? Self.pitch3D : Self.pitch2D
        publishedDistanceMeters = uses3D ? Self.distance3D : Self.distance2D
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
