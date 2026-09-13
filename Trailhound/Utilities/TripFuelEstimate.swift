import CoreLocation
import Foundation

/// Trip-specific fuel from GPS speed, stop-go, and acceleration, scaled to the vehicle's `C₀`.
///
/// Trailhound does not have mass, drag, grade, engine-on state, or city/highway ratings, so this
/// is not a vehicle-specific VT-CPFM or MOVES inventory. The only vehicle-specific magnitude is
/// catalog `C₀` (L/100 km or kWh/100 km). GPS contributes a dimensionless trip factor from
/// fleet-average road-load / VSP operating modes. Unusable traces fall back to `C₀ × km / 100`.
enum TripFuelEstimate {
    static let movingSpeedKmh: Double = TripMotionThresholds.movingSpeedKmh
    static let maximumStopGapSeconds: TimeInterval = TripMotionThresholds.maximumStopGapSeconds
    static let minimumIntervalSeconds: TimeInterval = TripMotionThresholds.minimumAccelIntervalSeconds
    static let maximumAbsAccelerationMps2: Double = TripMotionThresholds.maximumAbsAccelerationMps2
    static let referenceConsumptionPer100: Double = 7.5

    /// Documented envelope so sparse GPS cannot invent multiples of `C₀`.
    static let minimumTripFactor: Double = 0.45
    static let maximumTripFactor: Double = 2.20

    struct Result: Equatable, Sendable {
        /// Catalog volume: km × C₀ / 100 (litres or kWh).
        var avgVolume: Double
        /// GPS-adjusted volume (litres or kWh). Equals `avgVolume` when the trace is unusable.
        var dynamicVolume: Double
        var avgCost: Double
        var dynamicCost: Double
        /// 0…1 support for the GPS adjustment. 0 means the result is the catalog baseline.
        var confidence: Double

        static let zero = Result(
            avgVolume: 0,
            dynamicVolume: 0,
            avgCost: 0,
            dynamicCost: 0,
            confidence: 0
        )
    }

    /// Jiménez VSP (kW/ton) with grade = 0 — Trailhound stores no altitude.
    /// Used as an operating-mode classifier (cruise / accel / coast), not as a litre rate.
    static func vehicleSpecificPower(speedMps: Double, accelerationMps2: Double) -> Double {
        let v = max(0, speedMps)
        let a = accelerationMps2
        return v * (1.1 * a + 0.132) + 0.000302 * v * v * v
    }

    static func compute(
        samples: [RouteSample],
        distanceMeters: Double,
        consumptionPer100: Double,
        unitPrice: Double,
        fuelType: VehicleFuelType,
        excludedStops: [TripFuelMotionTimeline.ExcludedStop] = []
    ) -> Result {
        let kilometers = max(0, distanceMeters) / 1_000
        let c0 = consumptionPer100 > 0 ? consumptionPer100 : referenceConsumptionPer100
        let price = max(0, unitPrice)
        let avgVolume = kilometers * c0 / 100
        let avgCost = avgVolume * price

        guard kilometers > 0 else {
            return Result(avgVolume: 0, dynamicVolume: 0, avgCost: 0, dynamicCost: 0, confidence: 0)
        }

        let timeline = TripFuelMotionTimeline.build(
            samples: samples,
            storedDistanceMeters: distanceMeters,
            excludedStops: excludedStops
        )
        guard samples.count >= 2, timeline.confidence > 0, timeline.observedMovingMeters > 1 else {
            return Result(
                avgVolume: avgVolume,
                dynamicVolume: avgVolume,
                avgCost: avgCost,
                dynamicCost: avgCost,
                confidence: 0
            )
        }

        let rawFactor = tripFactor(timeline: timeline, fuelType: fuelType)
        let clamped = min(maximumTripFactor, max(minimumTripFactor, rawFactor))
        let blended = 1 + (clamped - 1) * timeline.confidence
        let dynamicVolume = max(0, avgVolume * blended)
        return Result(
            avgVolume: avgVolume,
            dynamicVolume: dynamicVolume,
            avgCost: avgCost,
            dynamicCost: dynamicVolume * price,
            confidence: timeline.confidence
        )
    }

    static func compute(
        points: [TripPoint],
        distanceMeters: Double,
        consumptionPer100: Double,
        unitPrice: Double,
        fuelType: VehicleFuelType,
        excludedStops: [TripFuelMotionTimeline.ExcludedStop] = []
    ) -> Result {
        compute(
            samples: RouteDisplayPath.samples(from: points),
            distanceMeters: distanceMeters,
            consumptionPer100: consumptionPer100,
            unitPrice: unitPrice,
            fuelType: fuelType,
            excludedStops: excludedStops
        )
    }

    // MARK: - Relative factor

    /// Dimensionless intensity of this trace relative to the documented mixed-cycle reference.
    private static func tripFactor(
        timeline: TripFuelMotionTimeline.Result,
        fuelType: VehicleFuelType
    ) -> Double {
        let profile = PowertrainFuelProfile.profile(for: fuelType)
        var relativeKm = 0.0
        var tractionReserve = 0.0

        var stopRunDuration: TimeInterval = 0
        func flushStopRun() {
            guard stopRunDuration > 0 else { return }
            relativeKm += profile.idleEquivalentKmPerSecond
                * TripFuelMotionTimeline.idleCreditSeconds(forRunDuration: stopRunDuration)
            stopRunDuration = 0
        }

        for interval in timeline.intervals {
            switch interval.kind {
            case .unobserved, .teleport:
                flushStopRun()
                continue
            case .observedStop:
                stopRunDuration += interval.dt * interval.evidenceWeight
            case .moving:
                flushStopRun()
                let km = interval.distanceMeters / 1_000
                guard km > 0 else { continue }
                let kmh = interval.speedMps * 3.6
                let cruise = km * profile.shape(kmh)
                let vsp = vehicleSpecificPower(
                    speedMps: interval.speedMps,
                    accelerationMps2: interval.accelerationMps2
                )
                if vsp < 0 || interval.accelerationMps2 < -0.15 {
                    let recovered = min(
                        tractionReserve,
                        cruise * profile.regenFraction(accelerationMps2: interval.accelerationMps2)
                    )
                    tractionReserve -= recovered
                    relativeKm += cruise * profile.coastFraction - recovered
                } else {
                    let extra = cruise * profile.accelFraction(accelerationMps2: interval.accelerationMps2)
                    tractionReserve += extra
                    relativeKm += cruise + extra
                }
            }
        }
        flushStopRun()

        let movingKm = timeline.observedMovingMeters / 1_000
        guard movingKm > 0 else { return 1 }
        let tripMean = relativeKm / movingKm
        return tripMean / profile.referenceMean
    }
}
