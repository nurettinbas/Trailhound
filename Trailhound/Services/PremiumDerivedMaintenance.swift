import Foundation
import SwiftData

struct PremiumTripSnapshot: Equatable, Sendable {
    let route: FrequentRouteSnapshot?
    let localities: [String]
    let isCompleted: Bool
}

enum PremiumDerivedDelta {
    static func snapshot(
        of trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> PremiumTripSnapshot {
        PremiumTripSnapshot(
            route: FrequentRouteAggregateService.snapshot(
                of: trip,
                places: places,
                privacyRadius: privacyRadius
            ),
            localities: TripLocalityResolver.localities(on: trip),
            isCompleted: trip.endedAt != nil
        )
    }

    static func add(_ trip: Trip, in context: ModelContext) {
        guard canPersist(in: context) else { return }
        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = privacyRadiusMeters()
        apply(
            trip: trip,
            snapshot: snapshot(of: trip, places: places, privacyRadius: privacyRadius),
            sign: 1,
            in: context
        )
    }

    static func remove(_ trip: Trip, in context: ModelContext) {
        guard canPersist(in: context) else { return }
        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = privacyRadiusMeters()
        apply(
            trip: trip,
            snapshot: snapshot(of: trip, places: places, privacyRadius: privacyRadius),
            sign: -1,
            in: context
        )
    }

    static func update(
        _ trip: Trip,
        from previous: PremiumTripSnapshot?,
        in context: ModelContext
    ) {
        if let previous {
            apply(trip: trip, snapshot: previous, sign: -1, in: context)
        }
        add(trip, in: context)
    }

    static func apply(
        trip: Trip,
        snapshot: PremiumTripSnapshot,
        sign: Double,
        in context: ModelContext
    ) {
        guard canPersist(in: context) else { return }
        guard snapshot.isCompleted || trip.endedAt != nil else { return }
        if let route = snapshot.route {
            if sign > 0 {
                FrequentRouteAggregateService.add(route, in: context)
            } else {
                FrequentRouteAggregateService.remove(route, in: context)
            }
        }
        AchievementEvaluator.apply(
            trip: trip,
            sign: sign,
            localities: snapshot.localities,
            in: context
        )
        YearRecapCache.invalidate(yearContaining: trip.startedAt)
    }

    private static func canPersist(in context: ModelContext) -> Bool {
        do {
            var descriptor = FetchDescriptor<FrequentRouteAggregate>()
            descriptor.fetchLimit = 0
            _ = try context.fetch(descriptor)
            return true
        } catch {
            return false
        }
    }

    private static func privacyRadiusMeters() -> Double {
        let defaults = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName) ?? .standard
        let value = defaults.double(forKey: "privacyRadiusMeters")
        return value > 0 ? value : 500
    }
}

@MainActor
enum PremiumDerivedMaintenance {
    private static let rebuildVersionKey = "trailhound.premium.rebuiltVersion"
    private static let rebuildVersion = 1

    static func rebuildIfNeeded(container: ModelContainer) async {
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: rebuildVersionKey) < rebuildVersion else { return }
        await rebuildAll(container: container)
        defaults.set(rebuildVersion, forKey: rebuildVersionKey)
    }

    static func rebuildAll(container: ModelContainer) async {
        await PremiumDerivedRebuilder(modelContainer: container).run()
    }
}

@ModelActor
actor PremiumDerivedRebuilder {
    private static let batchSize = 200

    func run() async {
        for row in (try? modelContext.fetch(FetchDescriptor<FrequentRouteAggregate>())) ?? [] {
            modelContext.delete(row)
        }
        for row in (try? modelContext.fetch(FetchDescriptor<AchievementProgress>())) ?? [] {
            modelContext.delete(row)
        }
        for row in (try? modelContext.fetch(FetchDescriptor<VisitedLocality>())) ?? [] {
            modelContext.delete(row)
        }
        try? modelContext.save()

        let places = (try? modelContext.fetch(FetchDescriptor<SavedPlace>())) ?? []
        let privacyRadius = UserDefaults(suiteName: RecordingControlBridge.appGroupSuiteName)?
            .double(forKey: "privacyRadiusMeters") ?? 150
        let radius = privacyRadius > 0 ? privacyRadius : 500

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
                let snapshot = PremiumDerivedDelta.snapshot(
                    of: trip,
                    places: places,
                    privacyRadius: radius
                )
                PremiumDerivedDelta.apply(trip: trip, snapshot: snapshot, sign: 1, in: modelContext)
                trip.invalidatePointCaches()
            }
            try? modelContext.save()
            offset += batch.count
            await Task.yield()
        }

        YearRecapCache.invalidateAll()
    }
}
