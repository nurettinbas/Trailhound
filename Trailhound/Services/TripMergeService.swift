import CoreLocation
import Foundation
import SwiftData

enum TripMergeService {
    @MainActor
    static func merge(trips: [Trip], into context: ModelContext) throws -> Trip? {
        let completed = trips.filter { $0.endedAt != nil }.sorted { $0.startedAt < $1.startedAt }
        guard completed.count >= 2 else { return nil }

        let first = completed.first!
        let last = completed.last!

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

        var sequence = 0
        var totalDistance = 0.0
        var maxSpeed: Double = 0

        for (index, trip) in completed.enumerated() {
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
                merged.points.append(newPoint)
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
                merged.stops.append(newStop)
                context.insert(newStop)
            }

            let next = index + 1 < completed.count ? completed[index + 1] : nil
            junction(from: trip, to: next)?
                .apply(to: merged, candidates: copiedStops, context: context)

            TripRollupService.remove(trip, in: context)
            context.delete(trip)
        }

        merged.distanceMeters = totalDistance
        merged.maxSpeedMps = maxSpeed > 0 ? maxSpeed : nil
        merged.estimatedFuelCost = FuelCostCalculator.estimateCost(distanceMeters: totalDistance)
        merged.geocodeStatus = .pending
        context.insert(merged)

        let places = (try? context.fetch(FetchDescriptor<SavedPlace>())) ?? []
        TripDerivedMetrics.recompute(
            for: merged,
            places: places,
            privacyRadius: AppSettings.shared.privacyRadiusMeters
        )
        TripRollupService.add(merged, in: context)
        try context.save()

        let mergedUUID = merged.id
        let container = context.container
        Task { @MainActor in
            await TripPostProcessor.process(
                tripUUID: mergedUUID,
                container: container
            )
        }

        return merged
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
