import Charts
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct SpeedColoredSegment: Identifiable {
    let id: Int
    let coordinates: [CLLocationCoordinate2D]
    let band: SpeedBand

    var color: Color { band.color }

    init(id: Int, coordinates: [CLLocationCoordinate2D], band: SpeedBand) {
        self.id = id
        self.coordinates = coordinates
        self.band = band
    }
}

struct TripSummaryMetric: Identifiable {
    enum Kind {
        case duration(TimeInterval)
        case distance(Double)
        case maxSpeedKmh(Double)
        case averageSpeedKmh(Double)
        case cruiseSpeedKmh(Double)
        case mostCommonSpeedKmh(Double)
        case medianSpeedKmh(Double)
        case p90SpeedKmh(Double)
        case stopDuration(TimeInterval)
        case fuel(Double)
        /// Cost plus optional volume label (e.g. "₺142 · 2,1 L").
        case dynamicFuel(cost: Double, detail: String?)
    }

    let id: String
    let icon: String
    let title: String
    let kind: Kind
    var helpTitle: String? = nil
    var helpBody: String? = nil

    var showsHelp: Bool { helpTitle != nil && helpBody != nil }

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
        case .cruiseSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .mostCommonSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .medianSpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .p90SpeedKmh(let kmh):
            return L10n.formatSpeedKmh(kmh * eased)
        case .stopDuration(let seconds):
            return DateFormatters.formatDuration(seconds * eased)
        case .fuel(let cost):
            return FuelCostCalculator.formatCost(cost * eased)
        case .dynamicFuel(let cost, let detail):
            let costText = FuelCostCalculator.formatCost(cost * eased)
            if let detail, !detail.isEmpty, p >= 0.99 {
                return "\(costText) · \(detail)"
            }
            return costText
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
        /// Map view width / height. Needed so latitude/longitude spans match the portrait
        /// aspect — equal spans make MapKit expand latitude and defeat the vertical offset.
        var aspectWidthOverHeight: Double

        /// Visible strip above the default balanced overlay panel (full-screen map).
        /// `top` is only status/nav chrome over the map (transparent bar); keep it measured in the view.
        static let detailWithPanel = MapFitContext(
            top: 0.10,
            bottom: 0.60,
            horizontal: 0.06,
            aspectWidthOverHeight: 0.46
        )
        static let fullscreen = MapFitContext(
            top: 0.11,
            bottom: 0.10,
            horizontal: 0.06,
            aspectWidthOverHeight: 0.46
        )
        static let cinematicReveal = MapFitContext(
            top: 0.10,
            bottom: 0.08,
            horizontal: 0.06,
            aspectWidthOverHeight: 0.46
        )

