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
    private static let searchIndexVersionKey = "trailhound.derived.searchIndexVersion"
    /// Bump when search-index contents change (place names, folding) so existing rows are rewritten.
    private static let searchIndexVersion = 1

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

    /// Re-runs place matching + search index after the corpus gained canonical saved-place names
    /// and SearchFolding. Does not rewrite GPS, notes, or other user fields.
    ///
    /// Must persist on this actor's context (not a second main-thread context): another
    /// `ModelContext` can still hold pre-backfill snapshots and a later save would clobber
    /// derived fields. SwiftUI is kept off this thread by `onStoreSave`'s main-thread receive.
    func refreshSearchIndexesIfNeeded(privacyRadius: Double) async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.searchIndexVersionKey) < Self.searchIndexVersion else {
            return
        }

        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
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
                PlaceMatchingService.matchPlaces(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius
                )
                TripDerivedMetrics.refreshSearchIndex(
                    for: trip,
                    places: places,
                    privacyRadius: privacyRadius
                )
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
        defaults.set(Self.searchIndexVersion, forKey: Self.searchIndexVersionKey)
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
        await backfiller.refreshSearchIndexesIfNeeded(privacyRadius: privacyRadius)
    }
}
