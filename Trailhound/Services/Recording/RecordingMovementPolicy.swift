import CoreLocation
import Foundation

enum RecordingMovementPolicy {
    enum Decision: Equatable {
        /// Jitter / stationary — ignore completely.
        case ignore
        /// Plausible movement — add distance and optionally a point.
        case accumulate
        /// Impossible GPS jump — advance anchor and record a point, but do not add distance.
        case gapResume
    }

    static let minimumDistanceSampleMeters: CLLocationDistance = 2
    static let stationarySpeedMps: Double = 0.5
    static let stationaryDistanceMeters: CLLocationDistance = 5
    static let maximumPlausibleSpeedMps: Double = 70
    /// Do not draw a map chord longer than this (sparse GPS may still count distance).
    static let mapMaxChordMeters: CLLocationDistance = 450

    static func decision(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        speed: Double
    ) -> Decision {
        decision(delta: delta, timeDelta: timeDelta, locationSpeedMps: speed)
    }

    static func decision(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        locationSpeedMps: Double
    ) -> Decision {
        guard delta >= minimumDistanceSampleMeters else { return .ignore }

        let safeTimeDelta = max(0.01, timeDelta)
        let impliedSpeedMps = delta / safeTimeDelta
        let movementSpeedMps = locationSpeedMps > 0 ? locationSpeedMps : impliedSpeedMps

        if movementSpeedMps < stationarySpeedMps, delta < stationaryDistanceMeters {
            return .ignore
        }

        if impliedSpeedMps > maximumPlausibleSpeedMps {
            return .gapResume
        }
        return .accumulate
    }

    static func isPlausibleRecordedSpeed(_ speedMps: Double) -> Bool {
        speedMps > 0 && speedMps <= maximumPlausibleSpeedMps
    }

    /// Prefer GPS speed; fall back to distance / time when Core Location reports invalid speed (-1).
    static func effectiveSpeedMps(
        locationSpeedMps: Double,
        delta: CLLocationDistance,
        timeDelta: TimeInterval
    ) -> Double? {
        if isPlausibleRecordedSpeed(locationSpeedMps) {
            return locationSpeedMps
        }
        let safeTime = max(0.01, timeDelta)
        let implied = delta / safeTime
        if isPlausibleRecordedSpeed(implied) {
            return implied
        }
        return nil
    }

    /// Whether map should connect two stored points (distance may still accumulate for longer sparse gaps).
    static func shouldDrawMapSegment(
        delta: CLLocationDistance,
        timeDelta: TimeInterval,
        speed: Double
    ) -> Bool {
        guard decision(delta: delta, timeDelta: timeDelta, speed: speed) == .accumulate else {
            return false
        }
        return delta <= mapMaxChordMeters
    }
}
