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
/// Camera center is the vehicle itself so the puck sits on the screen midpoint.
struct LiveFollowCamera {
    /// Below this, `course` is too noisy — keep the last accepted heading.
    static let minimumSpeedForHeadingMps: Double = 5.0 / 3.6
    /// Legacy per-sample blend factor (tests / helpers). Prefer `headingTauSeconds` at runtime.
    static let headingSmoothing: Double = 0.34
    /// Time constant for published heading — higher = softer map rotation in turns.
    static let headingTauSeconds: TimeInterval = 0.56
    /// Ease each GPS course sample into the heading target (avoids 1 Hz target snaps).
    static let targetHeadingIngestFactor: Double = 0.42
    /// Blend GPS course with path bearing when the fix moved enough to trust geometry.
    static let pathHeadingBlend: Double = 0.48
    static let pathHeadingMinMoveMeters: CLLocationDistance = 6
    /// Softer than a raw GPS chase so 1 Hz samples do not hitch the puck.
    static let positionTauSeconds: TimeInterval = 0.24
    static let modeTauSeconds: TimeInterval = 0.20
    /// Ease GPS speed into dead-reckon so a noisy speed sample cannot yank the camera.
    static let speedIngestFactor: Double = 0.38
    /// Ignore sub-meter “GPS is behind the puck” noise — never rewind along heading.
    static let alongTrackRewindDeadbandMeters: CLLocationDistance = 0.15
    /// Cap dead-reckoning so a lost fix does not fly the puck forever.
    static let maxDeadReckonSeconds: TimeInterval = 1.2
    /// Ignore absurd frame gaps (app backgrounded, debugger pause).
    static let maxTickDeltaSeconds: TimeInterval = 0.05

    /// Closer than overview maps — “on the road” nav feel (Apple Maps follow).
    static let pitch3D: Double = 62
    static let pitch2D: Double = 0
    static let distance3D: CLLocationDistance = 220
    static let distance2D: CLLocationDistance = 520

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

    /// Published vehicle position (puck). `pose.center` matches this coordinate.
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
    private var lastSampleTimestamp: Date?
    private var lastSampleCoordinate: CLLocationCoordinate2D?
    private var hasAcceptedHeading = false
    private var hasIngestedSpeed = false
    private var publishedPitchDegrees: Double = pitch3D
    private var publishedDistanceMeters: CLLocationDistance = distance3D

