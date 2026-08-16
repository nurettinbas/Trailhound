import Foundation

/// Night driving split for a single trip.
struct NightDistanceShare: Sendable {
    let nightMeters: Double
    let trackedMeters: Double
}

/// Display names resolved on the main actor so breakdowns can run off it.
struct StatsNameMap: Sendable {
    let names: [String: String]
    let fallback: String

    func name(for key: String) -> String {
        names[key] ?? fallback
    }
}

/// Everything the stats aggregations read from a trip.
///
/// `Trip` and `TripStatsRow` both conform, so the aggregations stay written once while the stats
/// tab can hand a `Sendable` snapshot to a background task.
protocol TripStatsAggregable {
    var startedAt: Date { get }
    var endedAt: Date? { get }
    var distanceMeters: Double { get }
    var duration: TimeInterval? { get }
    var maxSpeedMps: Double? { get }
    var categoryID: String { get }
    var vehicleID: UUID? { get }
    var startPlaceName: String? { get }
    var endPlaceName: String? { get }
    var resolvedFuelCost: Double { get }
    /// Trip-specific VSP/Willans cost. 0 when unknown or not yet computed.
    var resolvedDynamicFuelCost: Double { get }
    /// `nil` when the split is unknown, in which case the trip is left out of the ratio rather
    /// than counted as daytime.
    var nightDistanceShare: NightDistanceShare? { get }
    /// Modal cruise speed (km/h). 0 when unknown or not enough moving time.
    /// Named separately from `Trip.cruiseSpeedKmh` (optional stored field).
    var resolvedCruiseSpeedKmh: Double { get }
    /// Seconds spent in the winning cruise bucket — weight for period cruise.
    var resolvedCruiseDurationSeconds: TimeInterval { get }
    /// Seconds spent below the moving threshold across short gaps.
    var resolvedStopDurationSeconds: TimeInterval { get }
    /// Driving-pace mode (km/h). 0 when unknown.
    var resolvedMostCommonSpeedKmh: Double { get }
    /// How many real trips this value stands for. Always 1 for a `Trip`, but a row rolled up from
    /// `TripDailyRollup` represents a whole day's worth.
    var tripCount: Int { get }
}

extension TripStatsAggregable {
    var tripCount: Int { 1 }
}

/// A trip flattened to plain values so aggregation can leave the main actor.
struct TripStatsRow: TripStatsAggregable, Sendable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double
    let duration: TimeInterval?
    let maxSpeedMps: Double?
    let categoryID: String
    let vehicleID: UUID?
    let startPlaceName: String?
    let endPlaceName: String?
    let resolvedFuelCost: Double
    let resolvedDynamicFuelCost: Double
    let nightDistanceShare: NightDistanceShare?
    let resolvedCruiseSpeedKmh: Double
    let resolvedCruiseDurationSeconds: TimeInterval
    let resolvedStopDurationSeconds: TimeInterval
    let resolvedMostCommonSpeedKmh: Double
    let tripCount: Int
}

extension TripStatsRow {
    /// Call only from the actor that owns `trip` (main actor or a `@ModelActor`). The resulting
    /// value is free to cross actors.
    nonisolated init(trip: Trip) {
        self.init(
            id: trip.id,
            startedAt: trip.startedAt,
            endedAt: trip.endedAt,
            distanceMeters: trip.distanceMeters,
            duration: trip.duration,
            // Vetted rather than derived: statistics span thousands of trips, so loading their
            // points is not an option. An implausible stored value counts as no reading.
            maxSpeedMps: TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps),
            categoryID: trip.categoryID,
            vehicleID: trip.vehicleID,
            startPlaceName: trip.startPlaceName,
            endPlaceName: trip.endPlaceName,
            resolvedFuelCost: StatsViewModel.fuelCost(for: trip),
            resolvedDynamicFuelCost: trip.dynamicFuelCost ?? 0,
            nightDistanceShare: trip.nightDistanceShare,
            resolvedCruiseSpeedKmh: trip.cruiseSpeedKmh ?? 0,
            resolvedCruiseDurationSeconds: trip.cruiseDurationSeconds ?? 0,
            resolvedStopDurationSeconds: trip.stopDurationSeconds ?? 0,
            resolvedMostCommonSpeedKmh: trip.mostCommonSpeedKmh ?? 0,
            tripCount: 1
        )
    }

    /// One day's worth of trips collapsed into a single row, so the same aggregations can run
    /// over pre-summarised data when a period covers too many trips to load individually.
    /// Call only from the actor that owns `rollup`.
    ///
    /// Place names are always `nil`: daily rollups have no place dimension. Callers that filter
    /// by place must fetch individual trips instead.
    nonisolated init(rollup: TripDailyRollup) {
        let weight = rollup.cruiseWeightSeconds
        let mostCommonWeight = rollup.mostCommonWeightSeconds
        self.init(
            id: UUID(),
            startedAt: rollup.dayStart,
            endedAt: rollup.dayStart.addingTimeInterval(max(rollup.duration, 1)),
            distanceMeters: rollup.distanceMeters,
            duration: rollup.duration,
            maxSpeedMps: rollup.maxSpeedMps > 0 ? rollup.maxSpeedMps : nil,
            categoryID: rollup.categoryID,
            vehicleID: UUID(uuidString: rollup.vehicleKey),
            startPlaceName: nil,
            endPlaceName: nil,
            resolvedFuelCost: rollup.estimatedFuelCost,
            resolvedDynamicFuelCost: rollup.dynamicFuelCost,
            nightDistanceShare: NightDistanceShare(
                nightMeters: rollup.nightDistanceMeters,
                trackedMeters: rollup.trackedDistanceMeters
            ),
            resolvedCruiseSpeedKmh: weight > 0 ? rollup.cruiseSpeedProduct / weight : 0,
            resolvedCruiseDurationSeconds: weight,
            resolvedStopDurationSeconds: rollup.stopDurationSeconds,
            resolvedMostCommonSpeedKmh: mostCommonWeight > 0
                ? rollup.mostCommonSpeedProduct / mostCommonWeight
                : 0,
            tripCount: rollup.tripCount
        )
    }
}

extension Trip: TripStatsAggregable {
    var resolvedFuelCost: Double {
        StatsViewModel.fuelCost(for: self)
    }

    var resolvedDynamicFuelCost: Double {
        dynamicFuelCost ?? 0
    }

    var resolvedCruiseSpeedKmh: Double { cruiseSpeedKmh ?? 0 }
    var resolvedCruiseDurationSeconds: TimeInterval { cruiseDurationSeconds ?? 0 }
    var resolvedStopDurationSeconds: TimeInterval { stopDurationSeconds ?? 0 }
    var resolvedMostCommonSpeedKmh: Double { mostCommonSpeedKmh ?? 0 }

    var nightDistanceShare: NightDistanceShare? {
        if let nightDistanceMeters, let trackedDistanceMeters {
            return NightDistanceShare(
                nightMeters: nightDistanceMeters,
                trackedMeters: trackedDistanceMeters
            )
        }
        // Recorded before the derived fields shipped and not yet reached by
        // `TripDerivedBackfillService`, so pay for the walk this once.
        return StatsViewModel.walkNightDistanceShare(for: self)
    }
}
