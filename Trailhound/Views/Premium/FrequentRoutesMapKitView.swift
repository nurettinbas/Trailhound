import MapKit
import SwiftUI

final class FrequentRouteArcOverlay: NSObject, MKOverlay {
    let start: CLLocationCoordinate2D
    let end: CLLocationCoordinate2D
    let count: Int
    let isBusiness: Bool
    let pairKey: String
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(aggregate: FrequentRouteAggregate) {
        start = aggregate.startCoordinate
        end = aggregate.endCoordinate
        count = aggregate.count
        isBusiness = aggregate.isBusinessHeavy
        pairKey = aggregate.pairKey
        let startItem = MKMapPoint(start)
        let endItem = MKMapPoint(end)
        boundingMapRect = MKMapRect(
            x: min(startItem.x, endItem.x),
            y: min(startItem.y, endItem.y),
            width: max(abs(startItem.x - endItem.x), 1),
            height: max(abs(startItem.y - endItem.y), 1)
        ).insetBy(dx: -80_000, dy: -80_000)
        coordinate = CLLocationCoordinate2D(
            latitude: (start.latitude + end.latitude) / 2,
            longitude: (start.longitude + end.longitude) / 2
        )
        super.init()
    }
}

final class FrequentRouteArcRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FrequentRouteArcOverlay else { return }
        let start = point(for: MKMapPoint(overlay.start))
        let end = point(for: MKMapPoint(overlay.end))
        let controlCoord = FrequentRouteAggregateService.arcControlPoint(start: overlay.start, end: overlay.end)
        let control = point(for: MKMapPoint(controlCoord))
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        let weight = CGFloat(1.5 + log2(Double(max(overlay.count, 1))))
        context.setLineWidth(weight * 1.8 / zoomScale)
        context.setLineCap(.round)
        let color = overlay.isBusiness
            ? UIColor(red: 0.61, green: 0.50, blue: 0.91, alpha: 0.85)
            : UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: 0.85)
        context.setStrokeColor(color.cgColor)
        context.addPath(path)
        context.strokePath()
    }
}

final class FrequentRoutesHeatmapOverlay: NSObject, MKOverlay {
    let samples: [CLLocationCoordinate2D]
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(samples: [CLLocationCoordinate2D]) {
        self.samples = samples
        var rect = MKMapRect.null
        for sample in samples {
            let point = MKMapPoint(sample)
            let cell = MKMapRect(x: point.x - 40_000, y: point.y - 40_000, width: 80_000, height: 80_000)
            rect = rect.union(cell)
        }
        boundingMapRect = rect.isNull ? MKMapRect.world : rect
        coordinate = samples.first ?? CLLocationCoordinate2D()
        super.init()
    }
}

final class FrequentRoutesHeatmapRenderer: MKOverlayRenderer {
    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        overlay.boundingMapRect.intersects(mapRect)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? FrequentRoutesHeatmapOverlay else { return }
        // Zoomed in: arcs carry the story, heatmap eases off. Zoomed out: cells merge.
        let fade = min(1, max(0, CGFloat(0.00012 / max(zoomScale, 0.00001))))
        guard fade > 0.04 else { return }
        let cell = max(24.0 / zoomScale, 8)
        var grid: [String: Int] = [:]
        for sample in overlay.samples {
            let mapPoint = MKMapPoint(sample)
            guard mapRect.contains(mapPoint) || mapRect.intersects(
                MKMapRect(x: mapPoint.x - cell, y: mapPoint.y - cell, width: cell * 2, height: cell * 2)
            ) else { continue }
            let point = point(for: mapPoint)
            let key = "\(Int(point.x / cell))|\(Int(point.y / cell))"
            grid[key, default: 0] += 1
        }
        let maxCount = max(grid.values.max() ?? 1, 1)
        for (key, count) in grid {
            let parts = key.split(separator: "|")
            guard parts.count == 2,
                  let gx = Int(parts[0]),
                  let gy = Int(parts[1]) else { continue }
            let rect = CGRect(x: CGFloat(gx) * cell, y: CGFloat(gy) * cell, width: cell, height: cell)
            let t = CGFloat(count) / CGFloat(maxCount)
            context.setFillColor(
                UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: (0.08 + 0.32 * t) * fade).cgColor
            )
            context.fillEllipse(in: rect.insetBy(dx: cell * 0.1, dy: cell * 0.1))
        }
    }
}

