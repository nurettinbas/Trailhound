import MapKit
import UIKit

@MainActor
final class TripMapSnapshotCache {
    static let shared = TripMapSnapshotCache()

    private var memoryCache: [UUID: UIImage] = [:]
    private var inFlight: [UUID: Task<UIImage?, Never>] = [:]

    /// Resolved once. As a computed property this issued a `fileExists` syscall for every row
    /// that scrolled into view.
    private let cacheDirectory: URL

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = appSupport.appendingPathComponent("TripMapSnapshots", isDirectory: true)
        if !fileManager.fileExists(atPath: cacheDirectory.path) {
            try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    /// Memory hit only — never touches disk, so it is safe to call while scrolling.
    func cachedImage(for tripID: UUID) -> UIImage? {
        memoryCache[tripID]
    }

    func snapshot(for trip: Trip, size: CGSize = CGSize(width: 88, height: 88)) async -> UIImage? {
        if let cached = memoryCache[trip.id] {
            return cached
        }

        if let existingTask = inFlight[trip.id] {
            return await existingTask.value
        }

        // Reading and decoding the JPEG on the main actor stalled scrolling once the list had
        // more than a handful of trips.
        if let stored = await Self.readImage(at: fileURL(for: trip.id)) {
            memoryCache[trip.id] = stored
            return stored
        }

        let pieces = RouteDisplayPath.displaySegmentCoordinates(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        // The decimated coordinates are all the renderer needs, so drop the faulted points rather
        // than keeping every scrolled row's GPS history alive for the rest of the session.
        trip.invalidatePointCaches()
        let task = Task<UIImage?, Never> { @MainActor in
            defer { inFlight[trip.id] = nil }
            guard pieces.contains(where: { $0.count >= 2 }) else { return nil }
            guard let image = await renderSnapshot(pieces: pieces, size: size) else { return nil }
            store(image, for: trip.id)
            return image
        }

        inFlight[trip.id] = task
        return await task.value
    }

    func remove(for tripID: UUID) {
        memoryCache.removeValue(forKey: tripID)
        inFlight[tripID]?.cancel()
        inFlight.removeValue(forKey: tripID)
        let url = fileURL(for: tripID)
        Self.diskQueue.async {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(for tripID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(tripID.uuidString).jpg")
    }

    private func store(_ image: UIImage, for tripID: UUID) {
        memoryCache[tripID] = image
        let url = fileURL(for: tripID)
        Self.diskQueue.async {
            guard let data = image.jpegData(compressionQuality: 0.85) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    /// One serial queue for every file operation. Besides keeping encode/decode off the main
    /// actor, FIFO ordering means a delete can never be overtaken by an in-flight write and
    /// leave a snapshot behind for a trip the user removed.
    private static let diskQueue = DispatchQueue(
        label: "com.trailhound.TripMapSnapshotCache.disk",
        qos: .utility
    )

    private static func readImage(at url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            diskQueue.async {
                guard let data = try? Data(contentsOf: url) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: UIImage(data: data))
            }
        }
    }

    private func renderSnapshot(pieces: [[CLLocationCoordinate2D]], size: CGSize) async -> UIImage? {
        guard let region = mapRegion(for: pieces.flatMap { $0 }) else { return nil }

        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = UIScreen.main.scale

        let snapshotter = MKMapSnapshotter(options: options)

        return await withCheckedContinuation { continuation in
            snapshotter.start { snapshot, _ in
                guard let snapshot else {
                    continuation.resume(returning: nil)
                    return
                }

                let image = UIGraphicsImageRenderer(size: size).image { _ in
                    snapshot.image.draw(at: .zero)

                    // One sub-path per piece: real gaps must not be bridged by a straight line.
                    let path = UIBezierPath()
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
                    UIColor.systemBlue.setStroke()
                    path.lineWidth = 2.5
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    path.stroke()
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func mapRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = coordinates.first else { return nil }

        var minLat = first.latitude
        var maxLat = first.latitude
        var minLon = first.longitude
        var maxLon = first.longitude

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
            latitudeDelta: max(0.008, (maxLat - minLat) * 1.5),
            longitudeDelta: max(0.008, (maxLon - minLon) * 1.5)
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}
