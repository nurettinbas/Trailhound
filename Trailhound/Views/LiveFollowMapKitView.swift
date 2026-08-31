import MapKit
import SwiftUI
import UIKit

/// Live-follow route stroke — single solid (no casing, no second blue).
enum LiveFollowRouteStrokeStyle {
    static let solidWidth: CGFloat = 7.2
    static let solidColor = UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 1)
}

/// MapKit host for live follow — display-link camera, GPS history + two-point tip, pins + puck.
struct LiveFollowMapKitView: UIViewRepresentable {
    var session: LiveFollowSession
    var isFollowing: Bool
    var isPaused: Bool
    /// Bumped when the user asks to fit start + traveled path + puck (north-up 2D).
    var overviewRequestToken: Int
    var segments: [LiveFollowPolylineSegment]
    var pins: [LiveFollowMapPin]
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var puckRevealed: Bool
    /// 0…1 — MapKit puck view alpha (handoff crossfade with SwiftUI hero).
    var puckAlpha: CGFloat
    /// Bumped when puck alpha should animate (open/close handoff).
    var puckFadeToken: Int
    var isMoving: Bool
    var onUserBreakFollow: () -> Void
    /// Once MapKit has laid out, reports the puck circle center in map-view coordinates.
    var onPuckCircleScreenPoint: ((CGPoint) -> Void)?

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
        map.pointOfInterestFilter = .excludingAll
        if #available(iOS 16.0, *) {
            map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        }
        context.coordinator.mapView = map
        context.coordinator.bindSession()
        context.coordinator.installGestureBreak(on: map)
        context.coordinator.ensureHistoryOverlay(on: map)
        context.coordinator.ensureTipOverlay(on: map)
        if let pose = session.pose {
            context.coordinator.applyCamera(pose, on: map)
        }
        return map
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.session = session
        context.coordinator.isFollowing = isFollowing
        context.coordinator.isPaused = isPaused
        context.coordinator.onUserBreakFollow = onUserBreakFollow
        context.coordinator.onPuckCircleScreenPoint = onPuckCircleScreenPoint
        context.coordinator.desiredPuckAlpha = puckAlpha
        context.coordinator.bindSession()

        if #available(iOS 16.0, *) {
            if !(mapView.preferredConfiguration is MKStandardMapConfiguration) {
                mapView.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
            }
        }

        context.coordinator.syncRoute(segments, on: mapView)
        context.coordinator.syncPins(pins, on: mapView)
        context.coordinator.syncPuck(
            coordinate: session.vehicleCoordinate,
            revealed: puckRevealed,
            photo: vehiclePhoto,
            systemImage: vehicleSystemImage,
            isMoving: isMoving,
            updateCoordinate: false,
            on: mapView
        )
        let shouldAnimatePuck = context.coordinator.lastPuckFadeToken != puckFadeToken
        if shouldAnimatePuck {
            context.coordinator.lastPuckFadeToken = puckFadeToken
            context.coordinator.applyPuckAlpha(puckAlpha, animated: true, on: mapView)
        } else if abs(context.coordinator.desiredPuckAlpha - puckAlpha) > 0.001 {
            context.coordinator.applyPuckAlpha(puckAlpha, animated: false, on: mapView)
        } else {
            context.coordinator.desiredPuckAlpha = puckAlpha
        }
        if context.coordinator.lastOverviewRequestToken != overviewRequestToken {
            context.coordinator.lastOverviewRequestToken = overviewRequestToken
            if overviewRequestToken > 0 {
                context.coordinator.applyOverviewCamera(on: mapView)
            }
        }
        context.coordinator.reportPuckCircleScreenPointIfPossible(on: mapView)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var session: LiveFollowSession
        var isFollowing = true
        var isPaused = false
        var onUserBreakFollow: () -> Void
        var onPuckCircleScreenPoint: ((CGPoint) -> Void)?
        var desiredPuckAlpha: CGFloat = 1
        var lastPuckFadeToken: Int = 0
        var lastOverviewRequestToken: Int = 0
        weak var mapView: MKMapView?
        private var isApplyingCamera = false
        private var pinAnnotations: [String: LiveFollowPinAnnotation] = [:]
        private var puckAnnotation: LiveFollowPuckAnnotation?
        private var gestureRecognizersInstalled = false
        private var lastReportedPuckPoint: CGPoint?
        private let historyOverlay = LiveFollowHistoryOverlay()
        private weak var historyRenderer: LiveFollowHistoryRenderer?
        private let tipOverlay = LiveFollowTipOverlay()
        private weak var tipRenderer: LiveFollowTipRenderer?
        private var lastCommittedPieces: [[CLLocationCoordinate2D]] = []

        init(
            session: LiveFollowSession,
            onUserBreakFollow: @escaping () -> Void
        ) {
            self.session = session
            self.onUserBreakFollow = onUserBreakFollow
        }

        @objc private func userGesture(_ gesture: UIGestureRecognizer) {
            guard gesture.state == .began else { return }
            guard !isApplyingCamera else { return }
            breakFollow()
            onUserBreakFollow()
        }

        /// Stop follow immediately — don't wait for SwiftUI `updateUIView`.
        private func breakFollow() {
            session.isFollowing = false
            isFollowing = false
        }

        private var isFollowLocked: Bool {
            session.isFollowing && isFollowing
        }

        func bindSession() {
            session.onPoseWrite = { [weak self] pose, vehicle in
                guard let self, let map = self.mapView else { return }
                let following = self.isFollowLocked

                CATransaction.begin()
                CATransaction.setDisableActions(true)
                if following {
                    self.applyCamera(pose, on: map, withinTransaction: true)
                }
                if let vehicle, let puck = self.puckAnnotation {
                    puck.coordinate = vehicle
                }
                self.updateRouteTip(vehicle: vehicle, on: map)
                CATransaction.commit()
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

        func applyCamera(
            _ pose: LiveFollowCamera.Pose,
            on map: MKMapView,
            preserveCenter: Bool = false,
            withinTransaction: Bool = false
        ) {
            let center = preserveCenter ? map.camera.centerCoordinate : pose.center
            let camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: pose.distanceMeters,
                pitch: pose.pitchDegrees,
                heading: preserveCenter ? map.camera.heading : pose.headingDegrees
            )
            isApplyingCamera = true
            if !withinTransaction {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
            }
            map.camera = camera
            if !withinTransaction {
                CATransaction.commit()
            }
            isApplyingCamera = false
        }

        func syncRoute(_ segments: [LiveFollowPolylineSegment], on map: MKMapView) {
            let next = segments.map(\.coordinates)
            let unchanged = Self.samePieces(next, lastCommittedPieces)
            lastCommittedPieces = next
            if !unchanged {
                replaceHistoryOverlay(next, on: map)
            }
            updateRouteTip(vehicle: session.vehicleCoordinate, on: map)
        }

        private func updateRouteTip(vehicle: CLLocationCoordinate2D?, on map: MKMapView) {
            ensureTipOverlay(on: map)
            let points: [CLLocationCoordinate2D]
            if isPaused {
                points = []
            } else {
                points = LiveFollowGrowingRoute.tipSegment(
                    anchor: LiveFollowGrowingRoute.tipAnchor(from: lastCommittedPieces),
                    vehicle: vehicle
                ) ?? []
            }
            let dirty = tipOverlay.replacePoints(points)
            guard !dirty.isNull else { return }
            tipRenderer?.setNeedsDisplay(dirty)
        }

        func ensureTipOverlay(on map: MKMapView) {
            if !map.overlays.contains(where: { $0 === tipOverlay }) {
                map.addOverlay(tipOverlay, level: .aboveRoads)
            }
        }

        func ensureHistoryOverlay(on map: MKMapView) {
            if !map.overlays.contains(where: { $0 === historyOverlay }) {
                map.addOverlay(historyOverlay, level: .aboveRoads)
            }
        }

        private func replaceHistoryOverlay(_ pieces: [[CLLocationCoordinate2D]], on map: MKMapView) {
            ensureHistoryOverlay(on: map)
            let drawable = LiveFollowGrowingRoute.historyPieces(from: pieces)
            if let dirty = historyOverlay.replacePieces(drawable) {
                historyRenderer?.setNeedsDisplay(dirty)
            } else {
                historyRenderer?.setNeedsDisplay()
            }
        }

        func applyOverviewCamera(on map: MKMapView) {
            let pieces = LiveFollowGrowingRoute.historyPieces(from: lastCommittedPieces)
            let rect = LiveFollowGrowingRoute.overviewMapRect(
                historyPieces: pieces,
                vehicle: session.vehicleCoordinate ?? LiveFollowGrowingRoute.tipAnchor(from: lastCommittedPieces)
            )
            guard !rect.isNull else { return }
            breakFollow()
            onUserBreakFollow()
            let center = MKMapPoint(x: rect.midX, y: rect.midY).coordinate
            let metersPerPoint = MKMetersPerMapPointAtLatitude(center.latitude)
            let spanMeters = max(rect.size.width, rect.size.height) * metersPerPoint
            let distance = max(spanMeters * 1.35, 220)
            isApplyingCamera = true
            let camera = MKMapCamera(
                lookingAtCenter: center,
                fromDistance: distance,
                pitch: 0,
                heading: 0
            )
            map.setCamera(camera, animated: true)
            isApplyingCamera = false
        }

        private static func samePieces(
            _ lhs: [[CLLocationCoordinate2D]],
            _ rhs: [[CLLocationCoordinate2D]]
        ) -> Bool {
            guard lhs.count == rhs.count else { return false }
            for (a, b) in zip(lhs, rhs) {
                guard a.count == b.count else { return false }
                if let al = a.last, let bl = b.last,
                   abs(al.latitude - bl.latitude) > 1e-9
                    || abs(al.longitude - bl.longitude) > 1e-9
                {
                    return false
                }
                if let af = a.first, let bf = b.first,
                   abs(af.latitude - bf.latitude) > 1e-9
                    || abs(af.longitude - bf.longitude) > 1e-9
                {
                    return false
                }
            }
            return true
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
            updateCoordinate: Bool = true,
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
                if updateCoordinate {
                    puckAnnotation.coordinate = coordinate
                }
                puckAnnotation.vehiclePhoto = photo
                puckAnnotation.vehicleSystemImage = systemImage
                puckAnnotation.isMoving = isMoving
                if let view = map.view(for: puckAnnotation) as? LiveFollowPuckAnnotationView {
                    view.isHidden = false
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

        func applyPuckAlpha(_ alpha: CGFloat, animated: Bool, on map: MKMapView) {
            desiredPuckAlpha = alpha
            let apply = {
                if let puckAnnotation = self.puckAnnotation, let view = map.view(for: puckAnnotation) {
                    view.alpha = alpha
                    view.isHidden = false
                }
            }
            if animated {
                UIView.animate(
                    withDuration: TrailhoundMotion.liveFollowHandoffDuration,
                    delay: 0,
                    options: [.curveEaseInOut, .beginFromCurrentState]
                ) {
                    apply()
                }
            } else {
                apply()
            }
        }

        /// Projects the live vehicle into map-view space and reports the photo-circle center.
        func reportPuckCircleScreenPointIfPossible(on map: MKMapView) {
            guard let onPuckCircleScreenPoint else { return }
            guard map.bounds.width > 1, map.bounds.height > 1 else { return }
            guard let coordinate = session.vehicleCoordinate else { return }
            let projected = map.convert(coordinate, toPointTo: map)
            let circle = LiveFollowPresentation.puckCircleCenter(fromProjectedAnnotationPoint: projected)
            if let last = lastReportedPuckPoint,
               abs(last.x - circle.x) < 0.5,
               abs(last.y - circle.y) < 0.5
            {
                return
            }
            lastReportedPuckPoint = circle
            onPuckCircleScreenPoint(circle)
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let history = overlay as? LiveFollowHistoryOverlay {
                let renderer = LiveFollowHistoryRenderer(overlay: history)
                historyRenderer = renderer
                return renderer
            }
            if let tip = overlay as? LiveFollowTipOverlay {
                let renderer = LiveFollowTipRenderer(overlay: tip)
                tipRenderer = renderer
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let puck = annotation as? LiveFollowPuckAnnotation {
                let reuse = "live-follow-puck"
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? LiveFollowPuckAnnotationView)
                    ?? LiveFollowPuckAnnotationView(annotation: puck, reuseIdentifier: reuse)
                view.apply(puck)
                view.alpha = desiredPuckAlpha
                view.isHidden = false
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

        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for view in views where view is LiveFollowPuckAnnotationView {
                view.alpha = desiredPuckAlpha
                view.isHidden = false
            }
            reportPuckCircleScreenPointIfPossible(on: mapView)
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

// MARK: - History overlay (fixed world bounds — mutate in place, no 1 Hz add/remove)

final class LiveFollowHistoryOverlay: NSObject, MKOverlay {
    private(set) var pieces: [[CLLocationCoordinate2D]] = []

    var coordinate: CLLocationCoordinate2D {
        pieces.first?.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    let boundingMapRect: MKMapRect = .world

    /// Returns a small dirty rect when the active run grew; `nil` means full redraw.
    func replacePieces(_ next: [[CLLocationCoordinate2D]]) -> MKMapRect? {
        let previousCount = pieces.count
        let previousActiveCount = pieces.last?.count ?? 0
        let previousLast = pieces.last?.last
        pieces = next
        let grewSameRun = next.count == previousCount
            && (next.last?.count ?? 0) >= previousActiveCount
            && previousCount > 0
        if grewSameRun, let previousLast, let nextLast = next.last?.last {
            return LiveFollowGrowingRoute.dirtyMapRect(around: [previousLast, nextLast])
        }
        return nil
    }
}

final class LiveFollowHistoryRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? LiveFollowHistoryOverlay else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(LiveFollowRouteStrokeStyle.solidColor.cgColor)
        context.setLineWidth(LiveFollowRouteStrokeStyle.solidWidth / zoomScale)

        for piece in overlay.pieces where piece.count >= 2 {
            let path = CGMutablePath()
            for (index, coordinate) in piece.enumerated() {
                let point = self.point(for: MKMapPoint(coordinate))
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
            context.addPath(path)
            context.strokePath()
        }
    }
}

// MARK: - Two-point tip overlay (fixed world bounds — MapKit never drops the renderer)

final class LiveFollowTipOverlay: NSObject, MKOverlay {
    private(set) var points: [CLLocationCoordinate2D] = []

    var coordinate: CLLocationCoordinate2D {
        points.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    /// Captured when MapKit adds the overlay. Must stay world-sized so later
    /// coordinate updates remain drawable without swapping the overlay.
    let boundingMapRect: MKMapRect = .world

    @discardableResult
    func replacePoints(_ next: [CLLocationCoordinate2D]) -> MKMapRect {
        let previous = points
        if previous.count == next.count,
           zip(previous, next).allSatisfy({
               abs($0.latitude - $1.latitude) < 1e-9
                   && abs($0.longitude - $1.longitude) < 1e-9
           })
        {
            return .null
        }
        points = next
        return LiveFollowGrowingRoute.dirtyMapRect(around: previous + next)
    }
}

final class LiveFollowTipRenderer: MKOverlayRenderer {
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? LiveFollowTipOverlay else { return }
        guard overlay.points.count == 2 else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(LiveFollowRouteStrokeStyle.solidColor.cgColor)
        context.setLineWidth(LiveFollowRouteStrokeStyle.solidWidth / zoomScale)

        let path = CGMutablePath()
        let start = point(for: MKMapPoint(overlay.points[0]))
        let end = point(for: MKMapPoint(overlay.points[1]))
        path.move(to: start)
        path.addLine(to: end)
        context.addPath(path)
        context.strokePath()
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
    /// Opaque plate so the traveled path cannot show through the photo.
    private static let plateBlue = UIColor(red: 0.28, green: 0.62, blue: 1.0, alpha: 1)

    private let badge = UIView()
    private let photoView = UIImageView()
    private let symbolView = UIImageView()
    private let chevron = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        canShowCallout = false
        clipsToBounds = false
        zPriority = .max
        displayPriority = .required
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
        centerOffset = LiveFollowPresentation.puckAnnotationCenterOffset

        badge.isOpaque = true
        badge.backgroundColor = Self.plateBlue
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
        chevron.layer.zPosition = 2
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
    }

    func apply(_ annotation: LiveFollowPuckAnnotation) {
        zPriority = .max
        displayPriority = .required
        isHidden = false
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
    }

    /// Four-point chevron (V notch). Tests and drawing both use `points.last`.
    static func chevronOutlinePoints(size: CGSize) -> [CGPoint] {
        let w = size.width
        let h = size.height
        return [
            CGPoint(x: w * 0.50, y: h * 0.04),
            CGPoint(x: w * 0.97, y: h * 0.92),
            CGPoint(x: w * 0.50, y: h * 0.72),
            CGPoint(x: w * 0.03, y: h * 0.92)
        ]
    }

    private static func makeChevronImage(size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let w = size.width
            let h = size.height
            let points = Self.chevronOutlinePoints(size: size)
            let radius = min(w, h) * 0.12
            let cg = CGMutablePath()
            guard let last = points.last else { return }
            let first = points[0]
            cg.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
            for index in points.indices {
                let current = points[index]
                let next = points[(index + 1) % points.count]
                cg.addArc(tangent1End: current, tangent2End: next, radius: radius)
            }
            cg.closeSubpath()
            let rounded = UIBezierPath(cgPath: cg)

            let colors = [
                UIColor(red: 0.42, green: 0.76, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.28, green: 0.62, blue: 1.0, alpha: 1).cgColor,
                UIColor(red: 0.12, green: 0.48, blue: 0.95, alpha: 1).cgColor
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
        zPriority = .min
        displayPriority = .required
        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(_ annotation: LiveFollowPinAnnotation) {
        zPriority = .min
        displayPriority = .required
        let routeKind: RouteMapPinKind = {
            switch annotation.kind {
            case .start: return .start
            case .pause, .tripStop: return .stop
            }
        }()
        let image = RouteMapPinImage.uiImage(for: routeKind)
        iconView.image = image
        let size = image.size
        bounds = CGRect(origin: .zero, size: size)
        iconView.frame = bounds
        centerOffset = routeKind.isEndpoint
            ? CGPoint(x: 0, y: -size.height / 2)
            : .zero
        accessibilityLabel = {
            switch annotation.kind {
            case .start: return L10n.string("recording.live_map.start_pin")
            case .pause: return L10n.string("recording.live_map.pause_pin")
            case .tripStop: return L10n.tripPointStop
            }
        }()
    }
}
