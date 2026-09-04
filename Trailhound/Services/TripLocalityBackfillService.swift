import Foundation
import SwiftData

/// Conservative locality fill for pre-V19 trips: privacy zones stay blank; saved-place
/// names are never treated as cities. Future reverse-geocode writes `CLPlacemark.locality`.
@ModelActor
actor TripLocalityBackfiller {
    private static let batchSize = 50
    private static let versionKey = "trailhound.derived.localityBackfillVersion"
    private static let version = 1

    func run(privacyRadius: Double) async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: Self.versionKey) < Self.version else { return }

        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        var offset = 0
        while !Task.isCancelled {
            var descriptor = FetchDescriptor<Trip>(
                predicate: #Predicate { trip in
                    trip.endedAt != nil && trip.startLocality == nil && trip.endLocality == nil
                },
                sortBy: [SortDescriptor(\.startedAt, order: .forward)]
            )
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = Self.batchSize
            let batch = (try? modelContext.fetch(descriptor)) ?? []
            guard !batch.isEmpty else { break }

            for trip in batch {
                TripLocalityResolver.apply(
                    to: trip,
                    startLocality: nil,
                    startCountryCode: nil,
                    endLocality: nil,
                    endCountryCode: nil,
                    places: places,
                    privacyRadius: privacyRadius
                )
                trip.invalidatePointCaches()
            }
            try? modelContext.save()
            offset += batch.count
            await Task.yield()
        }

        defaults.set(Self.version, forKey: Self.versionKey)
    }
}

enum TripLocalityBackfillService {
    static func backfillIfNeeded(container: ModelContainer, privacyRadius: Double) async {
        await TripLocalityBackfiller(modelContainer: container).run(privacyRadius: privacyRadius)
    }
}
