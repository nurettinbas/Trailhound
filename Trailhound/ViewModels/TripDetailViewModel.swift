import Charts
import CoreLocation
import MapKit
import SwiftUI

struct SpeedColoredSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let color: Color
}

struct TripSummaryMetric: Identifiable {
    enum Kind {
        case duration(TimeInterval)
        case distance(Double)
        case maxSpeedKmh(Double)
        case averageSpeedKmh(Double)
        case fuel(Double)
    }

    let id: String
    let icon: String
    let title: String
    let kind: Kind

    func formatted(progress: Double) -> String {
        let p = min(1, max(0, progress))
        // Ease-out so the last digits land softly.
        let eased = 1 - pow(1 - p, 2.2)
        switch kind {
        case .duration(let seconds):
            return DateFormatters.formatDuration(seconds * eased)
        case .distance(let meters):
            return DateFormatters.formatDistance(meters * eased)
        case .maxSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .averageSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .fuel(let cost):
            return FuelCostCalculator.formatCost(cost * eased)
        }
    }
}

@MainActor
struct TripDetailViewModel {
    /// Fractional insets (0...1) describing UI that covers the map; used to zoom/pan so the route fits the visible area.
    struct MapFitContext: Equatable {
        var top: Double
        var bottom: Double
        var horizontal: Double

        static let detailWithPanel = MapFitContext(top: 0.13, bottom: 0.54, horizontal: 0.08)
        static let fullscreen = MapFitContext(top: 0.11, bottom: 0.10, horizontal: 0.08)
        static let cinematicReveal = MapFitContext(top: 0.13, bottom: 0.08, horizontal: 0.08)
    }

    let trip: Trip
    let places: [SavedPlace]
    let privacyRadius: Double

    private static var speedSegmentCache: [UUID: (pointCount: Int, segments: [SpeedColoredSegment])] = [:]

    static func invalidateSpeedSegmentCache(for tripID: UUID) {
        speedSegmentCache.removeValue(forKey: tripID)
    }

    var durationText: String {
        guard let duration = trip.duration else { return "—" }
        return DateFormatters.formatDuration(duration)
    }

    var distanceText: String {
        DateFormatters.formatDistance(trip.distanceMeters)
    }

    var dateText: String {
        DateFormatters.tripDate.string(from: trip.startedAt)
    }

    var routeSummary: String {
        TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
    }

    var coordinates: [CLLocationCoordinate2D] {
        RoutePrivacyClipper.clip(
            trip.coordinates,
            privacyRadiusMeters: privacyRadius,
            places: places
        )
    }

    /// Start/end markers must sit at the ends of the drawn route (which uses the
    /// full recorded points), not the privacy-clipped coordinates — otherwise the
    /// pins appear pushed inward from where the route actually begins/ends.
    var routeStartCoordinate: CLLocationCoordinate2D? {
        trip.sortedPoints.first?.coordinate ?? coordinates.first
    }

    var routeEndCoordinate: CLLocationCoordinate2D? {
        if trip.sortedPoints.count > 1 {
            return trip.sortedPoints.last?.coordinate
        }
        return coordinates.count > 1 ? coordinates.last : nil
    }

    var speedSamples: [(id: Int, date: Date, speedKmh: Double)] {
        trip.sortedPoints.enumerated().compactMap { index, point in
            guard let speedMps = point.speedMps, speedMps > 0 else { return nil }
            return (id: index, date: point.timestamp, speedKmh: speedMps * 3.6)
        }
    }

    var speedChartMaxKmh: Double {
        let peak = speedSamples.map(\.speedKmh).max() ?? 0
        let reference = max(peak, (trip.maxSpeedMps ?? 0) * 3.6, 60)
        return min(max(reference * 1.15, 80), 200)
    }

    var maxSpeedText: String? {
        guard let maxSpeed = trip.maxSpeedMps, maxSpeed > 0 else { return nil }
        return L10n.formatSpeedKmh(maxSpeed * 3.6)
    }

    var averageSpeedKmh: Double? {
        guard let duration = trip.duration, duration > 0, trip.distanceMeters > 0 else { return nil }
        let kmh = trip.distanceMeters * 3.6 / duration
        return kmh > 0 ? kmh : nil
    }

    var fuelText: String? {
        let cost = StatsViewModel.fuelCost(for: trip)
        guard cost > 0 else { return nil }
        return FuelCostCalculator.formatCost(cost)
    }

    var summaryItems: [(icon: String, title: String, value: String)] {
        summaryMetrics.map { ($0.icon, $0.title, $0.formatted(progress: 1)) }
    }

