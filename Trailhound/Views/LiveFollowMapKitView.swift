import MapKit
import SwiftUI
import UIKit

/// MapKit host for live follow — display-link camera writes, incremental polylines, pins + puck.
struct LiveFollowMapKitView: UIViewRepresentable {
    var session: LiveFollowSession
    var isFollowing: Bool
    var interactionEnabled: Bool
    var uses3DElevation: Bool
    var segments: [LiveFollowPolylineSegment]
    var pins: [LiveFollowMapPin]
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var puckRevealed: Bool
    var isMoving: Bool
    var onUserBreakFollow: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onUserBreakFollow: onUserBreakFollow)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.showsCompass = false
        map.showsScale = false
        map.showsTraffic = false
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        map.isZoomEnabled = true
        map.isScrollEnabled = true
        map.pointOfInterestFilter = .includingAll
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKStandardMapConfiguration(
                elevationStyle: uses3DElevation ? .realistic : .flat
            )
        }
        context.coordinator.mapView = map
        context.coordinator.bindSession()
        context.coordinator.installGestureBreak(on: map)
        if let pose = session.pose {
            context.coordinator.applyCamera(pose, on: map)
        }
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.session = session
        context.coordinator.isFollowing = isFollowing
        context.coordinator.onUserBreakFollow = onUserBreakFollow
        context.coordinator.bindSession()
        mapView.isScrollEnabled = interactionEnabled
        mapView.isZoomEnabled = interactionEnabled
        mapView.isRotateEnabled = interactionEnabled
        mapView.isPitchEnabled = interactionEnabled

        if #available(iOS 16.0, *) {
            let elevation: MKStandardMapConfiguration.ElevationStyle = uses3DElevation ? .realistic : .flat
            if let config = mapView.preferredConfiguration as? MKStandardMapConfiguration {
                if config.elevationStyle != elevation {
                    mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: elevation)
                }
            } else {
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: elevation)
            }
        }

        context.coordinator.syncPolylines(segments, on: mapView)
        context.coordinator.syncPins(pins, on: mapView)
        context.coordinator.syncPuck(
            coordinate: session.vehicleCoordinate,
            revealed: puckRevealed,
            photo: vehiclePhoto,
            systemImage: vehicleSystemImage,
            isMoving: isMoving,
            on: mapView
        )
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var session: LiveFollowSession
        var isFollowing = true
        var onUserBreakFollow: () -> Void
        weak var mapView: MKMapView?
        private var isApplyingCamera = false
        private var polylineByID: [String: MKPolyline] = [:]
        private var pinAnnotations: [String: LiveFollowPinAnnotation] = [:]
        private var puckAnnotation: LiveFollowPuckAnnotation?
        private var gestureRecognizersInstalled = false

        init(session: LiveFollowSession, onUserBreakFollow: @escaping () -> Void) {
            self.session = session
            self.onUserBreakFollow = onUserBreakFollow
        }

        func bindSession() {
            session.onPoseWrite = { [weak self] pose, vehicle in
                guard let self, let map = self.mapView else { return }
                if self.isFollowing {
                    self.applyCamera(pose, on: map)
                }
                if let vehicle, let puck = self.puckAnnotation {
                    puck.coordinate = vehicle
                }
            }
        }

        func installGestureBreak(on map: MKMapView) {
            guard !gestureRecognizersInstalled else { return }
            gestureRecognizersInstalled = true
            let pan = UIPanGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 2
            map.addGestureRecognizer(pan)
            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            pinch.delegate = self
            map.addGestureRecognizer(pinch)
            let rotate = UIRotationGestureRecognizer(target: self, action: #selector(userGesture(_:)))
            rotate.delegate = self
            map.addGestureRecognizer(rotate)
        }

        @objc private func userGesture(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard !isApplyingCamera else { return }
            onUserBreakFollow()
        }

        func applyCamera(_ pose: LiveFollowCamera.Pose, on map: MKMapView) {
            let camera = MKMapCamera(
                lookingAtCenter: pose.center,
                fromDistance: pose.distanceMeters,
                pitch: pose.pitchDegrees,
                heading: pose.headingDegrees
            )
            isApplyingCamera = true
            map.setCamera(camera, animated: false)
            isApplyingCamera = false
        }

        func syncPolylines(_ segments: [LiveFollowPolylineSegment], on map: MKMapView) {
            // Halo + solid overlays share the same coordinate run (two IDs per segment).
            var nextIDs = Set<String>()
            for segment in segments {
                nextIDs.insert(Self.haloID(segment.id))
                nextIDs.insert(Self.solidID(segment.id))
            }
            for (id, polyline) in polylineByID where !nextIDs.contains(id) {
                map.removeOverlay(polyline)
                polylineByID.removeValue(forKey: id)
            }
            for segment in segments {
                var coords = segment.coordinates
                guard coords.count >= 2 else { continue }
                upsertPolyline(
                    id: Self.haloID(segment.id),
                    coordinates: &coords,
                    on: map
                )
                upsertPolyline(
                    id: Self.solidID(segment.id),
                    coordinates: &coords,
                    on: map
                )
            }
        }

        private static func haloID(_ segmentID: String) -> String { "\(segmentID)#halo" }
        private static func solidID(_ segmentID: String) -> String { "\(segmentID)#solid" }

        private func upsertPolyline(id: String, coordinates: inout [CLLocationCoordinate2D], on map: MKMapView) {
            let count = coordinates.count
            if let existing = polylineByID[id] {
                let existingCount = existing.pointCount
                let tipMoved: Bool = {
                    guard existingCount > 0, count > 0 else { return true }
                    let lastExisting = existing.points()[existingCount - 1].coordinate
                    let lastNew = coordinates[count - 1]
                    return abs(lastExisting.latitude - lastNew.latitude) > 1e-9
                        || abs(lastExisting.longitude - lastNew.longitude) > 1e-9
                }()
                if existingCount == count, !tipMoved { return }
                map.removeOverlay(existing)
            }
            let polyline = MKPolyline(coordinates: &coordinates, count: count)
            polylineByID[id] = polyline
            map.addOverlay(polyline, level: .aboveRoads)
        }

        func syncPins(_ pins: [LiveFollowMapPin], on map: MKMapView) {
            let nextIDs = Set(pins.map(\.id))
            for (id, annotation) in pinAnnotations where !nextIDs.contains(id) {
                map.removeAnnotation(annotation)
                pinAnnotations.removeValue(forKey: id)
            }
            for pin in pins {
                if let existing = pinAnnotations[pin.id] {
                    if existing.coordinate.latitude != pin.latitude
                        || existing.coordinate.longitude != pin.longitude
                    {
                        existing.coordinate = pin.coordinate
                    }
                    existing.kind = pin.kind
                } else {
                    let annotation = LiveFollowPinAnnotation(pin: pin)
                    pinAnnotations[pin.id] = annotation
                    map.addAnnotation(annotation)
                }
            }
        }

        func syncPuck(
            coordinate: CLLocationCoordinate2D?,
            revealed: Bool,
            photo: UIImage?,
            systemImage: String,
            isMoving: Bool,
            on map: MKMapView
        ) {
            guard revealed, let coordinate else {
                if let puckAnnotation {
                    map.removeAnnotation(puckAnnotation)
                    self.puckAnnotation = nil
                }
                return
            }
            if let puckAnnotation {
                puckAnnotation.coordinate = coordinate
                puckAnnotation.vehiclePhoto = photo
                puckAnnotation.vehicleSystemImage = systemImage
                puckAnnotation.isMoving = isMoving
                if let view = map.view(for: puckAnnotation) as? LiveFollowPuckAnnotationView {
                    view.apply(puckAnnotation)
                }
            } else {
                let annotation = LiveFollowPuckAnnotation(
                    coordinate: coordinate,
                    vehiclePhoto: photo,
                    vehicleSystemImage: systemImage,
                    isMoving: isMoving
                )
                puckAnnotation = annotation
                map.addAnnotation(annotation)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let isHalo = polylineByID.first(where: { $0.value === polyline })?.key.hasSuffix("#halo") == true
            let renderer = MKPolylineRenderer(polyline: polyline)
            if isHalo {
                renderer.strokeColor = UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 0.35)
                renderer.lineWidth = 14
            } else {
                renderer.strokeColor = UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 1)
                renderer.lineWidth = 6
            }
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let puck = annotation as? LiveFollowPuckAnnotation {
                let reuse = "live-follow-puck"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? LiveFollowPuckAnnotationView)
                    ?? LiveFollowPuckAnnotationView(annotation: puck, reuseIdentifier: reuse)
                view.apply(puck)
                return view
            }
            if let pin = annotation as? LiveFollowPinAnnotation {
                let reuse = "live-follow-pin-\(pin.kind.rawValue)"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? LiveFollowPinAnnotationView)
                    ?? LiveFollowPinAnnotationView(annotation: pin, reuseIdentifier: reuse)
                view.apply(pin)
                return view
            }
            return nil
        }
    }
}

