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

    func run(privacyRadius: Double) async {
        // Fetched on this actor's own context: `SavedPlace` cannot cross actor boundaries.
        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []

        while !Task.isCancelled {
            let pending = fetchPendingBatch()
            guard !pending.isEmpty else { break }

            for trip in pending {
                TripDerivedMetrics.recompute(for: trip, places: places, privacyRadius: privacyRadius)
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

    /// Completed trips are the only ones read paths aggregate, and an unfinished trip would be
    /// recomputed again the moment it is finalized.
    private func fetchPendingBatch() -> [Trip] {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.nightDistanceMeters == nil && $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.batchSize
        return (try? modelContext.fetch(descriptor)) ?? []
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
        await TripDerivedBackfiller(modelContainer: container).run(privacyRadius: privacyRadius)
    }
}