    var summaryMetrics: [TripSummaryMetric] {
        var items: [TripSummaryMetric] = [
            TripSummaryMetric(
                id: "duration",
                icon: "clock",
                title: L10n.duration,
                kind: .duration(trip.duration ?? 0)
            ),
            TripSummaryMetric(
                id: "distance",
                icon: "road.lanes",
                title: L10n.labelDistance,
                kind: .distance(trip.distanceMeters)
            )
        ]
        if let maxSpeed = trip.maxSpeedMps, maxSpeed > 0 {
            items.append(
                TripSummaryMetric(
                    id: "maxSpeed",
                    icon: "speedometer",
                    title: L10n.maxSpeed,
                    kind: .maxSpeedKmh(maxSpeed * 3.6)
                )
            )
        }
        if let averageSpeed = averageSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "averageSpeed",
                    icon: "gauge.with.dots.needle.33percent",
                    title: L10n.averageSpeed,
                    kind: .averageSpeedKmh(averageSpeed)
                )
            )
        }
        let fuel = StatsViewModel.fuelCost(for: trip)
        if fuel > 0 {
            items.append(
                TripSummaryMetric(
                    id: "fuel",
                    icon: "fuelpump",
                    title: L10n.estimatedFuel,
                    kind: .fuel(fuel)
                )
            )
        }
        return items
    }

    /// Full recorded path used for draw-on reveal (not privacy-clipped).
    var routeCoordinates: [CLLocationCoordinate2D] {
        trip.coordinates
    }

    var speedColoredSegments: [SpeedColoredSegment] {
        let pointCount = trip.sortedPoints.count
        if let cached = Self.speedSegmentCache[trip.id], cached.pointCount == pointCount {
            return cached.segments
        }

        let points = trip.sortedPoints
        let segments = buildSpeedColoredSegments(
            coordinates: points.map(\.coordinate),
            speeds: points.map(\.speedMps)
        )
        Self.speedSegmentCache[trip.id] = (pointCount, segments)
        return segments
    }

    /// Speed-colored segments truncated to `progress` (0...1) for route draw-on.
    func revealedSpeedColoredSegments(progress: Double) -> [SpeedColoredSegment] {
        let points = trip.sortedPoints
        guard points.count >= 2 else { return [] }
        let clamped = min(1, max(0, progress))
        if clamped >= 1 { return speedColoredSegments }

        let exact = Double(points.count - 1) * clamped
        let lastIndex = min(points.count - 1, Int(exact))
        let fraction = exact - Double(Int(exact))

        var coordinates = Array(points.prefix(lastIndex + 1)).map(\.coordinate)
        var speeds = Array(points.prefix(lastIndex + 1)).map(\.speedMps)

        if lastIndex < points.count - 1, fraction > 0.001 {
            let start = points[lastIndex].coordinate
            let end = points[lastIndex + 1].coordinate
            coordinates.append(
                CLLocationCoordinate2D(
                    latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                    longitude: start.longitude + (end.longitude - start.longitude) * fraction
                )
            )
            speeds.append(points[lastIndex].speedMps)
        }

        return buildSpeedColoredSegments(coordinates: coordinates, speeds: speeds)
    }

    func revealedFallbackCoordinates(progress: Double) -> [CLLocationCoordinate2D] {
        RoutePathReveal.prefix(coordinates, progress: progress)
    }

    func annotationRevealProgress(forStopAt coordinate: CLLocationCoordinate2D) -> Double {
        RoutePathReveal.progress(nearestTo: coordinate, in: routeCoordinates)
    }

    func followRegion(
        progress: Double,
        fit: MapFitContext = .cinematicReveal
    ) -> MKCoordinateRegion? {
        let path = routeCoordinates.isEmpty ? coordinates : routeCoordinates
        guard let tip = RoutePathReveal.tip(of: path, progress: progress) else { return nil }
        guard let settled = mapRegion(fit: fit) else { return nil }

        // Follow a bit tighter than the final fit early on, then ease out to the settled span.
        let blend = min(1, max(0, (progress - 0.55) / 0.45))
        let followFactor = 0.72 + (0.28 * blend)
        return MKCoordinateRegion(
            center: tip,
            span: MKCoordinateSpan(
                latitudeDelta: settled.span.latitudeDelta * followFactor,
                longitudeDelta: settled.span.longitudeDelta * followFactor
            )
        )
    }

    /// High-altitude opening look — route as a small silhouette below.
    func cinematicOpeningCamera(fit: MapFitContext = .cinematicReveal) -> MapCamera? {
        guard let settled = mapRegion(fit: fit) else { return nil }
        let path = routeCoordinates.isEmpty ? coordinates : routeCoordinates
        let center = path.first ?? settled.center
        return MapCamera(
            centerCoordinate: center,
            distance: cameraDistance(for: settled.span, multiplier: 4.6),
            heading: initialHeading(of: path),
            pitch: 58
        )
    }

    /// Dive + follow the drawing tip; pitch and altitude ease toward the settle pose.
    func cinematicFollowCamera(
        routeProgress: Double,
        fit: MapFitContext = .cinematicReveal
    ) -> MapCamera? {
        let path = routeCoordinates.isEmpty ? coordinates : routeCoordinates
        guard let tip = RoutePathReveal.tip(of: path, progress: routeProgress) else { return nil }
        guard let settled = mapRegion(fit: fit) else { return nil }

        let p = min(1, max(0, routeProgress))
        let ease = 1 - pow(1 - p, 1.65)
        let distance = cameraDistance(
            for: settled.span,
            multiplier: 4.6 - (3.35 * ease)
        )
        let pitch = 58 - (48 * ease)
        let lookAhead = RoutePathReveal.tip(of: path, progress: min(1, p + 0.04)) ?? tip
        return MapCamera(
            centerCoordinate: tip,
            distance: distance,
            heading: Self.bearing(from: tip, to: lookAhead),
            pitch: pitch
        )
    }

    private func cameraDistance(for span: MKCoordinateSpan, multiplier: Double) -> CLLocationDistance {
        let metersAcross = max(span.latitudeDelta, span.longitudeDelta) * 111_320
        return max(320, metersAcross * multiplier)
    }

    private func initialHeading(of path: [CLLocationCoordinate2D]) -> CLLocationDirection {
        guard path.count >= 2 else { return 0 }
        return Self.bearing(from: path[0], to: path[min(path.count - 1, max(1, path.count / 8))])
    }

    private static func bearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let dLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private func buildSpeedColoredSegments(
        coordinates: [CLLocationCoordinate2D],
        speeds: [Double?]
    ) -> [SpeedColoredSegment] {
        guard coordinates.count >= 2, coordinates.count == speeds.count else { return [] }

        var segments: [SpeedColoredSegment] = []
        var currentCoordinates = [coordinates[0]]
        var currentColor = Self.speedColor(for: speeds[0])

        for index in 1..<coordinates.count {
            let color = Self.speedColor(for: speeds[index])
            currentCoordinates.append(coordinates[index])

            if color != currentColor {
                if currentCoordinates.count >= 2 {
                    segments.append(
                        SpeedColoredSegment(
                            id: segments.count,
                            coordinates: currentCoordinates,
                            color: currentColor
                        )
                    )
                }
                currentCoordinates = [coordinates[index - 1], coordinates[index]]
                currentColor = color
            }
        }

        if currentCoordinates.count >= 2 {
            segments.append(
                SpeedColoredSegment(
                    id: segments.count,
                    coordinates: currentCoordinates,
                    color: currentColor
                )
            )
        }

        return segments
    }

    func mapRegion(fit: MapFitContext = .detailWithPanel) -> MKCoordinateRegion? {
        let path = routeCoordinates.isEmpty ? coordinates : routeCoordinates
        guard !path.isEmpty else { return nil }
        return Self.regionFitting(coordinates: path, fit: fit)
    }

    /// Fits the camera to the drawn route inside the visible map area.
    static func regionFitting(
        coordinates: [CLLocationCoordinate2D],
        fit: MapFitContext
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        var latDelta = max(maxLat - minLat, 0)
        var lonDelta = max(maxLon - minLon, 0)

        // ~180m floor — keeps very short hops readable without over-zooming long trips.
        let minimumDelta = 0.0016
        if latDelta < 1e-8 { latDelta = minimumDelta * 0.35 }
        if lonDelta < 1e-8 { lonDelta = minimumDelta * 0.35 }

        let visibleHeight = max(0.22, 1 - fit.top - fit.bottom)
        let visibleWidth = max(0.22, 1 - (2 * fit.horizontal))

        var requiredLat = latDelta / visibleHeight
        var requiredLon = lonDelta / visibleWidth

        let rawMax = max(latDelta, lonDelta)
        let margin: Double
        if rawMax < 0.003 {
            margin = 2.35
        } else if rawMax < 0.01 {
            margin = 1.85
        } else if rawMax < 0.05 {
            margin = 1.45
        } else {
            margin = 1.28
        }

        requiredLat *= margin
        requiredLon *= margin

        let side = max(requiredLat, requiredLon, minimumDelta)

        // Shift the center so the route sits in the visible map above the bottom sheet.
        let visibleCenterY = fit.top + (visibleHeight / 2)
        let latOffset = (0.5 - visibleCenterY) * side

        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: ((minLat + maxLat) / 2) - latOffset,
                longitude: (minLon + maxLon) / 2
            ),
            span: MKCoordinateSpan(latitudeDelta: side, longitudeDelta: side)
        )
    }

    static func speedColor(for speedMps: Double?) -> Color {
        let kmh = (speedMps ?? 0) * 3.6
        if kmh < 50 { return .green }
        if kmh < 90 { return .yellow }
        return .red
    }
}
