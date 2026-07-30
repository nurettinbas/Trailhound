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
    var resolvedFuelCost: Double { get }
    /// `nil` when the split is unknown, in which case the trip is left out of the ratio rather
    /// than counted as daytime.
    var nightDistanceShare: NightDistanceShare? { get }
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
    let resolvedFuelCost: Double
    let nightDistanceShare: NightDistanceShare?
    let tripCount: Int
}

extension TripStatsRow {
    /// Must run where the model is safe to touch; the resulting value is free to cross actors.
    @MainActor
    init(trip: Trip) {
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
            resolvedFuelCost: StatsViewModel.fuelCost(for: trip),
            nightDistanceShare: trip.nightDistanceShare,
            tripCount: 1
        )
    }

    /// One day's worth of trips collapsed into a single row, so the same aggregations can run
    /// over pre-summarised data when a period covers too many trips to load individually.
    @MainActor
    init(rollup: TripDailyRollup) {
        self.init(
            id: UUID(),
            startedAt: rollup.dayStart,
            endedAt: rollup.dayStart.addingTimeInterval(max(rollup.duration, 1)),
            distanceMeters: rollup.distanceMeters,
            duration: rollup.duration,
            maxSpeedMps: rollup.maxSpeedMps > 0 ? rollup.maxSpeedMps : nil,
            categoryID: rollup.categoryID,
            vehicleID: UUID(uuidString: rollup.vehicleKey),
            resolvedFuelCost: rollup.estimatedFuelCost,
            nightDistanceShare: NightDistanceShare(
                nightMeters: rollup.nightDistanceMeters,
                trackedMeters: rollup.trackedDistanceMeters
            ),
            tripCount: rollup.tripCount
        )
    }
}

extension Trip: TripStatsAggregable {
    var resolvedFuelCost: Double {
        StatsViewModel.fuelCost(for: self)
    }

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
