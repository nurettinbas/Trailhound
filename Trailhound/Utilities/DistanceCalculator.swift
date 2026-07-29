import CoreLocation

enum DistanceCalculator {
    static func totalDistance(for locations: [CLLocation]) -> Double {
        guard locations.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<locations.count {
            total += locations[index].distance(from: locations[index - 1])
        }
        return total
    }

    /// Douglas-Peucker polyline simplification for storage optimization.
    static func simplify(coordinates: [CLLocationCoordinate2D], tolerance: Double = 0.00005) -> [CLLocationCoordinate2D] {
        guard coordinates.count > 2 else { return coordinates }
        return douglasPeucker(coordinates, epsilon: tolerance)
    }

    private static func douglasPeucker(_ points: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var maxDistance: Double = 0
        var index = 0
        let end = points.count - 1

        for i in 1..<end {
            let distance = perpendicularDistance(points[i], lineStart: points[0], lineEnd: points[end])
            if distance > maxDistance {
                maxDistance = distance
                index = i
            }
        }

        if maxDistance > epsilon {
            guard index > 0, index < end else {
                return [points[0], points[end]]
            }
            let left = douglasPeucker(Array(points[0...index]), epsilon: epsilon)
            let right = douglasPeucker(Array(points[index...end]), epsilon: epsilon)
            return Array(left.dropLast()) + right
        }

        return [points[0], points[end]]
    }

    private static func perpendicularDistance(
        _ point: CLLocationCoordinate2D,
        lineStart: CLLocationCoordinate2D,
        lineEnd: CLLocationCoordinate2D
    ) -> Double {
        let dx = lineEnd.longitude - lineStart.longitude
        let dy = lineEnd.latitude - lineStart.latitude
        if dx == 0 && dy == 0 {
            return hypot(point.latitude - lineStart.latitude, point.longitude - lineStart.longitude)
        }
        let t = ((point.longitude - lineStart.longitude) * dx + (point.latitude - lineStart.latitude) * dy) / (dx * dx + dy * dy)
        let clampedT = max(0, min(1, t))
        let projLat = lineStart.latitude + clampedT * dy
        let projLon = lineStart.longitude + clampedT * dx
        return hypot(point.latitude - projLat, point.longitude - projLon)
    }
}