extension LiveFollowMapKitView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

// MARK: - Annotations

final class LiveFollowPuckAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var isMoving: Bool

    init(
        coordinate: CLLocationCoordinate2D,
        vehiclePhoto: UIImage?,
        vehicleSystemImage: String,
        isMoving: Bool
    ) {
        self.coordinate = coordinate
        self.vehiclePhoto = vehiclePhoto
        self.vehicleSystemImage = vehicleSystemImage
        self.isMoving = isMoving
    }
}

final class LiveFollowPinAnnotation: NSObject, MKAnnotation {
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var kind: LiveFollowMapPinKind

    init(pin: LiveFollowMapPin) {
        self.coordinate = pin.coordinate
        self.kind = pin.kind
    }
}

final class LiveFollowPuckAnnotationView: MKAnnotationView {
    private let circleSize: CGFloat = 56
    private let chevronSize = CGSize(width: 52, height: 38)
    private let chevronOverlap: CGFloat = 18
    private let photoBorder: CGFloat = 5
    private let photoGap: CGFloat = 3

    private let badge = UIView()
    private let photoView = UIImageView()
    private let symbolView = UIImageView()
    private let chevron = UIImageView()
    private let pulse = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        centerOffset = CGPoint(x: 0, y: -circleSize / 2 + 8)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        let frameHeight = circleSize + chevronSize.height - chevronOverlap + 14
        let frameWidth = max(circleSize, chevronSize.width) + 24
        frame = CGRect(x: 0, y: 0, width: frameWidth, height: frameHeight)

