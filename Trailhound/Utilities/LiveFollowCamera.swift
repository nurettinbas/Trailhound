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
    static let headingTauSeconds: TimeInterval = 0.72
    /// Ease each GPS course sample into the heading target (avoids 1 Hz target snaps).
    static let targetHeadingIngestFactor: Double = 0.42
    /// Blend GPS course with path bearing when the fix moved enough to trust geometry.
    static let pathHeadingBlend: Double = 0.48
    static let pathHeadingMinMoveMeters: CLLocationDistance = 6
    /// Path bearing is used as heading when GPS course is missing (simulator / tunnels).
    static let pathHeadingFallbackMeters: CLLocationDistance = 4
    /// Published speed follows GPS. Long enough that a 1 Hz speed sample cannot pulse
    /// the scroll rate — a car's real acceleration is far slower than this lag.
    static let speedTauSeconds: TimeInterval = 0.55
    /// Slide onto the GPS lane without yanking the camera sideways. Kept fairly tight:
    /// dead-reckoning runs straight while the road bends, so a slow lateral pull leaves
    /// the puck sitting beside its own trail through a curve.
    static let lateralTauSeconds: TimeInterval = 0.50
    /// Catch up only when GPS is ahead — never rewind. Kept slow so the correction
    /// trims the integrated position instead of racing it.
    static let alongCatchupTauSeconds: TimeInterval = 1.20
    /// Ignore sub-step along-track noise, but small enough that real lag cannot settle in.
    static let alongCatchupDeadbandMeters: CLLocationDistance = 0.25
    static let maxImpliedSpeedMps: Double = 50
    static let modeTauSeconds: TimeInterval = 0.20
    /// Ease GPS speed into dead-reckon so a noisy speed sample cannot yank the camera.
    static let speedIngestFactor: Double = 0.38
    /// Beyond this the fix is stale and the coast starts bleeding off. Must stay well
    /// above the ~1 Hz fix interval, otherwise the puck stalls between every sample.
    static let maxDeadReckonSeconds: TimeInterval = 3.0
    /// How fast the coast decays once the fix is stale (never a hard stop).
    static let deadReckonDecayTauSeconds: TimeInterval = 1.0
    /// Ignore absurd frame gaps (app backgrounded, debugger pause). Generous enough
    /// that a few dropped frames still integrate the correct distance.
    static let maxTickDeltaSeconds: TimeInterval = 0.12

    /// Closer than overview maps — “on the road” nav feel (Apple Maps follow).
    static let pitch3D: Double = 62
    static let pitch2D: Double = 0
    /// Standstill eye distance. The camera pulls back with speed (see `followDistance`).
    static let distance3D: CLLocationDistance = 220
    static let distance2D: CLLocationDistance = 520
    static let distanceStretch3D: CLLocationDistance = 13
    static let distanceStretch2D: CLLocationDistance = 21
    static let distanceCap3D: CLLocationDistance = 620
    static let distanceCap2D: CLLocationDistance = 1_150

    /// Eye distance for the current speed — Apple Maps pulls back as you speed up.
    ///
    /// A fixed 220 m eye at motorway speed sweeps the ground past the screen so fast that
    /// every dropped frame reads as a lurch. Backing off cuts the on-screen angular rate
    /// and shows more road ahead, which is both calmer and more useful.
    static func followDistance(uses3D: Bool, speedMps: Double) -> CLLocationDistance {
        let base = uses3D ? distance3D : distance2D
        let stretch = max(0, speedMps) * (uses3D ? distanceStretch3D : distanceStretch2D)
        return min(base + stretch, uses3D ? distanceCap3D : distanceCap2D)
    }

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
    /// Integrated speed used every display tick (not the raw 1 Hz GPS speed).
    private var publishedSpeedMps: Double = 0
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
        let previousSampleTimestamp = lastSampleTimestamp
        let rawSpeed = Self.resolvedSpeedMps(
            location: location,
            previousCoordinate: previousSampleCoordinate,
            previousStamp: previousSampleTimestamp
        )
        lastSampleTimestamp = location.timestamp
        lastSampleCoordinate = location.coordinate
        targetCoordinate = location.coordinate
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

        let moved: CLLocationDistance = {
            guard let previousSampleCoordinate else { return 0 }
            return CLLocation(
                latitude: previousSampleCoordinate.latitude,
                longitude: previousSampleCoordinate.longitude
            )
            .distance(from: CLLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            ))
        }()
        var aim: CLLocationDirection?
        if shouldAcceptCourse(from: location) {
            var next = Self.normalizedHeading(location.course)
            if !reduceMotion, previousSampleCoordinate != nil, moved >= Self.pathHeadingMinMoveMeters {
                let pathBearing = Self.bearingDegrees(
                    from: previousSampleCoordinate!,
                    to: location.coordinate
                )
                next = Self.smoothedHeading(
                    from: next,
                    toward: pathBearing,
                    factor: Self.pathHeadingBlend
                )
            }
            aim = next
        } else if !hasAcceptedHeading, let previousSampleCoordinate, moved >= Self.pathHeadingFallbackMeters {
            aim = Self.bearingDegrees(from: previousSampleCoordinate, to: location.coordinate)
        }
        if let aim {
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
            // Speed first: `snapPublished` sizes the eye distance from it.
            publishedSpeedMps = targetSpeedMps
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

        let isStale = age > Self.maxDeadReckonSeconds
        if isStale {
            // Decay only — blending back toward the last GPS speed would fight the
            // decay and settle at a constant coast instead of stopping.
            publishedSpeedMps *= exp(-clampedDt / Self.deadReckonDecayTauSeconds)
        } else {
            let speedAlpha = 1 - exp(-clampedDt / Self.speedTauSeconds)
            publishedSpeedMps += (targetSpeedMps - publishedSpeedMps) * speedAlpha
        }

        // A fix says where the car *was*. Correcting toward that raw point parks the puck
        // a whole GPS interval behind reality, so the breadcrumb trail draws out ahead of
        // the vehicle and lurches forward once a second. Aim at where the car should be
        // *now* instead: the reference then advances at the same rate as the puck and stays
        // continuous across fixes, because a new fix arrives exactly as old age is spent.
        let liveTarget: CLLocationCoordinate2D = {
            guard !isStale, hasAcceptedHeading, publishedSpeedMps > 0.2 else { return target }
            return Self.coordinate(
                from: target,
                headingDegrees: headingDegrees,
                distanceMeters: publishedSpeedMps * min(age, Self.maxDeadReckonSeconds)
            )
        }()

        if let current = center {
            if publishedSpeedMps > 0.2, hasAcceptedHeading {
                let step = publishedSpeedMps * clampedDt
                let predicted = Self.coordinate(
                    from: current,
                    headingDegrees: headingDegrees,
                    distanceMeters: step
                )
                center = Self.correctedTowardGPS(
                    current: predicted,
                    gps: liveTarget,
                    headingDegrees: headingDegrees,
                    dt: clampedDt
                )
            } else if !isStale {
                let positionAlpha = 1 - exp(-clampedDt / Self.alongCatchupTauSeconds)
                center = Self.lerpCoordinate(from: current, toward: liveTarget, factor: positionAlpha)
            }
            // Stale fix with the coast spent: hold. Never rewind to an old position.
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
        let targetDistance = Self.followDistance(uses3D: uses3D, speedMps: publishedSpeedMps)
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
        targetSpeedMps = max(0, location.speed >= 0 ? location.speed : 0)
        hasIngestedSpeed = true
        publishedSpeedMps = targetSpeedMps
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
        publishedSpeedMps = targetSpeedMps
    }

    /// Instantly match published pitch/distance to the current 2D/3D mode (no lerp).
    mutating func snapDimensionMode() {
        publishedPitchDegrees = uses3D ? Self.pitch3D : Self.pitch2D
        publishedDistanceMeters = Self.followDistance(uses3D: uses3D, speedMps: publishedSpeedMps)
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
        publishedSpeedMps = 0
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
        publishedDistanceMeters = Self.followDistance(uses3D: uses3D, speedMps: publishedSpeedMps)
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

    /// GPS speed if valid; otherwise distance / time between samples (simulator often reports -1).
    static func resolvedSpeedMps(
        location: CLLocation,
        previousCoordinate: CLLocationCoordinate2D?,
        previousStamp: Date?
    ) -> Double {
        var implied = 0.0
        if let previousCoordinate, let previousStamp {
            let delta = location.timestamp.timeIntervalSince(previousStamp)
            if delta >= 0.2 {
                let distance = CLLocation(
                    latitude: previousCoordinate.latitude,
                    longitude: previousCoordinate.longitude
                )
                .distance(from: CLLocation(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude
                ))
                implied = min(distance / delta, maxImpliedSpeedMps)
            }
        }
        if location.speed >= 0 {
            if implied > 1.5, location.speed < implied * 0.25 {
                return implied
            }
            return location.speed
        }
        return implied
    }

    /// Nudge toward GPS: lateral always, along-track only when the fix is ahead.
    static func correctedTowardGPS(
        current: CLLocationCoordinate2D,
        gps: CLLocationCoordinate2D,
        headingDegrees: CLLocationDirection,
        dt: TimeInterval
    ) -> CLLocationCoordinate2D {
        let distance = CLLocation(latitude: current.latitude, longitude: current.longitude)
            .distance(from: CLLocation(latitude: gps.latitude, longitude: gps.longitude))
        guard distance > 0.05 else { return current }
        let along = alongTrackMeters(from: current, to: gps, headingDegrees: headingDegrees)
        var delta = bearingDegrees(from: current, to: gps) - headingDegrees
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        let cross = distance * sin(delta * .pi / 180)

        var result = current
        let lateralStep = cross * (1 - exp(-dt / lateralTauSeconds))
        if lateralStep > 0.02 {
            result = coordinate(
                from: result,
                headingDegrees: normalizedHeading(headingDegrees + 90),
                distanceMeters: lateralStep
            )
        } else if lateralStep < -0.02 {
            result = coordinate(
                from: result,
                headingDegrees: normalizedHeading(headingDegrees - 90),
                distanceMeters: -lateralStep
            )
        }
        if along > alongCatchupDeadbandMeters {
            let catchUp = along * (1 - exp(-dt / alongCatchupTauSeconds))
            result = coordinate(from: result, headingDegrees: headingDegrees, distanceMeters: catchUp)
        }
        return result
    }
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