    var pose: Pose? {
        guard let center else { return nil }
        return Pose(
            center: center,
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
        let wasFrozen = isFrozen
        if isPaused {
            isFrozen = true
            return
        }
        isFrozen = false

        // Display-link re-feeds `lastLocation` every frame. Re-ingesting the same fix
        // must not reset the dead-reckon clock — that pins the puck to 1 Hz GPS snaps.
        if isSameSample(as: location) {
            return
        }

        let isFirstFix = center == nil
        let stampAdvanced = lastSampleTimestamp.map { location.timestamp > $0 } ?? true
        let previousSampleCoordinate = lastSampleCoordinate
        lastSampleTimestamp = location.timestamp
        lastSampleCoordinate = location.coordinate
        targetCoordinate = location.coordinate
        let rawSpeed = max(0, location.speed)
        if hasIngestedSpeed {
            targetSpeedMps += (rawSpeed - targetSpeedMps) * Self.speedIngestFactor
        } else {
            targetSpeedMps = rawSpeed
            hasIngestedSpeed = true
        }
        if stampAdvanced, abs(now.timeIntervalSince(location.timestamp)) <= 5 {
            lastFixAt = location.timestamp
        } else {
            lastFixAt = now
        }

        if shouldAcceptCourse(from: location) {
            let raw = Self.normalizedHeading(location.course)
            var aim = raw
            if !reduceMotion, let previousSampleCoordinate {
                let moved = CLLocation(
                    latitude: previousSampleCoordinate.latitude,
                    longitude: previousSampleCoordinate.longitude
                )
                .distance(from: CLLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ))
                if moved >= Self.pathHeadingMinMoveMeters {
                    let pathBearing = Self.bearingDegrees(
                        from: previousSampleCoordinate,
                        to: location.coordinate
                    )
                    aim = Self.smoothedHeading(
                        from: aim,
                        toward: pathBearing,
                        factor: Self.pathHeadingBlend
                    )
                }
            }
            if !hasAcceptedHeading {
                targetHeadingDegrees = aim
                headingDegrees = aim
                hasAcceptedHeading = true
            } else if reduceMotion {
                targetHeadingDegrees = aim
            } else {
                targetHeadingDegrees = Self.smoothedHeading(
                    from: targetHeadingDegrees,
                    toward: aim,
                    factor: Self.targetHeadingIngestFactor
                )
            }
        }

        if isFirstFix || wasFrozen {
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

        var predicted = target
        if targetSpeedMps > 0.5, hasAcceptedHeading, reckonAge > 0 {
            predicted = Self.coordinate(
                from: target,
                headingDegrees: headingDegrees,
                distanceMeters: targetSpeedMps * reckonAge
            )
        }
        if let current = center, hasAcceptedHeading, targetSpeedMps > 0.5 {
            predicted = Self.withoutAlongTrackRewind(
                current: current,
                predicted: predicted,
                headingDegrees: headingDegrees
            )
        }
        let positionAlpha = 1 - exp(-clampedDt / Self.positionTauSeconds)
        if let current = center {
            center = Self.lerpCoordinate(from: current, toward: predicted, factor: positionAlpha)
        } else {
            center = predicted
        }

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
        hasIngestedSpeed = true
        lastFixAt = now
        lastSampleTimestamp = location.timestamp
        lastSampleCoordinate = location.coordinate
        if shouldAcceptCourse(from: location) {
            let raw = Self.normalizedHeading(location.course)
            targetHeadingDegrees = raw
            headingDegrees = raw
            hasAcceptedHeading = true
        }
        snapPublished(to: location.coordinate)
    }

    /// Instantly match published pitch/distance to the current 2D/3D mode (no lerp).
    mutating func snapDimensionMode() {
        publishedPitchDegrees = uses3D ? Self.pitch3D : Self.pitch2D
        publishedDistanceMeters = uses3D ? Self.distance3D : Self.distance2D
    }

    mutating func reset() {
        center = nil
        headingDegrees = 0
        isFrozen = false
        hasAcceptedHeading = false
        hasIngestedSpeed = false
        targetCoordinate = nil
        targetHeadingDegrees = 0
        targetSpeedMps = 0
        lastFixAt = nil
        lastSampleTimestamp = nil
        lastSampleCoordinate = nil
        publishedPitchDegrees = Self.pitch3D
        publishedDistanceMeters = Self.distance3D
    }

    private func isSameSample(as location: CLLocation) -> Bool {
        guard let stamp = lastSampleTimestamp, let coordinate = lastSampleCoordinate else {
            return false
        }
        let sameStamp = abs(location.timestamp.timeIntervalSince(stamp)) < 0.000_1
        let sameCoord = abs(coordinate.latitude - location.coordinate.latitude) < 1e-12
            && abs(coordinate.longitude - location.coordinate.longitude) < 1e-12
        return sameStamp && sameCoord
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

    /// Initial bearing from `from` to `to` (degrees, clockwise from north).
    static func bearingDegrees(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return normalizedHeading(atan2(y, x) * 180 / .pi)
    }

    /// Meters of `to` ahead of `from` along `headingDegrees` (negative = behind).
    static func alongTrackMeters(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        headingDegrees: CLLocationDirection
    ) -> CLLocationDistance {
        let distance = CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
        guard distance > 0 else { return 0 }
        var delta = bearingDegrees(from: from, to: to) - headingDegrees
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return distance * cos(delta * .pi / 180)
    }

    /// Keep the puck from sliding backward when a stale GPS sample lands behind dead-reckon.
    static func withoutAlongTrackRewind(
        current: CLLocationCoordinate2D,
        predicted: CLLocationCoordinate2D,
        headingDegrees: CLLocationDirection
    ) -> CLLocationCoordinate2D {
        let along = alongTrackMeters(from: current, to: predicted, headingDegrees: headingDegrees)
        guard along < -alongTrackRewindDeadbandMeters else { return predicted }
        return coordinate(from: predicted, headingDegrees: headingDegrees, distanceMeters: -along)
    }

    static func lerpCoordinate(
        from: CLLocationCoordinate2D,
        toward: CLLocationCoordinate2D,
        factor: Double
    ) -> CLLocationCoordinate2D {
        let t = min(1, max(0, factor))
        return CLLocationCoordinate2D(
            latitude: from.latitude + (toward.latitude - from.latitude) * t,
            longitude: from.longitude + (toward.longitude - from.longitude) * t
        )
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
