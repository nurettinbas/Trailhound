import CoreLocation
import Foundation

/// Caps how many polyline vertices a travel-journal map may draw.
enum TravelJournalMapBudget {
    static let totalCap = 4000
    /// Beyond this many members, draw a bounding polyline instead of every route.
    static let overviewTripCount = 20

    /// Allocates a per-trip vertex budget that sums to at most `totalCap`.
    /// Endpoints are preserved: a path with at least two points never drops below 2.
    static func allocate(pointCounts: [Int], totalCap: Int = totalCap) -> [Int] {
        let counts = pointCounts.map { max(0, $0) }
        let sum = counts.reduce(0, +)
        guard sum > totalCap else { return counts }

        var allocated = counts.map { count -> Int in
            guard count >= 2 else { return count }
            let share = Int((Double(count) / Double(sum) * Double(totalCap)).rounded(.down))
            return max(2, min(count, share))
        }

        var used = allocated.reduce(0, +)
        if used > totalCap {
            var overflow = used - totalCap
            for index in allocated.indices.reversed() where overflow > 0 {
                let reducible = allocated[index] - (counts[index] >= 2 ? 2 : 0)
                let cut = min(reducible, overflow)
                allocated[index] -= cut
                overflow -= cut
            }
            return allocated
        }

        var remainder = totalCap - used
        let order = allocated.indices.sorted { counts[$0] > counts[$1] }
        while remainder > 0 {
            var granted = false
            for index in order where remainder > 0 {
                guard allocated[index] < counts[index] else { continue }
                allocated[index] += 1
                remainder -= 1
                granted = true
            }
            if !granted { break }
        }
        return allocated
    }

    /// Evenly samples `coordinates` down to `maxCount`, always keeping both ends.
    static func downsample(
        _ coordinates: [CLLocationCoordinate2D],
        to maxCount: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maxCount, maxCount >= 2 else { return coordinates }
        if maxCount == 2 {
            return [coordinates[0], coordinates[coordinates.count - 1]]
        }
        let last = coordinates.count - 1
        return (0..<maxCount).map { step in
            let index = step == maxCount - 1
                ? last
                : Int((Double(step) * Double(last) / Double(maxCount - 1)).rounded())
            return coordinates[index]
        }
    }

    /// Axis-aligned bounding ring for far-zoom overview (not GPS-point clustering).
    static func boundingPolyline(from pieces: [[CLLocationCoordinate2D]]) -> [CLLocationCoordinate2D] {
        let flat = pieces.flatMap { $0 }
        guard let first = flat.first else { return [] }
        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude
        for coordinate in flat.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        return [
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
            CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
            CLLocationCoordinate2D(latitude: minLat, longitude: minLon)
        ]
    }
}
