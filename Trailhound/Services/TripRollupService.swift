import Foundation
import SwiftData

/// Nonisolated rollup deltas so `@ModelActor` workers can maintain daily totals off the main thread.
enum TripRollupDelta {
    static func add(_ trip: Trip, in context: ModelContext) {
        applyDelta(for: trip, sign: 1, in: context)
    }

    static func remove(_ trip: Trip, in context: ModelContext) {
        applyDelta(for: trip, sign: -1, in: context)
    }

    static func update(_ trip: Trip, from previous: TripRollupEntry?, in context: ModelContext) {
        if let previous {
            applyDelta(key: previous.key, contribution: previous.contribution, sign: -1, in: context)
        }
        applyDelta(for: trip, sign: 1, in: context)
    }

    private static func applyDelta(for trip: Trip, sign: Double, in context: ModelContext) {
        guard trip.endedAt != nil else { return }
        applyDelta(
            key: TripRollupKey(trip: trip),
            contribution: Contribution(trip: trip),
            sign: sign,
            in: context
        )
    }

    private static func applyDelta(
        key: TripRollupKey,
        contribution: Contribution,
        sign: Double,
        in context: ModelContext
    ) {
        guard let rollup = existingRollup(for: key, in: context) ?? makeRollup(for: key, sign: sign, in: context)
        else { return }

        rollup.distanceMeters = max(0, rollup.distanceMeters + sign * contribution.distanceMeters)
        rollup.duration = max(0, rollup.duration + sign * contribution.duration)
        rollup.nightDistanceMeters = max(0, rollup.nightDistanceMeters + sign * contribution.nightMeters)
        rollup.trackedDistanceMeters = max(0, rollup.trackedDistanceMeters + sign * contribution.trackedMeters)
        rollup.estimatedFuelCost = max(0, rollup.estimatedFuelCost + sign * contribution.fuelCost)
        rollup.tripCount = max(0, rollup.tripCount + Int(sign))

        if sign > 0 {
            rollup.maxSpeedMps = max(rollup.maxSpeedMps, contribution.maxSpeedMps)
        }

        // A day with nothing left in it would otherwise keep a zeroed row forever, and a stale
        // `maxSpeedMps` that removals cannot lower.
        if rollup.tripCount == 0 {
            context.delete(rollup)
        }
    }

    private static func existingRollup(for key: TripRollupKey, in context: ModelContext) -> TripDailyRollup? {
        let dayStart = key.dayStart
        let categoryID = key.categoryID
        let vehicleKey = key.vehicleKey
        var descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart == dayStart
                    && rollup.categoryID == categoryID
                    && rollup.vehicleKey == vehicleKey
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func makeRollup(
        for key: TripRollupKey,
        sign: Double,
        in context: ModelContext
    ) -> TripDailyRollup? {
        // Nothing to subtract from: the delta was already accounted for, or never applied.
        guard sign > 0 else { return nil }
        let rollup = TripDailyRollup(
            dayStart: key.dayStart,
            categoryID: key.categoryID,
            vehicleKey: key.vehicleKey
        )
        context.insert(rollup)
        return rollup
    }
}

/// Keeps `TripDailyRollup` in step with the trips it summarises.
///
/// Rollups are maintained as deltas at the same write sites that compute derived metrics, so a
/// finished, edited, merged or deleted trip adjusts its day's totals rather than triggering a
/// rescan. Because deltas can drift if a write is ever missed, `rebuildAll` can regenerate the
/// whole table from `Trip`, which remains the only source of truth.
@MainActor
enum TripRollupService {
    // MARK: - Delta maintenance

    static func add(_ trip: Trip, in context: ModelContext) {
        TripRollupDelta.add(trip, in: context)
    }

    static func remove(_ trip: Trip, in context: ModelContext) {
        TripRollupDelta.remove(trip, in: context)
    }

    /// Everything a trip contributed before an edit, so the edit can be applied as a delta.
    static func snapshot(of trip: Trip) -> TripRollupEntry? {
        guard trip.endedAt != nil else { return nil }
        return TripRollupEntry(key: TripRollupKey(trip: trip), contribution: Contribution(trip: trip))
    }

    /// Re-points a trip's contribution after an edit that may have moved it to another day,
    /// category or vehicle, or changed its distance.
    static func update(_ trip: Trip, from previous: TripRollupEntry?, in context: ModelContext) {
        TripRollupDelta.update(trip, from: previous, in: context)
    }

    // MARK: - Rebuild

    private static let rebuildVersionKey = "trailhound.rollup.rebuiltVersion"
    /// Bump to force every install to regenerate the table after a change to how it is derived.
    /// Version 2 drops the phantom maxima that existing rows recorded before speeds were vetted.
    private static let rebuildVersion = 2

