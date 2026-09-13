import Foundation

struct FuelSpeedKnot: Sendable {
    let kmh: Double
    let factor: Double
}

/// Fleet-average relative L/100 (or kWh/100) vs speed, plus idle / regen behaviour.
///
/// Petrol knots follow Oak Ridge / DOE fuel-economy-by-speed (50–80 mph) below the
/// documented range, with a physics-style `v²` rise above 129 km/h marked as extrapolation.
/// The mixed-cycle `referenceMean` is an **assumption**: EPA-like 55 % urban / 45 % highway
/// distance so a user's single `C₀` has something to be relative to. It is not that vehicle's
/// true city/highway split.
struct PowertrainFuelProfile: Sendable {
    enum Kind: Sendable {
        case petrol
        case diesel
        case hybrid
        case electric
    }

    let idleEquivalentKmPerSecond: Double
    let coastFraction: Double
    let regenGain: Double
    let accelGain: Double
    let referenceMean: Double
    let kind: Kind

    func shape(_ kmh: Double) -> Double {
        switch kind {
        case .electric:
            return Self.electricShape(kmh)
        case .petrol:
            return Self.interpolate(Self.petrolKnots(), kmh: kmh)
        case .diesel:
            return Self.interpolate(Self.dieselKnots(), kmh: kmh)
        case .hybrid:
            return Self.interpolate(Self.hybridKnots(), kmh: kmh)
        }
    }

    func accelFraction(accelerationMps2: Double) -> Double {
        min(0.60, max(0, accelerationMps2) * accelGain)
    }

    func regenFraction(accelerationMps2: Double) -> Double {
        min(0.50, max(0, -accelerationMps2) * regenGain)
    }

    static func profile(for fuelType: VehicleFuelType) -> PowertrainFuelProfile {
        switch fuelType {
        case .petrol:
            let idle = petrolIdleKmPerSecond
            return PowertrainFuelProfile(
                idleEquivalentKmPerSecond: idle,
                coastFraction: 0.90,
                regenGain: 0,
                accelGain: 0.12,
                referenceMean: mixedReference(kind: .petrol, idleKmPerSecond: idle, idleSecondsPer100Km: 12 * 60),
                kind: .petrol
            )
        case .diesel:
            let idle = petrolIdleKmPerSecond * 0.75
            return PowertrainFuelProfile(
                idleEquivalentKmPerSecond: idle,
                coastFraction: 0.85,
                regenGain: 0,
                accelGain: 0.10,
                referenceMean: mixedReference(kind: .diesel, idleKmPerSecond: idle, idleSecondsPer100Km: 12 * 60),
                kind: .diesel
            )
        case .hybrid:
            let idle = petrolIdleKmPerSecond * 0.08
            return PowertrainFuelProfile(
                idleEquivalentKmPerSecond: idle,
                coastFraction: 0.20,
                regenGain: 0.18,
                accelGain: 0.08,
                referenceMean: mixedReference(kind: .hybrid, idleKmPerSecond: idle, idleSecondsPer100Km: 4 * 60),
                kind: .hybrid
            )
        case .electric:
            return PowertrainFuelProfile(
                idleEquivalentKmPerSecond: 0,
                coastFraction: 0.12,
                regenGain: 0.22,
                accelGain: 0.08,
                referenceMean: mixedReference(kind: .electric, idleKmPerSecond: 0, idleSecondsPer100Km: 0),
                kind: .electric
            )
        }
    }

    /// 0.6 L/h idle at the 7.5 L/100 reference, expressed as km-equivalent so volume still
    /// scales with `C₀` via `km × C₀ / 100`.
    private static var petrolIdleKmPerSecond: Double { 0.6 / 7.5 * 100 / 3_600 }

    /// Relative L/100 vs 80.5 km/h = 1.0. 50–80 mph from DOE/ORNL 74-vehicle study;
    /// 140 km/h is an extrapolation (study stopped at 80 mph / 129 km/h).
    private static func petrolKnots() -> [FuelSpeedKnot] {
        [
            FuelSpeedKnot(kmh: 0, factor: 2.40),
            FuelSpeedKnot(kmh: 20, factor: 1.45),
            FuelSpeedKnot(kmh: 32, factor: 1.22),
            FuelSpeedKnot(kmh: 48, factor: 1.10),
            FuelSpeedKnot(kmh: 64, factor: 1.03),
            FuelSpeedKnot(kmh: 80.5, factor: 1.00),
            FuelSpeedKnot(kmh: 96.6, factor: 1.142),
            FuelSpeedKnot(kmh: 112.7, factor: 1.328),
            FuelSpeedKnot(kmh: 128.7, factor: 1.570),
            FuelSpeedKnot(kmh: 140, factor: 1.74),
            FuelSpeedKnot(kmh: 160, factor: 2.05),
            FuelSpeedKnot(kmh: 180, factor: 2.40),
        ]
    }

    /// Diesel keeps the aero rise; low-speed penalty is milder (Argonne Autonomie midsize diesel).
    private static func dieselKnots() -> [FuelSpeedKnot] {
        petrolKnots().map { knot in
            if knot.kmh >= 80.5 { return knot }
            return FuelSpeedKnot(kmh: knot.kmh, factor: 1 + (knot.factor - 1) * 0.85)
        }
    }

    /// Hybrids lose less in the city and more evenly as highway speed rises (Argonne Autonomie HEV).
    private static func hybridKnots() -> [FuelSpeedKnot] {
        petrolKnots().map { knot in
            if knot.kmh < 80.5 {
                return FuelSpeedKnot(kmh: knot.kmh, factor: 1 + (knot.factor - 1) * 0.45)
            }
            return FuelSpeedKnot(kmh: knot.kmh, factor: 1 + (knot.factor - 1) * 0.90)
        }
    }

    private static func electricShape(_ kmh: Double) -> Double {
        let v = max(0, kmh)
        return 0.45 + 0.55 * pow(v / 80.5, 2)
    }

    /// Assumed mix that a single combined `C₀` represents: 55 km urban @ 40 km/h + 45 km
    /// highway @ 96 km/h, plus a small idle allowance for combustion engines.
    private static func mixedReference(
        kind: Kind,
        idleKmPerSecond: Double,
        idleSecondsPer100Km: TimeInterval
    ) -> Double {
        let urban: Double
        let highway: Double
        switch kind {
        case .electric:
            urban = electricShape(40)
            highway = electricShape(96.6)
        case .petrol:
            urban = interpolate(petrolKnots(), kmh: 40)
            highway = interpolate(petrolKnots(), kmh: 96.6)
        case .diesel:
            urban = interpolate(dieselKnots(), kmh: 40)
            highway = interpolate(dieselKnots(), kmh: 96.6)
        case .hybrid:
            urban = interpolate(hybridKnots(), kmh: 40)
            highway = interpolate(hybridKnots(), kmh: 96.6)
        }
        let idle = idleKmPerSecond * idleSecondsPer100Km / 100
        return 0.55 * urban + 0.45 * highway + idle
    }

    private static func interpolate(_ knots: [FuelSpeedKnot], kmh: Double) -> Double {
        let v = max(0, kmh)
        if v <= knots[0].kmh { return knots[0].factor }
        if v >= knots[knots.count - 1].kmh { return knots[knots.count - 1].factor }
        for index in 1..<knots.count {
            let left = knots[index - 1]
            let right = knots[index]
            if v <= right.kmh {
                let t = (v - left.kmh) / (right.kmh - left.kmh)
                return left.factor + t * (right.factor - left.factor)
            }
        }
        return knots[knots.count - 1].factor
    }
}
