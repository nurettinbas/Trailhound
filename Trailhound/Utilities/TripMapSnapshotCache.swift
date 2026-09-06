import MapKit
import SwiftUI
import UIKit

/// Light vs dark MapKit snapshot. Disk and memory keep both; share cards stay dark separately.
enum MapSnapshotAppearance: String, Hashable, CaseIterable, Sendable {
    case light
    case dark

    init(_ colorScheme: ColorScheme) {
        self = colorScheme == .dark ? .dark : .light
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light: .light
        case .dark: .dark
        }
    }

    func fileName(for tripID: UUID) -> String {
        "\(tripID.uuidString)-\(rawValue).jpg"
    }

    static func fileNames(for tripID: UUID) -> [String] {
        allCases.map { $0.fileName(for: tripID) }
    }

    /// Pre-theme files were `{uuid}.jpg` with whatever style happened to render first.
    static func isLegacyUnstyledFileName(_ name: String) -> Bool {
        guard name.lowercased().hasSuffix(".jpg") else { return false }
        let stem = String(name.dropLast(4))
        return UUID(uuidString: stem) != nil
    }
}

@MainActor
final class TripMapSnapshotCache {
    static let shared = TripMapSnapshotCache()

    private struct SnapshotKey: Hashable {
        let tripID: UUID
        let appearance: MapSnapshotAppearance
    }

    private var memoryCache: [SnapshotKey: UIImage] = [:]
    private var inFlight: [SnapshotKey: Task<UIImage?, Never>] = [:]

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
        let directory = cacheDirectory
        Self.diskQueue.async {
            Self.purgeLegacyUnstyledSnapshots(in: directory)
        }
    }

    /// Memory hit only — never touches disk, so it is safe to call while scrolling.
    func cachedImage(for tripID: UUID, appearance: MapSnapshotAppearance) -> UIImage? {
        memoryCache[SnapshotKey(tripID: tripID, appearance: appearance)]
    }

    func snapshot(
        for trip: Trip,
        appearance: MapSnapshotAppearance,
        size: CGSize = CGSize(width: 88, height: 88)
    ) async -> UIImage? {
        let key = SnapshotKey(tripID: trip.id, appearance: appearance)
        if let cached = memoryCache[key] {
            return cached
        }

        if let existingTask = inFlight[key] {
            return await existingTask.value
        }

        // Reading and decoding the JPEG on the main actor stalled scrolling once the list had
        // more than a handful of trips.
        if let stored = await Self.readImage(at: fileURL(for: trip.id, appearance: appearance)) {
            memoryCache[key] = stored
            return stored
        }

        let pieces = RouteDisplayPath.displaySegmentCoordinates(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        // The decimated coordinates are all the renderer needs, so drop the faulted points rather
        // than keeping every scrolled row's GPS history alive for the rest of the session.
        trip.invalidatePointCaches()
        let task = Task<UIImage?, Never> { @MainActor in
            defer { inFlight[key] = nil }
            guard pieces.contains(where: { $0.count >= 2 }) else { return nil }
            guard let image = await renderSnapshot(
                pieces: pieces,
                size: size,
                appearance: appearance
            ) else { return nil }
            store(image, for: key)
            return image
        }

        inFlight[key] = task
        return await task.value
    }

    func remove(for tripID: UUID) {
        for appearance in MapSnapshotAppearance.allCases {
            let key = SnapshotKey(tripID: tripID, appearance: appearance)
            memoryCache.removeValue(forKey: key)
            inFlight[key]?.cancel()
            inFlight.removeValue(forKey: key)
        }
        let urls = MapSnapshotAppearance.allCases.map { fileURL(for: tripID, appearance: $0) }
            + [legacyFileURL(for: tripID)]
        Self.diskQueue.async {
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func fileURL(for tripID: UUID, appearance: MapSnapshotAppearance) -> URL {
        cacheDirectory.appendingPathComponent(appearance.fileName(for: tripID))
    }

    private func legacyFileURL(for tripID: UUID) -> URL {
        cacheDirectory.appendingPathComponent("\(tripID.uuidString).jpg")
    }

    private func store(_ image: UIImage, for key: SnapshotKey) {
        memoryCache[key] = image
        let url = fileURL(for: key.tripID, appearance: key.appearance)
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

    nonisolated private static func purgeLegacyUnstyledSnapshots(in directory: URL) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names where MapSnapshotAppearance.isLegacyUnstyledFileName(name) {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    private func renderSnapshot(
        pieces: [[CLLocationCoordinate2D]],
        size: CGSize,
        appearance: MapSnapshotAppearance
    ) async -> UIImage? {
        guard let region = mapRegion(for: pieces.flatMap { $0 }) else { return nil }

        let scale = UIScreen.main.scale
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = scale
        options.mapType = .standard
        options.traitCollection = UITraitCollection { mutableTraits in
            mutableTraits.userInterfaceStyle = appearance.userInterfaceStyle
            mutableTraits.displayScale = scale
        }

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
