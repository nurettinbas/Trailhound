import MapKit
import SwiftUI
import UIKit

@MainActor
enum TripShareCardRenderer {
    static func render(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        size: CGSize = CGSize(width: 600, height: 400)
    ) async -> UIImage? {
        let routePieces = RouteDisplayPath.displaySegmentCoordinates(
            trip: trip,
            privacyRadiusMeters: privacyRadius,
            places: places
        )
        let coordinates = routePieces.flatMap { $0 }
        guard !coordinates.isEmpty else { return renderStatsOnly(trip: trip, places: places, privacyRadius: privacyRadius, size: size) }

        let region = regionFor(coordinates: coordinates)
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = CGSize(width: size.width, height: size.height * 0.62)
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)
        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await snapshotter.start()
        } catch {
            return renderStatsOnly(trip: trip, places: places, privacyRadius: privacyRadius, size: size)
        }

        let mapImage = drawRoute(on: snapshot, pieces: routePieces)
        return composeCard(
            mapImage: mapImage,
            trip: trip,
            places: places,
            privacyRadius: privacyRadius,
            size: size
        )
    }

    /// Each piece gets its own sub-path, so a real GPS gap stays a gap instead of being
    /// bridged by a straight line through unrecorded ground.
    private static func drawRoute(
        on snapshot: MKMapSnapshotter.Snapshot,
        pieces: [[CLLocationCoordinate2D]]
    ) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: snapshot.image.size)
        return renderer.image { _ in
            snapshot.image.draw(at: .zero)

            let path = UIBezierPath()
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.systemBlue.setStroke()

            for piece in pieces where piece.count >= 2 {
                for (index, coordinate) in piece.enumerated() {
                    let point = snapshot.point(for: coordinate)
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            path.stroke()
        }
    }

    private static func composeCard(
        mapImage: UIImage,
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        size: CGSize
    ) -> UIImage {
        let route = TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
        let duration = trip.duration.map(DateFormatters.formatDuration) ?? "—"
        let distance = DateFormatters.formatDistance(trip.distanceMeters)
        let date = DateFormatters.tripDate.string(from: trip.startedAt)

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            let rect = CGRect(origin: .zero, size: size)
            UIColor.secondarySystemBackground.setFill()
            context.fill(rect)

            let mapHeight = size.height * 0.62
            mapImage.draw(in: CGRect(x: 0, y: 0, width: size.width, height: mapHeight))

            let textRect = CGRect(x: 20, y: mapHeight + 16, width: size.width - 40, height: size.height - mapHeight - 24)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
            let bodyAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.secondaryLabel,
                .paragraphStyle: paragraph
            ]

            var y = textRect.minY
            (date as NSString).draw(in: CGRect(x: textRect.minX, y: y, width: textRect.width, height: 24), withAttributes: bodyAttributes)
            y += 26
            (route as NSString).draw(in: CGRect(x: textRect.minX, y: y, width: textRect.width, height: 28), withAttributes: titleAttributes)
            y += 34
            let stats = "\(duration) · \(distance)"
            (stats as NSString).draw(in: CGRect(x: textRect.minX, y: y, width: textRect.width, height: 24), withAttributes: bodyAttributes)
        }
    }

    private static func renderStatsOnly(
        trip: Trip,
        places: [SavedPlace],
        privacyRadius: Double,
        size: CGSize
    ) -> UIImage {
        composeCard(
            mapImage: UIImage(),
            trip: trip,
            places: places,
            privacyRadius: privacyRadius,
            size: size
        )
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

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.01, (maxLon - minLon) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
