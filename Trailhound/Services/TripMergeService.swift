import CoreLocation
import Foundation
import SwiftData

enum TripMergeError: LocalizedError, Equatable {
    case needsTwoCompletedTrips

    var errorDescription: String? {
        switch self {
        case .needsTwoCompletedTrips:
            return L10n.tripsMergeNeedsTwo
        }
    }
}

/// Combines completed trip legs into a single trip.
///
/// Heavy work runs on `TripMergeWorker` (`@ModelActor`) so the UI stays responsive. The
/// `@MainActor` façade keeps call sites and tests on a familiar surface.
@MainActor
enum TripMergeService {
    /// Merges by ID off the main thread. Prefer this from UI code.
    static func merge(
        tripIDs: [UUID],
        container: ModelContainer,
        privacyRadius: Double = AppSettings.shared.privacyRadiusMeters
    ) async throws -> UUID {
        let mergedID = try await TripMergeWorker(modelContainer: container)
            .mergeAsync(tripIDs: tripIDs, privacyRadius: privacyRadius)
        for id in tripIDs {
            TripMapSnapshotCache.shared.remove(for: id)
            TripRoutePathCache.shared.remove(for: id)
        }
        TripRoutePathCache.shared.prewarm(tripID: mergedID, container: container)
        return mergedID
    }

    /// Merges trips already loaded in `context`. Used by unit tests and any caller that already
    /// holds the models. Throws `TripMergeError.needsTwoCompletedTrips` instead of returning nil.
    static func merge(
        trips: [Trip],
        into context: ModelContext,
        privacyRadius: Double = AppSettings.shared.privacyRadiusMeters
    ) throws -> Trip {
        let merged = try TripMergeCore.merge(
            trips: trips,
            into: context,
            privacyRadius: privacyRadius
        )
        let deletedIDs = trips.map(\.id)
        try context.save()
        for id in deletedIDs {
            TripMapSnapshotCache.shared.remove(for: id)
            TripRoutePathCache.shared.remove(for: id)
        }
        TripRoutePathCache.shared.prewarm(tripID: merged.id, container: context.container)
        return merged
    }
}

/// Shared merge body used by both the `@ModelActor` worker and the in-context façade.
enum TripMergeCore {
    static func merge(
        trips: [Trip],
        into context: ModelContext,
        privacyRadius: Double
    ) throws -> Trip {
        let completed = trips.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        let merged = try beginMergedTrip(from: completed, into: context)

        var sequence = 0
        var totalDistance = 0.0
        var maxSpeed: Double = 0

        for (index, trip) in completed.enumerated() {
            let next = index + 1 < completed.count ? completed[index + 1] : nil
            copyLeg(
                trip,
                next: next,
                into: merged,
                sequence: &sequence,
                totalDistance: &totalDistance,
                maxSpeed: &maxSpeed,
                context: context
            )
        }

        finalizeMergedTrip(
            merged,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            privacyRadius: privacyRadius,
            context: context
        )
        return merged
    }

    /// Copies one chronological leg onto `merged`.
    static func copyLeg(
        _ trip: Trip,
        next: Trip?,
        into merged: Trip,
        sequence: inout Int,
        totalDistance: inout Double,
        maxSpeed: inout Double,
        context: ModelContext
    ) {
        for point in trip.sortedPoints {
            let newPoint = TripPoint(
                timestamp: point.timestamp,
                latitude: point.latitude,
                longitude: point.longitude,
                sequence: sequence,
                speedMps: point.speedMps,
                trip: merged
            )
            sequence += 1
            // `trip:` already wires the inverse relationship — no `merged.points.append`.
            context.insert(newPoint)
            if let speed = point.speedMps { maxSpeed = max(maxSpeed, speed) }
        }
        totalDistance += trip.distanceMeters

        var copiedStops: [TripStop] = []
        for stop in trip.stops {
            let newStop = TripStop(
                latitude: stop.latitude,
                longitude: stop.longitude,
                startedAt: stop.startedAt,
                durationSeconds: stop.durationSeconds,
                trip: merged
            )
            copiedStops.append(newStop)
            context.insert(newStop)
        }

        junction(from: trip, to: next)?
            .apply(to: merged, candidates: copiedStops, context: context)

        trip.invalidatePointCaches()
        TripRollupDelta.remove(trip, in: context)
        context.delete(trip)
    }