        pulse.backgroundColor = UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 0.28)
        pulse.layer.cornerRadius = (circleSize + 22) / 2
        addSubview(pulse)

        badge.backgroundColor = UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 1)
        badge.layer.cornerRadius = circleSize / 2
        badge.layer.borderColor = UIColor.white.cgColor
        badge.layer.borderWidth = photoBorder
        badge.clipsToBounds = true
        addSubview(badge)

        photoView.contentMode = .scaleAspectFill
        photoView.clipsToBounds = true
        badge.addSubview(photoView)

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = .white
        badge.addSubview(symbolView)

        chevron.contentMode = .scaleAspectFit
        chevron.image = Self.makeChevronImage(size: chevronSize)
        addSubview(chevron)

        let side = circleSize
        badge.frame = CGRect(x: (frameWidth - side) / 2, y: 0, width: side, height: side)
        let inset = photoBorder + photoGap
        photoView.frame = badge.bounds.insetBy(dx: inset, dy: inset)
        photoView.layer.cornerRadius = photoView.bounds.width / 2
        symbolView.frame = photoView.frame
        chevron.frame = CGRect(
            x: (frameWidth - chevronSize.width) / 2,
            y: side - chevronOverlap,
            width: chevronSize.width,
            height: chevronSize.height
        )
        pulse.frame = CGRect(
            x: badge.frame.midX - (side + 22) / 2,
            y: badge.frame.midY - (side + 22) / 2,
            width: side + 22,
            height: side + 22
        )
        pulse.isHidden = true
    }

    func apply(_ annotation: LiveFollowPuckAnnotation) {
        if let photo = annotation.vehiclePhoto {
            photoView.image = photo
            photoView.isHidden = false
            symbolView.isHidden = true
        } else {
            photoView.isHidden = true
            symbolView.isHidden = false
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            symbolView.image = UIImage(systemName: annotation.vehicleSystemImage, withConfiguration: config)
        }
        setMoving(annotation.isMoving)
    }

    private func setMoving(_ moving: Bool) {
        pulse.layer.removeAllAnimations()
        guard moving else {
            pulse.isHidden = true
            return
        }
        pulse.isHidden = false
        pulse.alpha = 0.55
        pulse.transform = .identity
        UIView.animate(
            withDuration: 1.2,
            delay: 0,
            options: [.repeat, .autoreverse, .curveEaseInOut],
            animations: {
                self.pulse.alpha = 0.15
                self.pulse.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
            }
        )
    }

    private static func makeChevronImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let w = size.width
            let h = size.height
            let points = [
                CGPoint(x: w * 0.50, y: h * 0.04),
                CGPoint(x: w * 0.97, y: h * 0.92),
                CGPoint(x: w * 0.50, y: h * 0.72),
                CGPoint(x: w * 0.03, y: h * 0.92)
            ]
            let radius = min(w, h) * 0.12
            let cg = CGMutablePath()
            cg.move(to: CGPoint(x: (points[3].x + points[0].x) / 2, y: (points[3].y + points[0].y) / 2))
            for index in points.indices {
                let current = points[index]
                let next = points[(index + 1) % points.count]
                cg.addArc(tangent1End: current, tangent2End: next, radius: radius)
            }
            cg.closeSubpath()
            let rounded = UIBezierPath(cgPath: cg)

            let colors = [
                UIColor(red: 0.32, green: 0.70, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.04, green: 0.36, blue: 0.90, alpha: 1).cgColor
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 0.5, 1]
            )!
            ctx.cgContext.saveGState()
            ctx.cgContext.addPath(rounded.cgPath)
            ctx.cgContext.clip()
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: w / 2, y: 0),
                end: CGPoint(x: w / 2, y: h),
                options: []
            )
            ctx.cgContext.restoreGState()
            UIColor.white.setStroke()
            rounded.lineWidth = 4
            rounded.lineJoinStyle = .round
            rounded.lineCapStyle = .round
            rounded.stroke()
        }
    }
}

final class LiveFollowPinAnnotationView: MKAnnotationView {
    private let iconView = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        centerOffset = CGPoint(x: 0, y: -12)
        iconView.frame = bounds
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ annotation: LiveFollowPinAnnotation) {
        let (name, color): (String, UIColor) = {
            switch annotation.kind {
            case .start:
                return ("flag.fill", .systemGreen)
            case .pause, .tripStop:
                return ("pause.circle.fill", .systemOrange)
            }
        }()
        let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .semibold)
        iconView.image = UIImage(systemName: name, withConfiguration: config)
        iconView.tintColor = color
        accessibilityLabel = {
            switch annotation.kind {
            case .start: return L10n.string("recording.live_map.start_pin")
            case .pause: return L10n.string("recording.live_map.pause_pin")
            case .tripStop: return L10n.tripPointStop
            }
        }()
    }
}
