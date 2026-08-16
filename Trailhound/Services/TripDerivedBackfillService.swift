import Foundation
import SwiftData

/// Fills in `TripDerivedMetrics` values for trips recorded before those fields existed.
///
/// Runs on its own `@ModelActor`, off the main thread, so walking the GPS points of a large
/// library cannot stall the UI. Work is committed in small batches, which makes it safe to
/// interrupt: the next launch resumes where this one stopped. Existing trip data is only
/// augmented — nothing is deleted or rewritten.
@ModelActor
actor TripDerivedBackfiller {
    private static let batchSize = 25
    private static let speedProfileVersionKey = "trailhound.derived.speedProfileVersion"
    /// Bump when `TripSpeedProfile` changes so already-filled trips are recomputed.
    private static let speedProfileVersion = 6
    private static let dynamicFuelVersionKey = "trailhound.derived.dynamicFuelVersion"
    /// Bump when `TripFuelEstimate` changes so already-filled trips are recomputed.
    private static let dynamicFuelVersion = 1

    func run(privacyRadius: Double) async {
        // Fetched on this actor's own context: `SavedPlace` cannot cross actor boundaries.
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let fuelTypes = vehicleFuelTypesByID()

        while !Task.isCancelled {
            let pending = fetchPendingBatch()
            guard !pending.isEmpty else { break }

            for trip in pending {
                let fuelType = trip.vehicleID.flatMap { fuelTypes[$0] } ?? .petrol
                TripDerivedMetrics.recompute(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius,
                    fuelType: fuelType
                )
                // The derived values are what read paths need from here on; holding every
                // TripPoint alive would defeat the point of backfilling in batches.
                trip.invalidatePointCaches()
            }

            do {
                try modelContext.save()
            } catch {
                return
            }

            await Task.yield()
        }
    }

    /// Re-runs only the cruise / stop derivation after a formula change. Interruptible: the
    /// version key is written only when every completed trip has been visited.
    func refreshSpeedProfilesIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.speedProfileVersionKey) < Self.speedProfileVersion else {
            return
        }

        var offset = 0
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
                TripDerivedMetrics.recomputeSpeedProfile(for: trip)
                trip.invalidatePointCaches()
            }

            do {
                try modelContext.save()
            } catch {
                return
            }

            offset += batch.count
            await Task.yield()
        }

        guard !Task.isCancelled else { return }
        defaults.set(Self.speedProfileVersion, forKey: Self.speedProfileVersionKey)
    }

    /// Re-runs VSP/Willans fuel after a formula change. Does not rewrite `estimatedFuelCost`.
    func refreshDynamicFuelIfNeeded() async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.dynamicFuelVersionKey) < Self.dynamicFuelVersion else {
            return
        }

        let fuelTypes = vehicleFuelTypesByID()
        var offset = 0
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
                let fuelType = trip.vehicleID.flatMap { fuelTypes[$0] } ?? .petrol
                TripDerivedMetrics.recomputeFuel(for: trip, fuelType: fuelType)
                trip.invalidatePointCaches()
            }

            do {
                try modelContext.save()
            } catch {
                return
            }

            offset += batch.count
            await Task.yield()
        }

        guard !Task.isCancelled else { return }
        defaults.set(Self.dynamicFuelVersion, forKey: Self.dynamicFuelVersionKey)
    }

    /// Completed trips are the only ones read paths aggregate, and an unfinished trip would be
    /// recomputed again the moment it is finalized.
    private func fetchPendingBatch() -> [Trip] {
        // Separate predicates: a single OR over optionals can overwhelm the type checker.
        var pendingByID: [UUID: Trip] = [:]
        for trip in fetchBatch(
            predicate: #Predicate { $0.endedAt != nil && $0.stopDurationSeconds == nil }
        ) {
            pendingByID[trip.id] = trip
        }
        for trip in fetchBatch(
            predicate: #Predicate { $0.endedAt != nil && $0.nightDistanceMeters == nil }
        ) {
            pendingByID[trip.id] = trip
        }
        for trip in fetchBatch(
            predicate: #Predicate { $0.endedAt != nil && $0.dynamicFuelCost == nil }
        ) {
            pendingByID[trip.id] = trip
        }
        return Array(pendingByID.values)
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(Self.batchSize)
            .map { $0 }
    }

    private func fetchBatch(predicate: Predicate<Trip>) -> [Trip] {
        var descriptor = FetchDescriptor<Trip>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.batchSize
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func vehicleFuelTypesByID() -> [UUID: VehicleFuelType] {
        let vehicles = (try? modelContext.fetch(FetchDescriptor<VehicleProfile>())) ?? []
        var map: [UUID: VehicleFuelType] = [:]
        for vehicle in vehicles {
            map[vehicle.id] = vehicle.fuelType
        }
        return map
    }
}

@MainActor
enum TripDerivedBackfillService {
    private static var isRunning = false

    static func backfillIfNeeded(container: ModelContainer) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        let privacyRadius = AppSettings.shared.privacyRadiusMeters
        let backfiller = TripDerivedBackfiller(modelContainer: container)
        await backfiller.run(privacyRadius: privacyRadius)
        // After formula fixes, rewrite cruise / stop before rollups rebuild.
        await backfiller.refreshSpeedProfilesIfNeeded()
        await backfiller.refreshDynamicFuelIfNeeded()
    }
}