    /// Builds the table on the first launch that has it, and after any change to how rollups are
    /// derived. Cheap no-op afterwards.
    static func rebuildIfNeeded(container: ModelContainer) async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: rebuildVersionKey) < rebuildVersion else { return }
        await rebuildAll(container: container)
        defaults.set(rebuildVersion, forKey: rebuildVersionKey)
    }

    /// Regenerates the whole table from `Trip`. Used on first run after the rollup shipped, and
    /// available from Settings when the numbers look wrong.
    static func rebuildAll(container: ModelContainer) async {
        await TripRollupRebuilder(modelContainer: container).run()
    }

    // MARK: - Reads

    /// Aggregates a period in time proportional to the number of days it covers.
    static func stats(
        in interval: DateInterval,
        categoryID: String?,
        vehicleID: UUID?,
        in context: ModelContext
    ) -> TripStats {
        let lowerBound = interval.start
        let upperBound = interval.end
        let descriptor = FetchDescriptor<TripDailyRollup>(
            predicate: #Predicate { rollup in
                rollup.dayStart >= lowerBound && rollup.dayStart <= upperBound
            }
        )
        let rollups = ((try? context.fetch(descriptor)) ?? []).filter { rollup in
            if let categoryID, rollup.categoryID != categoryID { return false }
            if let vehicleID, rollup.vehicleKey != vehicleID.uuidString { return false }
            return true
        }

        var totalDistance = 0.0
        var totalDuration = 0.0
        var totalFuel = 0.0
        var nightMeters = 0.0
        var trackedMeters = 0.0
        var maxSpeedMps = 0.0
        var count = 0

        for rollup in rollups {
            totalDistance += rollup.distanceMeters
            totalDuration += rollup.duration
            totalFuel += rollup.estimatedFuelCost
            nightMeters += rollup.nightDistanceMeters
            trackedMeters += rollup.trackedDistanceMeters
            maxSpeedMps = max(maxSpeedMps, rollup.maxSpeedMps)
            count += rollup.tripCount
        }

        return TripStats(
            tripCount: count,
            totalDistanceMeters: totalDistance,
            totalDuration: totalDuration,
            averageDuration: count > 0 ? totalDuration / Double(count) : 0,
            averageSpeedKmh: StatsViewModel.averageSpeedKmh(
                distanceMeters: totalDistance,
                duration: totalDuration
            ),
            maxSpeedKmh: maxSpeedMps * 3.6,
            estimatedFuelCost: totalFuel,
            nightDrivingRatio: trackedMeters > 0 ? nightMeters / trackedMeters : 0
        )
    }
}

/// Rebuilds the whole rollup table off the main thread, since it has to visit every trip.
@ModelActor
actor TripRollupRebuilder {
    private static let batchSize = 200

    func run() async {
        for existing in (try? modelContext.fetch(FetchDescriptor<TripDailyRollup>())) ?? [] {
            modelContext.delete(existing)
        }

        var offset = 0
        var accumulator: [TripRollupKey: Contribution] = [:]

        while !Task.isCancelled {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { $0.endedAt != nil },
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize

            let batch = (try? modelContext.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }

            for trip in batch {
                    accumulator[TripRollupKey(trip: trip), default: .zero].merge(Contribution(trip: trip))
                trip.invalidatePointCaches()
            }

            offset += batch.count
            await Task.yield()
            
            
        }

        for (key, contribution) in accumulator {
            let rollup = TripDailyRollup(
                dayStart: key.dayStart,
                categoryID: key.categoryID,
                vehicleKey: key.vehicleKey
            )
            rollup.distanceMeters = contribution.distanceMeters
            rollup.duration = contribution.duration
            rollup.nightDistanceMeters = contribution.nightMeters
            rollup.trackedDistanceMeters = contribution.trackedMeters
            rollup.estimatedFuelCost = contribution.fuelCost
            rollup.tripCount = contribution.tripCount
            rollup.maxSpeedMps = contribution.maxSpeedMps
            modelContext.insert(rollup)
        }

        try? modelContext.save()
    }
}

/// Identifies the rollup bucket a trip belongs to.
struct TripRollupKey: Hashable {
    let dayStart: Date
    let categoryID: String
    let vehicleKey: String

    init(trip: Trip) {
        self.dayStart = Calendar.current.startOfDay(for: trip.startedAt)
        self.categoryID = trip.categoryID
        self.vehicleKey = TripDailyRollup.vehicleKey(for: trip.vehicleID)
    }
}

/// A trip's rollup bucket together with the amounts it put in it.
struct TripRollupEntry {
    fileprivate let key: TripRollupKey
    fileprivate let contribution: Contribution
}

fileprivate struct Contribution {
    var distanceMeters = 0.0
    var duration = 0.0
    var nightMeters = 0.0
    var trackedMeters = 0.0
    var fuelCost = 0.0
    var maxSpeedMps = 0.0
    var tripCount = 0

    static let zero = Contribution()

    init(trip: Trip) {
        distanceMeters = trip.distanceMeters
        duration = trip.duration ?? 0
        nightMeters = trip.nightDistanceMeters ?? 0
        trackedMeters = trip.trackedDistanceMeters ?? 0
        fuelCost = StatsViewModel.fuelCost(for: trip)
        // A rollup keeps the highest value it ever saw and never lowers it, so one phantom
        // maximum would poison a whole day's statistics permanently.
        maxSpeedMps = TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps) ?? 0
        tripCount = 1
    }

    init() {}

    mutating func merge(_ other: Contribution) {
        distanceMeters += other.distanceMeters
        duration += other.duration
        nightMeters += other.nightMeters
        trackedMeters += other.trackedMeters
        fuelCost += other.fuelCost
        maxSpeedMps = max(maxSpeedMps, other.maxSpeedMps)
        tripCount += other.tripCount
    }
}