        /// Fit for a live overlay panel on a full-screen map.
        /// - topChromeFraction: status + nav overlay on the map (from GeometryReader)
        /// - panelFraction: opaque card height / map height
        /// Bottom adds legend + pin clearance so the route centers in the clear map, not under chrome.
        static func detailOverlay(
            panelFraction: Double,
            aspectWidthOverHeight: Double,
            topChromeFraction: Double = 0.10
        ) -> MapFitContext {
            let top = max(0.06, min(topChromeFraction, 0.16))
            // Speed legend + start/end pin labels sit above the card in the map strip.
            let bottomChrome = 0.09
            let minVisible = 0.18
            let bottom = min(
                max(panelFraction + bottomChrome, 0.34),
                1 - top - minVisible
            )
            return MapFitContext(
                top: top,
                bottom: bottom,
                horizontal: 0.06,
                aspectWidthOverHeight: max(0.35, min(aspectWidthOverHeight, 0.7))
            )
        }
    }

    let trip: Trip
    let places: [SavedPlace]
    let privacyRadius: Double
    /// Decimated drawable pieces from `TripRoutePathCache`. `nil` until the async load finishes.
    let displayPieces: [[RouteSample]]?
    let routeFingerprint: TripRoutePathFingerprint

    private struct SpeedSegmentCacheEntry {
        let fingerprint: TripRoutePathFingerprint
        let displayPointCount: Int
        let segments: [SpeedColoredSegment]
    }

    private static var speedSegmentCache: [UUID: SpeedSegmentCacheEntry] = [:]

    private struct ChartSeriesCacheEntry {
        let fingerprint: TripRoutePathFingerprint
        let series: SpeedChartSeries.Series
    }

    /// The chart series is read several times per body pass — samples, median interval, axis
    /// scale — and building it walks every point, so it is built once per trip.
    private static var chartSeriesCache: [UUID: ChartSeriesCacheEntry] = [:]

    static func invalidateSpeedSegmentCache(for tripID: UUID) {
        speedSegmentCache.removeValue(forKey: tripID)
        chartSeriesCache.removeValue(forKey: tripID)
    }

    init(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        displayPieces: [[RouteSample]]? = nil
    ) {
        self.trip = trip
        self.places = places
        self.privacyRadius = privacyRadius
        self.displayPieces = displayPieces
        self.routeFingerprint = TripRoutePathFingerprint.make(from: trip)
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

    var hasDisplayPath: Bool {
        displayPieces != nil
    }

    /// Flattened coordinates of the prepared display path (empty while loading).
    var displayCoordinates: [CLLocationCoordinate2D] {
        (displayPieces ?? []).flatMap { $0.map(\.coordinate) }
    }

    /// Start/end markers sit at the ends of the drawn route. Prefer denormalised endpoints so
    /// opening detail never faults every GPS point just to place two pins.
    var routeStartCoordinate: CLLocationCoordinate2D? {
        if let first = displayPieces?.first?.first?.coordinate {
            return first
        }
        return trip.startCoordinate
    }

    var routeEndCoordinate: CLLocationCoordinate2D? {
        if let last = displayPieces?.last?.last?.coordinate {
            return last
        }
        return trip.endCoordinate
    }

    var speedSamples: [(id: Int, date: Date, speedKmh: Double)] {
        speedChartSeries.samples.enumerated().map { index, sample in
            (id: index, date: sample.date, speedKmh: sample.speedKmh)
        }
    }

    /// Median gap between the samples the chart actually plots — the chart uses this to decide
    /// where a real recording gap is, instead of a fixed threshold that breaks sparse trips.
    var speedSampleMedianIntervalSeconds: TimeInterval {
        speedChartSeries.medianIntervalSeconds
    }

    private var speedChartSeries: SpeedChartSeries.Series {
        if let cached = Self.chartSeriesCache[trip.id], cached.fingerprint == routeFingerprint {
            return cached.series
        }
        // Prefer the prepared display path so opening detail never faults every GPS point
        // just to draw the chart. Empty until `displayPieces` arrive.
        guard let pieces = displayPieces else {
            return SpeedChartSeries.Series()
        }
        let series = SpeedChartSeries.build(samples: pieces.flatMap { $0 })
        Self.chartSeriesCache[trip.id] = ChartSeriesCacheEntry(
            fingerprint: routeFingerprint,
            series: series
        )
        return series
    }

    /// Prefers speeds from the prepared display path so the summary strip never faults points
    /// on first paint. Falls back to the stored vetted maximum while the path is still loading.
    var derivedMaxSpeedMps: Double? {
        if let pieces = displayPieces, !pieces.isEmpty {
            return TripSpeedSummary.maxSpeedMps(samples: pieces.flatMap { $0 })
        }
        return TripSpeedSummary.believableStoredMaxSpeedMps(trip.maxSpeedMps)
    }

    /// Scaled from the plotted data alone. Blending in the stored maximum pinned the axis at
    /// 200 km/h for a trip whose real peak was 84, squashing the whole line into the bottom third.
    var speedChartMaxKmh: Double {
        let peak = speedSamples.map(\.speedKmh).max() ?? 0
        return min(max(peak * 1.15, 80), 200)
    }

    var maxSpeedText: String? {
        guard let maxSpeed = derivedMaxSpeedMps else { return nil }
        return L10n.formatSpeedKmh(maxSpeed * 3.6)
    }

    var averageSpeedKmh: Double? {
        guard let duration = trip.duration, duration > 0, trip.distanceMeters > 0 else { return nil }
        let kmh = trip.distanceMeters * 3.6 / duration
        return kmh > 0 ? kmh : nil
    }

    /// Prefer the prepared display path when it is loaded so the strip always uses the current
    /// formula (implied-speed stops, neighbour-blended mode). Fall back to stored cruise / stop
    /// while the path is still loading.
    private var speedProfile: TripSpeedProfile.Result {
        if let pieces = displayPieces, !pieces.isEmpty {
            return TripSpeedProfile.compute(samples: pieces.flatMap { $0 })
        }
        if trip.stopDurationSeconds != nil {
            let cruise = trip.cruiseSpeedKmh ?? 0
            let storedMostCommon = trip.mostCommonSpeedKmh ?? 0
            return TripSpeedProfile.Result(
                cruiseSpeedKmh: cruise > 0 ? cruise : nil,
                cruiseDurationSeconds: trip.cruiseDurationSeconds ?? 0,
                stopDurationSeconds: trip.stopDurationSeconds ?? 0,
                mostCommonSpeedKmh: storedMostCommon > 0 ? storedMostCommon : nil,
                medianSpeedKmh: nil,
                p90SpeedKmh: nil
            )
        }
        return .empty
    }

    var cruiseSpeedKmh: Double? {
        speedProfile.cruiseSpeedKmh
    }

    var mostCommonSpeedKmh: Double? {
        speedProfile.mostCommonSpeedKmh
    }

    var medianSpeedKmh: Double? {
        speedProfile.medianSpeedKmh
    }

    var p90SpeedKmh: Double? {
        speedProfile.p90SpeedKmh
    }

    var stopDurationSeconds: TimeInterval? {
        guard trip.stopDurationSeconds != nil || displayPieces != nil else { return nil }
        return speedProfile.stopDurationSeconds
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
        if let maxSpeed = derivedMaxSpeedMps {
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
        if let cruiseSpeed = cruiseSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "cruiseSpeed",
                    icon: "gauge.with.dots.needle.67percent",
                    title: L10n.cruiseSpeed,
                    kind: .cruiseSpeedKmh(cruiseSpeed),
                    helpTitle: L10n.cruiseSpeedHelpTitle,
                    helpBody: L10n.cruiseSpeedHelpBody
                )
            )
        }
        // Immediately right of cruise.
        if let mostCommon = mostCommonSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "mostCommonSpeed",
                    icon: "chart.bar",
                    title: L10n.mostCommonSpeed,
                    kind: .mostCommonSpeedKmh(mostCommon),
                    helpTitle: L10n.mostCommonSpeedHelpTitle,
                    helpBody: L10n.mostCommonSpeedHelpBody
                )
            )
        }
        if let median = medianSpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "medianSpeed",
                    icon: "equal.circle",
                    title: L10n.medianSpeed,
                    kind: .medianSpeedKmh(median),
                    helpTitle: L10n.medianSpeedHelpTitle,
                    helpBody: L10n.medianSpeedHelpBody
                )
            )
        }
        if let p90 = p90SpeedKmh {
            items.append(
                TripSummaryMetric(
                    id: "p90Speed",
                    icon: "arrow.up.right.circle",
                    title: L10n.p90Speed,
                    kind: .p90SpeedKmh(p90),
                    helpTitle: L10n.p90SpeedHelpTitle,
                    helpBody: L10n.p90SpeedHelpBody
                )
            )
        }
        if let stopDuration = stopDurationSeconds {
            items.append(
                TripSummaryMetric(
                    id: "stopDuration",
                    icon: "pause.circle",
                    title: L10n.stopDuration,
                    kind: .stopDuration(stopDuration)
                )
            )
        }
        let fuel = StatsViewModel.fuelCost(for: trip)
        if fuel > 0 {
            items.append(
                TripSummaryMetric(
                    id: "fuel",
                    icon: "fuelpump",
                    title: L10n.avgFuel,
                    kind: .fuel(fuel)
                )
            )
        }
        let dynamic = trip.dynamicFuelCost ?? 0
        if dynamic > 0 {
            items.append(
                TripSummaryMetric(
                    id: "dynamicFuel",
                    icon: "flame",
                    title: L10n.dynamicFuel,
                    kind: .dynamicFuel(cost: dynamic, detail: dynamicFuelVolumeText),
                    helpTitle: L10n.dynamicFuelHelpTitle,
                    helpBody: L10n.dynamicFuelHelpBody
                )
            )
        }
        return items
    }

    /// Litres or kWh implied by stored dynamic cost ÷ unit price snapshot.
    private var dynamicFuelVolumeText: String? {
        let cost = trip.dynamicFuelCost ?? 0
        let price = trip.fuelUnitPrice ?? 0
        guard cost > 0, price > 0 else { return nil }
        let volume = cost / price
        let isElectric = trip.vehicle?.fuelType == .electric
        let unit = isElectric ? "kWh" : "L"
        let formatter = NumberFormatter()
        formatter.locale = DateFormatters.currentLocale
        formatter.maximumFractionDigits = volume >= 10 ? 1 : 2
        formatter.minimumFractionDigits = 0
        let number = formatter.string(from: NSNumber(value: volume)) ?? String(format: "%.1f", volume)
        return "\(number) \(unit)"
    }

    /// Prepared display samples when available; empty while the async path is still loading.
    var routeSamples: [RouteSample] {
        (displayPieces ?? []).flatMap { $0 }
    }

    /// How many points actually reach the renderer. Reveal animation thresholds use this
    /// rather than the raw recorded count, which is now unbounded.
    var displayPointCount: Int {
        if let cached = Self.speedSegmentCache[trip.id], cached.fingerprint == routeFingerprint {
            return cached.displayPointCount
        }
        return (displayPieces ?? []).reduce(0) { $0 + $1.count }
    }

    var speedColoredSegments: [SpeedColoredSegment] {
        guard let pieces = displayPieces else { return [] }
        if let cached = Self.speedSegmentCache[trip.id], cached.fingerprint == routeFingerprint {
            return cached.segments
        }

        let segments = SpeedColoredSegmentBuilder.build(pieces: pieces)
        Self.speedSegmentCache[trip.id] = SpeedSegmentCacheEntry(
            fingerprint: routeFingerprint,
            displayPointCount: pieces.reduce(0) { $0 + $1.count },
            segments: segments
        )
        return segments
    }

    /// Speed-colored segments truncated to `progress` (0...1) for route draw-on.
    /// Uses the prepared segments — never re-runs decimation or recoloring.
    func revealedSpeedColoredSegments(progress: Double) -> [SpeedColoredSegment] {
        SpeedColoredSegmentBuilder.revealed(segments: speedColoredSegments, progress: progress)
    }

    func revealedFallbackCoordinates(progress: Double) -> [CLLocationCoordinate2D] {
        let path = displayCoordinates
        guard path.count >= 2 else { return [] }
        return RoutePathReveal.prefix(path, progress: progress)
    }

    func annotationRevealProgress(forStopAt coordinate: CLLocationCoordinate2D) -> Double {
        let path = displayCoordinates
        guard path.count >= 2 else { return 1 }
        return RoutePathReveal.progress(nearestTo: coordinate, in: path)
    }

    func followRegion(
        progress: Double,
        fit: MapFitContext = .cinematicReveal
    ) -> MKCoordinateRegion? {
        let path = displayCoordinates
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
        let path = displayCoordinates
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
        let path = displayCoordinates
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

    func mapRegion(fit: MapFitContext = .detailWithPanel) -> MKCoordinateRegion? {
        let path = displayCoordinates
        if path.count >= 2 {
            return Self.regionFitting(coordinates: path, fit: fit)
        }
        let endpoints = [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        guard !endpoints.isEmpty else { return nil }
        return Self.regionFitting(coordinates: endpoints, fit: fit)
    }

    /// Live layout fit — uses map pixel size + edge padding (nav, panel, legend).
    func mapRegion(
        mapSize: CGSize,
        edgePadding: UIEdgeInsets,
        margin: Double = 1.2
    ) -> MKCoordinateRegion? {
        let path = displayCoordinates
        if path.count >= 2 {
            return Self.regionFitting(
                coordinates: path,
                mapSize: mapSize,
                edgePadding: edgePadding,
                margin: margin
            )
        }
        let endpoints = [trip.startCoordinate, trip.endCoordinate].compactMap { $0 }
        guard !endpoints.isEmpty else { return nil }
        return Self.regionFitting(
            coordinates: endpoints,
            mapSize: mapSize,
            edgePadding: edgePadding,
            margin: margin
        )
    }

    /// Pixel-accurate fit: route centered in the map view after `edgePadding` (nav + panel + legend).
    static func regionFitting(
        coordinates: [CLLocationCoordinate2D],
        mapSize: CGSize,
        edgePadding: UIEdgeInsets,
        margin: Double = 1.2
    ) -> MKCoordinateRegion? {
        guard let first = coordinates.first,
              mapSize.width > 1,
              mapSize.height > 1
        else { return nil }

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

        let midLat = (minLat + maxLat) / 2
        let midLon = (minLon + maxLon) / 2

        // Build route map-rect ( Mercator ).
        let nw = MKMapPoint(CLLocationCoordinate2D(latitude: maxLat, longitude: minLon))
        let se = MKMapPoint(CLLocationCoordinate2D(latitude: minLat, longitude: maxLon))
        var routeRect = MKMapRect(
            x: min(nw.x, se.x),
            y: min(nw.y, se.y),
            width: max(abs(nw.x - se.x), 1),
            height: max(abs(nw.y - se.y), 1)
        )
        // ~180 m floor in map points at mid-latitude.
        let minMeters: CLLocationDistance = 180
        let metersPerPoint = MKMetersPerMapPointAtLatitude(midLat)
        let minPoints = minMeters / max(metersPerPoint, 1e-6)
        if routeRect.size.width < minPoints {
            routeRect = routeRect.insetBy(dx: -(minPoints - routeRect.size.width) / 2, dy: 0)
        }
        if routeRect.size.height < minPoints {
            routeRect = routeRect.insetBy(dx: 0, dy: -(minPoints - routeRect.size.height) / 2)
        }

        let usableWidth = max(mapSize.width - edgePadding.left - edgePadding.right, 48)
        let usableHeight = max(mapSize.height - edgePadding.top - edgePadding.bottom, 48)

        // Map points per view point so the route fills the usable rect.
        let scale = max(
            routeRect.size.width / usableWidth,
            routeRect.size.height / usableHeight
        ) * margin

        let fullWidth = scale * mapSize.width
        let fullHeight = scale * mapSize.height

        let routeCenter = MKMapPoint(CLLocationCoordinate2D(latitude: midLat, longitude: midLon))
        let visibleCenterX = edgePadding.left + usableWidth / 2
        let visibleCenterY = edgePadding.top + usableHeight / 2

        // Place route center at the visible-rect center (not the full map center).
        let mapCenterX = routeCenter.x + (0.5 - Double(visibleCenterX / mapSize.width)) * fullWidth
        let mapCenterY = routeCenter.y + (0.5 - Double(visibleCenterY / mapSize.height)) * fullHeight

        let fitted = MKMapRect(
            x: mapCenterX - fullWidth / 2,
            y: mapCenterY - fullHeight / 2,
            width: fullWidth,
            height: fullHeight
        )
        return MKCoordinateRegion(fitted)
    }

    /// Fractional-inset wrapper (tests + callers without a live layout size).
    static func regionFitting(
        coordinates: [CLLocationCoordinate2D],
        fit: MapFitContext
    ) -> MKCoordinateRegion? {
        let size = CGSize(width: 390, height: 844)
        let padding = UIEdgeInsets(
            top: fit.top * size.height,
            left: fit.horizontal * size.width,
            bottom: fit.bottom * size.height,
            right: fit.horizontal * size.width
        )
        return regionFitting(
            coordinates: coordinates,
            mapSize: size,
            edgePadding: padding
        )
    }

    /// Flat MapCamera distance that frames `region` without pitch.
    static func cameraDistance(for region: MKCoordinateRegion) -> CLLocationDistance {
        let metersAcross = max(region.span.latitudeDelta, region.span.longitudeDelta) * 111_320
        return max(400, metersAcross * 1.55)
    }

    static func speedColor(for speedMps: Double?) -> Color {
        SpeedBand.initial(kmh: (speedMps ?? 0) * 3.6).color
    }
}