    static func beginMergedTrip(from completed: [Trip], into context: ModelContext) throws -> Trip {
        guard completed.count >= 2 else { throw TripMergeError.needsTwoCompletedTrips }
        let first = completed[0]
        let last = completed[completed.count - 1]

        let merged = Trip(
            startedAt: first.startedAt,
            endedAt: last.endedAt
        )
        merged.categoryID = first.categoryID
        // Hand-picked by the driver, so unlike the route match the merged trip regenerates,
        // nothing can bring it back once the legs are deleted.
        merged.vehicleID = completed.compactMap(\.vehicleID).first
        merged.startAddress = first.startAddress
        merged.startPlaceName = first.startPlaceName
        merged.endAddress = last.endAddress
        merged.endPlaceName = last.endPlaceName
        merged.note = mergedNotes(from: completed)
        merged.label = mergedLabels(from: completed)
        // Insert before copying points so inverse relationships resolve against a registered trip.
        context.insert(merged)
        return merged
    }

    static func finalizeMergedTrip(
        _ merged: Trip,
        totalDistance: Double,
        maxSpeed: Double,
        privacyRadius: Double,
        context: ModelContext
    ) {
        merged.distanceMeters = totalDistance
        merged.maxSpeedMps = maxSpeed > 0 ? maxSpeed : nil
        merged.estimatedFuelCost = FuelCostCalculator.estimateCost(distanceMeters: totalDistance)
        merged.geocodeStatus = .pending

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        TripDerivedMetrics.recompute(
            for: merged,
            places: places,
            privacyRadius: privacyRadius
        )
        TripRollupDelta.add(merged, in: context)
    }

    /// The standstill between two merged legs. Merging used to join them with nothing but a
    /// break in the polyline, which hid the fact that the car had been parked there.
    private static func junction(from leg: Trip, to next: Trip?) -> TripStandstill? {
        guard let next, let legEnd = leg.endedAt else { return nil }

        let waited = next.startedAt.timeIntervalSince(legEnd)
        guard waited >= RecordingConfiguration.minimumMergeJunctionStopSeconds else { return nil }

        // Where the driver actually stood: the last fix of the leg that ended, falling back to
        // the first fix of the leg that resumes.
        guard let coordinate = leg.sortedPoints.last?.coordinate
            ?? next.sortedPoints.first?.coordinate else { return nil }

        return TripStandstill(coordinate: coordinate, startedAt: legEnd, endedAt: next.startedAt)
    }

    private static func mergedNotes(from trips: [Trip]) -> String? {
        let notes = trips.compactMap(\.note).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !notes.isEmpty else { return nil }
        return notes.joined(separator: "\n\n")
    }

    private static func mergedLabels(from trips: [Trip]) -> String? {
        let labels = trips.compactMap(\.label).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? labels
        guard !unique.isEmpty else { return nil }
        return unique.joined(separator: ", ")
    }
}

/// Off-main-thread merge so long GPS histories cannot stall the trip list.
@ModelActor
actor TripMergeWorker {
    func mergeAsync(tripIDs: [UUID], privacyRadius: Double) async throws -> UUID {
        let idList = tripIDs
        let fetched = (try? modelContext.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { idList.contains($0.id) })
        )) ?? []

        let completed = fetched.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        let merged = try TripMergeCore.beginMergedTrip(from: completed, into: modelContext)

        var sequence = 0
        var totalDistance = 0.0
        var maxSpeed: Double = 0

        for (index, trip) in completed.enumerated() {
            let next = index + 1 < completed.count ? completed[index + 1] : nil
            TripMergeCore.copyLeg(
                trip,
                next: next,
                into: merged,
                sequence: &sequence,
                totalDistance: &totalDistance,
                maxSpeed: &maxSpeed,
                context: modelContext
            )
            // Let the awaiting MainActor paint the loader between dense legs.
            await Task.yield()
        }

        TripMergeCore.finalizeMergedTrip(
            merged,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            privacyRadius: privacyRadius,
            context: modelContext
        )
        try modelContext.save()
        return merged.id
    }
}
