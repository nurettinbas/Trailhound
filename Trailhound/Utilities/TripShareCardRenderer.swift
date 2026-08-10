import MapKit
import SwiftUI
import UIKit

@MainActor
enum TripShareCardRenderer {
    static let defaultSize = CGSize(width: 1080, height: 1480)

    static func render(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        size: CGSize = defaultSize
    ) async -> UIImage? {
        // Fault points once on the main actor, then hop off for clip / decimate / chart / bands.
        let points = TripShareRoutePrep.points(
            from: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let placeInputs = places.map(TripShareRoutePrep.Place.init)
        let displayScale = UIScreen.main.scale

        let prep = await Task.detached(priority: .userInitiated) {
            TripShareRoutePrep.prepare(
                points: points,
                privacyRadiusMeters: privacyRadius,
                places: placeInputs
            )
        }.value

        let mapHeight = size.height * 0.55
        let mapSize = CGSize(width: size.width, height: mapHeight)
        let coordinates = prep.strokes.flatMap(\.coordinates)

        let mapImage: UIImage
        if coordinates.count >= 2 {
            mapImage = await renderMap(
                strokes: prep.strokes,
                start: prep.start.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                },
                end: prep.end.map {
                    CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                },
                size: mapSize,
                displayScale: displayScale
            ) ?? UIImage()
        } else {
            mapImage = UIImage()
        }

        return composeCard(
            mapImage: mapImage,
            trip: trip,
            places: places,
            privacyRadius: privacyRadius,
            chartSamples: prep.chartSeries,
            chartMaxKmh: prep.chartMaxKmh,
            size: size
        )
    }

    // MARK: - Map