struct FrequentRoutesMapKitView: UIViewRepresentable {
    var aggregates: [FrequentRouteAggregate]
    var isDark: Bool
    var onSelect: ((FrequentRouteAggregate) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.showsScale = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.didTapMap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        applyStyle(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        applyStyle(map)
        let top = FrequentRouteOverlayBudget.topAggregates(aggregates)
        context.coordinator.replaceOverlays(on: map, aggregates: top)
    }

    private func applyStyle(_ map: MKMapView) {
        map.preferredConfiguration = MKStandardMapConfiguration(
            elevationStyle: .flat,
            emphasisStyle: isDark ? .muted : .standard
        )
        if isDark {
            map.overrideUserInterfaceStyle = .dark
        } else {
            map.overrideUserInterfaceStyle = .light
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onSelect: ((FrequentRouteAggregate) -> Void)?
        private var overlaysInstalled = false
        private var lastKeys: [String] = []
        private var byKey: [String: FrequentRouteAggregate] = [:]

        init(onSelect: ((FrequentRouteAggregate) -> Void)?) {
            self.onSelect = onSelect
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func didTapMap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            let tap = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            var best: (FrequentRouteAggregate, CLLocationDistance)?
            for aggregate in byKey.values where aggregate.hasValidCoordinates {
                let samples = FrequentRouteAggregateService.bezierSamples(
                    start: aggregate.startCoordinate,
                    end: aggregate.endCoordinate
                )
                let nearest = samples.map {
                    tap.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                }.min() ?? .greatestFiniteMagnitude
                if nearest < 18_000, nearest < (best?.1 ?? .greatestFiniteMagnitude) {
                    best = (aggregate, nearest)
                }
            }
            if let best {
                onSelect?(best.0)
            }
        }

        func replaceOverlays(on map: MKMapView, aggregates: [FrequentRouteAggregate]) {
            let keys = aggregates.map(\.pairKey)
            guard keys != lastKeys else { return }
            lastKeys = keys
            byKey = Dictionary(uniqueKeysWithValues: aggregates.map { ($0.pairKey, $0) })
            map.removeOverlays(map.overlays)
            var samples: [CLLocationCoordinate2D] = []
            samples.reserveCapacity(aggregates.count * FrequentRouteOverlayBudget.heatmapSamplesPerArc)
            for aggregate in aggregates where aggregate.hasValidCoordinates {
                map.addOverlay(FrequentRouteArcOverlay(aggregate: aggregate), level: .aboveRoads)
                samples.append(contentsOf: FrequentRouteAggregateService.bezierSamples(
                    start: aggregate.startCoordinate,
                    end: aggregate.endCoordinate
                ))
            }
            if !samples.isEmpty {
                map.addOverlay(FrequentRoutesHeatmapOverlay(samples: samples), level: .aboveLabels)
            }
            if let first = aggregates.first, first.hasValidCoordinates {
                let coords = aggregates.flatMap { [$0.startCoordinate, $0.endCoordinate] }
                map.setVisibleMapRect(rect(for: coords), edgePadding: UIEdgeInsets(top: 48, left: 36, bottom: 120, right: 36), animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is FrequentRoutesHeatmapOverlay {
                return FrequentRoutesHeatmapRenderer(overlay: overlay)
            }
            return FrequentRouteArcRenderer(overlay: overlay)
        }

        private func rect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
            var rect = MKMapRect.null
            for coordinate in coordinates {
                let point = MKMapPoint(coordinate)
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
            }
            return rect.insetBy(dx: -120_000, dy: -120_000)
        }
    }
}

/// Static MapKit snapshot of the top frequent-route arcs. Never walks GPS polylines.
@MainActor
final class FrequentRoutesSnapshotCache {
    static let shared = FrequentRoutesSnapshotCache()

    private var memory: [String: UIImage] = [:]
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let cacheDirectory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDirectory = support.appendingPathComponent("FrequentRouteSnapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func snapshot(
        start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D,
        count: Int,
        isBusiness: Bool,
        size: CGSize = CGSize(width: 280, height: 160)
    ) async -> UIImage? {
        await Self.render(
            arcs: [
                SnapshotArc(start: start, end: end, isBusiness: isBusiness, count: count)
            ],
            size: size
        )
    }

    func snapshot(
        for aggregates: [FrequentRouteAggregate],
        size: CGSize = CGSize(width: 320, height: 140)
    ) async -> UIImage? {
        let top = FrequentRouteOverlayBudget.topAggregates(aggregates).filter(\.hasValidCoordinates)
        guard !top.isEmpty else { return nil }
        let key = top.prefix(8).map { "\($0.pairKey):\($0.count)" }.joined(separator: "|")
        if let cached = memory[key] { return cached }
        if let existing = inFlight[key] { return await existing.value }
        let diskURL = cacheDirectory.appendingPathComponent("\(Self.stableName(for: key)).jpg")
        if let data = try? Data(contentsOf: diskURL), let image = UIImage(data: data) {
            memory[key] = image
            return image
        }
        let copies = top.prefix(8).map { SnapshotArc(from: $0) }
        let task = Task<UIImage?, Never> {
            await Self.render(arcs: copies, size: size)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            memory[key] = image
            if let data = image.jpegData(compressionQuality: 0.72) {
                try? data.write(to: diskURL, options: .atomic)
            }
        }
        return image
    }

    func dropMemory() {
        memory.removeAll(keepingCapacity: true)
    }

    private static func stableName(for key: String) -> String {
        var hash: UInt64 = 5381
        for byte in key.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    private struct SnapshotArc {
        let start: CLLocationCoordinate2D
        let end: CLLocationCoordinate2D
        let isBusiness: Bool
        let count: Int

        init(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D, isBusiness: Bool, count: Int) {
            self.start = start
            self.end = end
            self.isBusiness = isBusiness
            self.count = count
        }

        init(from aggregate: FrequentRouteAggregate) {
            start = aggregate.startCoordinate
            end = aggregate.endCoordinate
            isBusiness = aggregate.isBusinessHeavy
            count = aggregate.count
        }
    }

    private static func render(arcs: [SnapshotArc], size: CGSize) async -> UIImage? {
        let coordinates = arcs.flatMap { [$0.start, $0.end] }
        guard coordinates.count >= 2 else { return nil }
        let options = MKMapSnapshotter.Options()
        options.size = size
        options.mapType = .standard
        options.pointOfInterestFilter = .excludingAll
        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 1, height: 1))
        }
        options.mapRect = rect.insetBy(dx: -80_000, dy: -80_000)
        let snapshot: MKMapSnapshotter.Snapshot
        do {
            snapshot = try await MKMapSnapshotter(options: options).start()
        } catch {
            return nil
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            snapshot.image.draw(in: CGRect(origin: .zero, size: size))
            let cg = ctx.cgContext
            cg.setLineCap(.round)
            for arc in arcs {
                let start = snapshot.point(for: arc.start)
                let end = snapshot.point(for: arc.end)
                let controlCoord = FrequentRouteAggregateService.arcControlPoint(start: arc.start, end: arc.end)
                let control = snapshot.point(for: controlCoord)
                let path = CGMutablePath()
                path.move(to: start)
                path.addQuadCurve(to: end, control: control)
                cg.addPath(path)
                let alpha: CGFloat = 0.45 + min(0.4, CGFloat(log2(Double(max(arc.count, 1)))) * 0.08)
                let color = arc.isBusiness
                    ? UIColor(red: 0.61, green: 0.50, blue: 0.91, alpha: alpha)
                    : UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: alpha)
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(2.4 + CGFloat(log2(Double(max(arc.count, 1)))))
                cg.strokePath()
            }
        }
    }
}
