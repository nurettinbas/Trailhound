import Foundation
import SwiftData

/// Computes the values that read paths would otherwise derive by walking every GPS point.
///
/// Stats, the trip list and search all used to fault a trip's whole `points` relationship just to
/// read its first coordinate or its night-driving share. Writing those values once, at the few
/// places where a trip's points actually change, keeps those reads O(1).
enum TripDerivedMetrics {
    /// Recomputes every field derived from `points`. Safe to call repeatedly.
    /// - Parameter fuelType: Used for VSP/Willans idle + regen factors. Prefer the trip's vehicle;
    ///   callers with only `vehicleID` should resolve before clearing the relationship.
    static func recompute(for trip: Trip, fuelType: VehicleFuelType = .petrol) {
        recomputeEndpoints(for: trip)
        recomputeNightDistance(for: trip)
        recomputeSpeedProfile(for: trip)
        recomputeFuel(for: trip, fuelType: fuelType)
    }

    /// Full refresh including the search index, which additionally depends on saved places.
    static func recompute(
        for trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        fuelType: VehicleFuelType = .petrol
    ) {
        recompute(for: trip, fuelType: fuelType)
        refreshSearchIndex(for: trip, places: places, privacyRadius: privacyRadius)
    }

    static func recomputeEndpoints(for trip: Trip) {
        let points = trip.sortedPoints
        if let first = points.first {
            trip.startLatitude = first.latitude
            trip.startLongitude = first.longitude
        } else {
            trip.startLatitude = nil
            trip.startLongitude = nil
        }
        if let last = points.last {
            trip.endLatitude = last.latitude
            trip.endLongitude = last.longitude
        } else {
            trip.endLatitude = nil
            trip.endLongitude = nil
        }
    }

    static func recomputeNightDistance(for trip: Trip) {
        let share = StatsViewModel.walkNightDistanceShare(for: trip)
        trip.nightDistanceMeters = share?.nightMeters ?? 0
        trip.trackedDistanceMeters = share?.trackedMeters ?? 0
    }

    /// Writes cruise / stop / most-common totals so stats never have to walk points. Always
    /// sets every field (0 when there is nothing to report) so backfill can treat `nil` as pending.
    static func recomputeSpeedProfile(for trip: Trip) {
        let profile = TripSpeedProfile.compute(points: trip.sortedPoints)
        trip.cruiseSpeedKmh = profile.cruiseSpeedKmh ?? 0
        trip.cruiseDurationSeconds = profile.cruiseDurationSeconds
        trip.stopDurationSeconds = profile.stopDurationSeconds
        trip.mostCommonSpeedKmh = profile.mostCommonSpeedKmh ?? 0
    }

    /// Writes trip-specific VSP/Willans cost. Always sets a non-nil value (0 when empty) so
    /// backfill can treat `nil` as pending. Does not rewrite `estimatedFuelCost` (avg).
    static func recomputeFuel(
        for trip: Trip,
        fuelType: VehicleFuelType = .petrol,
        vehicle: VehicleProfile? = nil
    ) {
        let c0 = FuelCostCalculator.resolvedConsumption(
            tripConsumption: trip.fuelConsumptionPer100,
            vehicle: vehicle
        )
        let unitPrice = FuelCostCalculator.resolvedUnitPrice(
            tripUnitPrice: trip.fuelUnitPrice,
            vehicle: vehicle
        )
        let estimate = TripFuelEstimate.compute(
            points: trip.sortedPoints,
            distanceMeters: trip.distanceMeters,
            consumptionPer100: c0,
            unitPrice: unitPrice,
            fuelType: fuelType
        )
        trip.dynamicFuelCost = estimate.dynamicCost
    }

    /// Mirrors the fields `TripListViewModel.matchesSearch` scans, lowercased once up front so
    /// filtering never has to resolve place names or coordinates per keystroke.
    static func refreshSearchIndex(for trip: Trip, places: [SavedPlace], privacyRadius: Double) {
        let components = [
            TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius),
            trip.label,
            trip.note,
            trip.startAddress,
            trip.endAddress,
            trip.startPlaceName,
            trip.endPlaceName
        ]

        trip.searchIndex = components
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .lowercased()
    }
}
