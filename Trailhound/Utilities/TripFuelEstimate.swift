import CoreLocation
import Foundation

/// Trip-specific fuel from GPS speed / stop / acceleration (Jiménez VSP + Willans / VT-CPFM).
///
/// Pure and free of SwiftData. Catalog average `C₀` (L/100 or kWh/100) still drives
/// `FuelCostCalculator` avg cost; this scales a reference Willans shape to that `C₀` so a
/// thirstier car burns more on the same trace, including idle.
enum TripFuelEstimate {
    /// Same moving threshold as `TripSpeedProfile`.
    static let movingSpeedKmh: Double = 5
    /// Same merge-seam ceiling as `TripSpeedProfile`.
    static let maximumStopGapSeconds: TimeInterval = 45 * 60
    /// Ignore sub-second GPS jitter when deriving acceleration.
    static let minimumIntervalSeconds: TimeInterval = 0.8
    /// Cap GPS-noise spikes in a = Δv / Δt.
    static let maximumAbsAccelerationMps2: Double = 3.5
    /// Reference catalog rate the base α coefficients were shaped for.
    static let referenceConsumptionPer100: Double = 7.5

    struct Result: Equatable, Sendable {
        /// Catalog volume: km × C₀ / 100 (litres or kWh).
        var avgVolume: Double
        /// VSP / Willans integrated volume (litres or kWh).
        var dynamicVolume: Double
        var avgCost: Double
        var dynamicCost: Double

        static let zero = Result(avgVolume: 0, dynamicVolume: 0, avgCost: 0, dynamicCost: 0)
    }

    /// Jiménez VSP (kW/ton) with grade = 0 — Trailhound stores no altitude.
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
        fuelType: VehicleFuelType
    ) -> Result {
        let kilometers = max(0, distanceMeters) / 1_000
        let c0 = consumptionPer100 > 0 ? consumptionPer100 : referenceConsumptionPer100
        let price = max(0, unitPrice)
        let avgVolume = kilometers * c0 / 100
        let avgCost = avgVolume * price

        guard samples.count >= 2, kilometers > 0 else {
            return Result(avgVolume: avgVolume, dynamicVolume: 0, avgCost: avgCost, dynamicCost: 0)
        }

        let alphas = scaledAlphas(consumptionPer100: c0, fuelType: fuelType)
        var dynamicVolume = 0.0
        var previousSpeedMps: Double?

        for index in 1..<samples.count {
            let previous = samples[index - 1]
            let current = samples[index]
            let dt = current.timestamp.timeIntervalSince(previous.timestamp)
            guard dt > 0 else { continue }

            if dt > maximumStopGapSeconds {
                previousSpeedMps = nil
                continue
            }

            let distance = current.location.distance(from: previous.location)
            let impliedMps = distance / dt
            let impliedKmh = impliedMps * 3.6

            if impliedKmh < movingSpeedKmh {
                dynamicVolume += alphas.idle * dt
                previousSpeedMps = TripSpeedSummary.effectiveSpeedMps(at: index, in: samples)
                continue
            }

            let sampleMps = TripSpeedSummary.effectiveSpeedMps(at: index, in: samples)
            let motionMps = sampleMps.map { min($0, impliedMps) } ?? impliedMps
            let kmh = motionMps * 3.6

            if kmh < movingSpeedKmh {
                dynamicVolume += alphas.idle * dt
                previousSpeedMps = motionMps
                continue
            }

            guard RecordingMovementPolicy.isRecordableSpeed(motionMps) else {
                previousSpeedMps = nil
                continue
            }

            let speedForAccel: Double
            if dt >= minimumIntervalSeconds, let previousSpeedMps {
                speedForAccel = motionMps
                let rawA = (motionMps - previousSpeedMps) / dt
                let a = min(maximumAbsAccelerationMps2, max(-maximumAbsAccelerationMps2, rawA))
                dynamicVolume += fuelRate(vsp: vehicleSpecificPower(speedMps: motionMps, accelerationMps2: a), alphas: alphas, fuelType: fuelType) * dt
            } else {
                // First moving sample after a gap / short interval: treat as steady cruise.
                speedForAccel = motionMps
                dynamicVolume += fuelRate(vsp: vehicleSpecificPower(speedMps: motionMps, accelerationMps2: 0), alphas: alphas, fuelType: fuelType) * dt
            }
            previousSpeedMps = speedForAccel
        }

        dynamicVolume = max(0, dynamicVolume)
        return Result(
            avgVolume: avgVolume,
            dynamicVolume: dynamicVolume,
            avgCost: avgCost,
            dynamicCost: dynamicVolume * price
        )
    }

    static func compute(
        points: [TripPoint],
        distanceMeters: Double,
        consumptionPer100: Double,
        unitPrice: Double,
        fuelType: VehicleFuelType
    ) -> Result {
        compute(
            samples: RouteDisplayPath.samples(from: points),
            distanceMeters: distanceMeters,
            consumptionPer100: consumptionPer100,
            unitPrice: unitPrice,
            fuelType: fuelType
        )
    }

    // MARK: - Willans coefficients

    private struct Alphas {
        /// Idle / coast baseline rate (volume units per second).
        var idle: Double
        var alpha1: Double
        var alpha2: Double
    }

    /// Shape for a generic 7.5 L/100 petrol car, then scaled by C₀ / 7.5 (and fuel-type idle factor).
    private static func scaledAlphas(consumptionPer100: Double, fuelType: VehicleFuelType) -> Alphas {
        let scale = consumptionPer100 / referenceConsumptionPer100
        // ~0.6 L/h idle at reference C₀ for petrol.
        let baseIdlePerSecond = 0.6 / 3_600
        let idleFactor: Double
        switch fuelType {
        case .petrol: idleFactor = 1.0
        case .diesel: idleFactor = 0.75
        case .hybrid: idleFactor = 0.25
        case .electric: idleFactor = 0.05
        }
        return Alphas(
            idle: baseIdlePerSecond * scale * idleFactor,
            alpha1: 0.00012 * scale,
            alpha2: 0.000005 * scale
        )
    }

    private static func fuelRate(vsp: Double, alphas: Alphas, fuelType: VehicleFuelType) -> Double {
        if vsp >= 0 {
            return alphas.idle + alphas.alpha1 * vsp + alphas.alpha2 * vsp * vsp
        }
        // Negative power: ICE coasts at idle; EV / hybrid reclaim a fraction.
        switch fuelType {
        case .electric:
            return max(0, alphas.idle + 0.35 * alphas.alpha1 * vsp)
        case .hybrid:
            return max(0, alphas.idle + 0.20 * alphas.alpha1 * vsp)
        case .petrol, .diesel:
            return alphas.idle
        }
    }
}