    private static func renderMap(
        strokes: [TripShareRoutePrep.StrokeSegment],
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?,
        size: CGSize,
        displayScale: CGFloat
    ) async -> UIImage? {
        let coordinates = strokes.flatMap(\.coordinates)
        guard !coordinates.isEmpty else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = regionFor(coordinates: coordinates)
        options.size = size
        options.mapType = .standard
        options.traitCollection = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = .dark
            mutableTraits.displayScale = displayScale
        }

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await snapshotter.start()
        } catch {
            return nil
        }

        return drawRoute(on: snapshot, strokes: strokes, start: start, end: end)
    }

    private static func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        strokes: [TripShareRoutePrep.StrokeSegment],
        start: CLLocationCoordinate2D?,
        end: CLLocationCoordinate2D?
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            for stroke in strokes where stroke.coordinates.count >= 2 {
                let points = stroke.coordinates.map { snapshot.point(for: $0) }
                strokePolyline(points: points, color: uiColor(for: stroke.band))
            }

            if let start {
                drawPin(
                    at: snapshot.point(for: start),
                    systemName: "flag.fill",
                    fill: .systemGreen
                )
            }
            if let end, strokes.contains(where: { $0.coordinates.count > 1 }) {
                drawPin(
                    at: snapshot.point(for: end),
                    systemName: "mappin.circle.fill",
                    fill: .systemRed
                )
            }

            drawLegend(in: CGRect(origin: .zero, size: snapshot.image.size))
        }
    }

    private static func strokePolyline(points: [CGPoint], color: UIColor) {
        guard points.count >= 2 else { return }
        let path = UIBezierPath()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        path.lineWidth = 11
        color.withAlphaComponent(0.35).setStroke()
        path.stroke()

        path.lineWidth = 5
        color.setStroke()
        path.stroke()
    }

    private static func drawPin(at point: CGPoint, systemName: String, fill: UIColor) {
        let diameter: CGFloat = 28
        let rect = CGRect(
            x: point.x - diameter / 2,
            y: point.y - diameter / 2,
            width: diameter,
            height: diameter
        )
        let circle = UIBezierPath(ovalIn: rect)
        fill.setFill()
        circle.fill()
        UIColor.white.withAlphaComponent(0.9).setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .bold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: config)?
            .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
        let symbolSize = symbol.size
        symbol.draw(
            at: CGPoint(
                x: point.x - symbolSize.width / 2,
                y: point.y - symbolSize.height / 2
            )
        )
    }

    private static func drawLegend(in bounds: CGRect) {
        let items: [(UIColor, String)] = [
            (.systemGreen, L10n.speedLegendSlow),
            (.systemYellow, L10n.speedLegendMedium),
            (.systemRed, L10n.speedLegendFast)
        ]
        let font = UIFont.systemFont(ofSize: 18, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]

        let spacing: CGFloat = 18
        let pillHeight: CGFloat = 34
        let horizontalPad: CGFloat = 14
        let dotSize: CGFloat = 10

        var totalWidth: CGFloat = horizontalPad * 2
        var itemWidths: [CGFloat] = []
        for (index, item) in items.enumerated() {
            let textWidth = (item.1 as NSString).size(withAttributes: attributes).width
            let width = dotSize + 8 + textWidth
            itemWidths.append(width)
            totalWidth += width
            if index < items.count - 1 { totalWidth += spacing }
        }

        let pillWidth = totalWidth
        let pillRect = CGRect(
            x: (bounds.width - pillWidth) / 2,
            y: bounds.height - pillHeight - 20,
            width: pillWidth,
            height: pillHeight
        )
        let pill = UIBezierPath(roundedRect: pillRect, cornerRadius: pillHeight / 2)
        UIColor.black.withAlphaComponent(0.55).setFill()
        pill.fill()

        var x = pillRect.minX + horizontalPad
        let midY = pillRect.midY
        for (index, item) in items.enumerated() {
            let dotRect = CGRect(
                x: x,
                y: midY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )
            item.0.setFill()
            UIBezierPath(ovalIn: dotRect).fill()

            let textX = x + dotSize + 8
            (item.1 as NSString).draw(
                at: CGPoint(x: textX, y: midY - font.lineHeight / 2),
                withAttributes: attributes
            )
            x += itemWidths[index] + spacing
        }
    }

    // MARK: - Card

    private static func composeCard(
        mapImage: UIImage,
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        chartSamples: SpeedChartSeries.Series,
        chartMaxKmh: Double,
        size: CGSize
    ) -> UIImage {
        let viewModel = TripDetailViewModel(trip: trip, places: places, privacyRadius: privacyRadius)
        let metrics = viewModel.summaryMetrics
        let route = viewModel.routeSummary
        let whenLine = TripShareCaption.whenLine(for: trip)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1).setFill()
            context.fill(rect)

            let mapHeight = size.height * 0.55
            let mapRect = CGRect(x: 0, y: 0, width: size.width, height: mapHeight)
            if mapImage.size.width > 0 {
                mapImage.draw(in: mapRect)
            } else {
                UIColor(white: 0.18, alpha: 1).setFill()
                context.fill(mapRect)
            }

            let contentX: CGFloat = 40
            let contentWidth = size.width - contentX * 2
            var y = mapHeight + 36

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor.white
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 24, weight: .regular),
                .foregroundColor: UIColor(white: 0.72, alpha: 1)
            ]

            (route as NSString).draw(
                in: CGRect(x: contentX, y: y, width: contentWidth, height: 48),
                withAttributes: titleAttributes
            )
            y += 52
            (whenLine as NSString).draw(
                in: CGRect(x: contentX, y: y, width: contentWidth, height: 32),
                withAttributes: bodyAttributes
            )
            y += 48

            y = drawMetrics(
                metrics,
                origin: CGPoint(x: contentX, y: y),
                width: contentWidth
            )

            if !chartSamples.samples.isEmpty {
                y += 28
                y = drawSpeedChart(
                    series: chartSamples,
                    trip: trip,
                    maxKmh: chartMaxKmh,
                    origin: CGPoint(x: contentX, y: y),
                    width: contentWidth
                )
            }

            drawBrandMark(
                in: rect,
                contentX: contentX,
                contentWidth: contentWidth
            )
        }
    }

    private static func drawBrandMark(
        in bounds: CGRect,
        contentX: CGFloat,
        contentWidth: CGFloat
    ) {
        let logoSize: CGFloat = 44
        let wordmark = "Trailhound" as NSString
        let wordAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92)
        ]
        let wordSize = wordmark.size(withAttributes: wordAttributes)
        let gap: CGFloat = 12
        let hasLogo = UIImage(named: "TrailhoundLogo") != nil
        let rowWidth = (hasLogo ? logoSize + gap : 0) + wordSize.width
        let originX = contentX + max(0, (contentWidth - rowWidth) / 2)
        let originY = bounds.height - 56 - logoSize

        if let logo = UIImage(named: "TrailhoundLogo"),
           let context = UIGraphicsGetCurrentContext() {
            let logoRect = CGRect(x: originX, y: originY, width: logoSize, height: logoSize)
            context.saveGState()
            UIBezierPath(roundedRect: logoRect, cornerRadius: logoSize * 0.22).addClip()
            logo.draw(in: logoRect)
            context.restoreGState()
        }

        let textX = hasLogo ? originX + logoSize + gap : originX
        wordmark.draw(
            at: CGPoint(
                x: textX,
                y: originY + (logoSize - wordSize.height) / 2
            ),
            withAttributes: wordAttributes
        )
    }

    private static func drawMetrics(
        _ metrics: [TripSummaryMetric],
        origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        let primaryIDs: Set<String> = ["duration", "distance", "maxSpeed"]
        let primary = metrics.filter { primaryIDs.contains($0.id) }
        let secondary = metrics.filter { !primaryIDs.contains($0.id) }

        var y = origin.y
        if !primary.isEmpty {
            y = drawMetricRow(
                primary,
                origin: CGPoint(x: origin.x, y: y),
                width: width,
                columns: primary.count
            )
            y += 16
        }
        if !secondary.isEmpty {
            y = drawMetricRow(
                secondary,
                origin: CGPoint(x: origin.x, y: y),
                width: width,
                columns: secondary.count
            )
        }
        return y
    }

    private static func drawMetricRow(
        _ metrics: [TripSummaryMetric],
        origin: CGPoint,
        width: CGFloat,
        columns: Int
    ) -> CGFloat {
        let spacing: CGFloat = 14
        let cardWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cardHeight: CGFloat = 100
        let titleFont = UIFont.systemFont(ofSize: 18, weight: .medium)
        let valueFont = UIFont.systemFont(ofSize: 28, weight: .semibold)

        for (index, metric) in metrics.enumerated() {
            let x = origin.x + CGFloat(index) * (cardWidth + spacing)
            let cardRect = CGRect(x: x, y: origin.y, width: cardWidth, height: cardHeight)
            let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 18)
            UIColor(white: 0.18, alpha: 1).setFill()
            path.fill()

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: UIColor(white: 0.65, alpha: 1)
            ]
            let valueAttributes: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: UIColor.white
            ]

            (metric.title as NSString).draw(
                in: CGRect(x: cardRect.minX + 16, y: cardRect.minY + 16, width: cardWidth - 32, height: 28),
                withAttributes: titleAttributes
            )
            (metric.formatted(progress: 1) as NSString).draw(
                in: CGRect(x: cardRect.minX + 16, y: cardRect.minY + 48, width: cardWidth - 32, height: 36),
                withAttributes: valueAttributes
            )
        }

        return origin.y + cardHeight
    }

    private static func drawSpeedChart(
        series: SpeedChartSeries.Series,
        trip: Trip,
        maxKmh: Double,
        origin: CGPoint,
        width: CGFloat
    ) -> CGFloat {
        let titleHeight: CGFloat = 36
        let chartHeight: CGFloat = 160
        let cardHeight = titleHeight + chartHeight + 40
        let cardRect = CGRect(x: origin.x, y: origin.y, width: width, height: cardHeight)
        let path = UIBezierPath(roundedRect: cardRect, cornerRadius: 20)
        UIColor(white: 0.18, alpha: 1).setFill()
        path.fill()

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: UIColor.white
        ]
        (L10n.tripSpeedChart as NSString).draw(
            at: CGPoint(x: cardRect.minX + 20, y: cardRect.minY + 16),
            withAttributes: titleAttributes
        )

        let axisFont = UIFont.systemFont(ofSize: 16, weight: .regular)
        let axisAttributes: [NSAttributedString.Key: Any] = [
            .font: axisFont,
            .foregroundColor: UIColor(white: 0.55, alpha: 1)
        ]
        let topLabel = L10n.formatSpeedKmh(maxKmh)
        let bottomLabel = L10n.formatSpeedKmh(0)
        let labelWidth: CGFloat = 70
        (topLabel as NSString).draw(
            in: CGRect(x: cardRect.minX + 12, y: cardRect.minY + titleHeight + 12, width: labelWidth, height: 22),
            withAttributes: axisAttributes
        )
        (bottomLabel as NSString).draw(
            in: CGRect(
                x: cardRect.minX + 12,
                y: cardRect.maxY - 36,
                width: labelWidth,
                height: 22
            ),
            withAttributes: axisAttributes
        )

        let plotRect = CGRect(
            x: cardRect.minX + labelWidth + 8,
            y: cardRect.minY + titleHeight + 12,
            width: cardRect.width - labelWidth - 36,
            height: chartHeight
        )
        // Span the clipped series so the chart matches the privacy-trimmed map, not full trip times.
        let chartStart = series.samples.first?.date ?? trip.startedAt
        let chartEnd = series.samples.last?.date ?? trip.endedAt ?? trip.startedAt
        drawChartPath(
            samples: series.samples,
            medianInterval: series.medianIntervalSeconds,
            tripStartedAt: chartStart,
            tripEndedAt: chartEnd,
            maxKmh: maxKmh,
            in: plotRect
        )

        return cardRect.maxY
    }

    private static func drawChartPath(
        samples: [SpeedChartSeries.Sample],
        medianInterval: TimeInterval,
        tripStartedAt: Date,
        tripEndedAt: Date,
        maxKmh: Double,
        in rect: CGRect
    ) {
        guard !samples.isEmpty else { return }

        let gapBreak = max(90.0, medianInterval * 6)
        let dateSpan = max(tripEndedAt.timeIntervalSince(tripStartedAt), 1)
        let speedMax = max(maxKmh, 1)
        let brand = UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: 1)

        func point(for sample: SpeedChartSeries.Sample) -> CGPoint {
            let xFraction = sample.date.timeIntervalSince(tripStartedAt) / dateSpan
            let yFraction = min(1, max(0, sample.speedKmh / speedMax))
            return CGPoint(
                x: rect.minX + CGFloat(xFraction) * rect.width,
                y: rect.maxY - CGFloat(yFraction) * rect.height
            )
        }

        var groups: [[CGPoint]] = []
        var current = [point(for: samples[0])]
        for index in 1..<samples.count {
            let gap = samples[index].date.timeIntervalSince(samples[index - 1].date)
            let p = point(for: samples[index])
            if gap > gapBreak {
                groups.append(current)
                current = [p]
            } else {
                current.append(p)
            }
        }
        groups.append(current)

        for points in groups where points.count >= 2 {
            let line = UIBezierPath()
            line.move(to: points[0])
            for p in points.dropFirst() {
                line.addLine(to: p)
            }

            let area = UIBezierPath()
            area.move(to: CGPoint(x: points[0].x, y: rect.maxY))
            area.addLine(to: points[0])
            for p in points.dropFirst() {
                area.addLine(to: p)
            }
            area.addLine(to: CGPoint(x: points[points.count - 1].x, y: rect.maxY))
            area.close()
            brand.withAlphaComponent(0.22).setFill()
            area.fill()

            brand.withAlphaComponent(0.35).setStroke()
            line.lineWidth = 6
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.stroke()

            brand.setStroke()
            line.lineWidth = 2.5
            line.stroke()
        }
    }

    // MARK: - Helpers

    private static func uiColor(for band: SpeedBand) -> UIColor {
        switch band {
        case .slow: return .systemGreen
        case .medium: return .systemYellow
        case .fast: return .systemRed
        }
    }

    private static func regionFor(coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coordinate in coordinates {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

// MARK: - Caption

@MainActor
enum TripShareCaption {
    static func build(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double
    ) -> String {
        let viewModel = TripDetailViewModel(trip: trip, places: places, privacyRadius: privacyRadius)
        var lines = [
            viewModel.routeSummary,
            whenLine(for: trip)
        ]

        var parts: [String] = [
            viewModel.durationText,
            viewModel.distanceText
        ]
        if let maxSpeed = viewModel.maxSpeedText {
            parts.append("\(L10n.maxAbbr) \(maxSpeed)")
        }
        if let average = viewModel.averageSpeedKmh {
            parts.append("\(L10n.avgAbbr) \(L10n.formatSpeedKmh(average))")
        }
        if let fuel = viewModel.fuelText {
            parts.append(fuel)
        }
        lines.append(parts.joined(separator: " · "))
        return lines.joined(separator: "\n")
    }

    static func whenLine(for trip: Trip) -> String {
        let date = DateFormatters.tripDateOnly.string(from: trip.startedAt)
        let start = DateFormatters.tripTime.string(from: trip.startedAt)
        if let endedAt = trip.endedAt {
            let end = DateFormatters.tripTime.string(from: endedAt)
            return L10n.shareCaptionWhenRange(date: date, start: start, end: end)
        }
        return L10n.shareCaptionWhenStart(date: date, start: start)
    }
}
