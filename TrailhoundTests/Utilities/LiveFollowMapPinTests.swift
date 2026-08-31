import CoreLocation
import MapKit
import XCTest
@testable import Trailhound

final class LiveFollowMapPinTests: XCTestCase {
    func testBuilderIncludesStartOnceAndAccumulatesPauses() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let pause1 = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        let pause2 = CLLocationCoordinate2D(latitude: 41.02, longitude: 29.02)
        let stop = CLLocationCoordinate2D(latitude: 41.03, longitude: 29.03)

        let pins = LiveFollowMapPinBuilder.pins(
            startCoordinate: start,
            pauseCoordinates: [pause1, pause2],
            tripStopCoordinates: [stop]
        )

        XCTAssertEqual(pins.count, 4)
        XCTAssertEqual(pins[0].kind, .start)
        XCTAssertEqual(pins[0].id, "start")
        XCTAssertEqual(pins[1].kind, .pause)
        XCTAssertEqual(pins[1].id, "pause-0")
        XCTAssertEqual(pins[2].kind, .pause)
        XCTAssertEqual(pins[2].id, "pause-1")
        XCTAssertEqual(pins[3].kind, .tripStop)
        XCTAssertEqual(pins[3].id, "stop-0")
    }

    func testResumeDoesNotRequireClearingPausePins() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let pause = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        let whilePaused = LiveFollowMapPinBuilder.pins(
            startCoordinate: start,
            pauseCoordinates: [pause],
            tripStopCoordinates: []
        )
        let afterResume = LiveFollowMapPinBuilder.pins(
            startCoordinate: start,
            pauseCoordinates: [pause],
            tripStopCoordinates: []
        )
        XCTAssertEqual(whilePaused, afterResume)
        XCTAssertEqual(afterResume.filter { $0.kind == .pause }.count, 1)
    }

    func testNilStartOmitsStartPin() {
        let pins = LiveFollowMapPinBuilder.pins(
            startCoordinate: nil,
            pauseCoordinates: [],
            tripStopCoordinates: []
        )
        XCTAssertTrue(pins.isEmpty)
    }

    func testResolvedStartPrefersLatchedThenBreadcrumbThenFallback() {
        let latched = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let breadcrumb = CLLocationCoordinate2D(latitude: 41.1, longitude: 29.1)
        let fallback = CLLocationCoordinate2D(latitude: 41.2, longitude: 29.2)
        XCTAssertEqual(
            LiveFollowMapPinBuilder.resolvedStartCoordinate(
                latched: latched,
                breadcrumbStart: breadcrumb,
                fallback: fallback
            )?.latitude ?? 0,
            41.0,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            LiveFollowMapPinBuilder.resolvedStartCoordinate(
                latched: nil,
                breadcrumbStart: breadcrumb,
                fallback: fallback
            )?.latitude ?? 0,
            41.1,
            accuracy: 0.000_000_1
        )
        XCTAssertEqual(
            LiveFollowMapPinBuilder.resolvedStartCoordinate(
                latched: nil,
                breadcrumbStart: nil,
                fallback: fallback
            )?.latitude ?? 0,
            41.2,
            accuracy: 0.000_000_1
        )
        XCTAssertNil(
            LiveFollowMapPinBuilder.resolvedStartCoordinate(
                latched: nil,
                breadcrumbStart: nil,
                fallback: nil
            )
        )
    }

    func testHistoryPiecesDropsEmptyAndSinglePointRuns() {
        let a = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let b = CLLocationCoordinate2D(latitude: 41.001, longitude: 29.0)
        XCTAssertTrue(LiveFollowGrowingRoute.historyPieces(from: []).isEmpty)
        XCTAssertTrue(LiveFollowGrowingRoute.historyPieces(from: [[]]).isEmpty)
        XCTAssertTrue(LiveFollowGrowingRoute.historyPieces(from: [[a]]).isEmpty)
        let pieces = LiveFollowGrowingRoute.historyPieces(from: [[a, b]])
        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces[0].count, 2)
    }

    func testHistoryPiecesKeepGapSplitRuns() {
        let first = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.001, longitude: 29.0)
        ]
        let second = [
            CLLocationCoordinate2D(latitude: 41.5, longitude: 29.4),
            CLLocationCoordinate2D(latitude: 41.501, longitude: 29.4)
        ]
        let pieces = LiveFollowGrowingRoute.historyPieces(from: [first, second])
        XCTAssertEqual(pieces.count, 2)
        let gap = CLLocation(latitude: 41.001, longitude: 29.0)
            .distance(from: CLLocation(latitude: 41.5, longitude: 29.4))
        XCTAssertGreaterThan(gap, 10_000)
        for piece in pieces {
            for index in 1..<piece.count {
                let a = piece[index - 1]
                let b = piece[index]
                let distance = CLLocation(latitude: a.latitude, longitude: a.longitude)
                    .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
                XCTAssertLessThan(distance, 5_000, "Must not chord across GPS gap")
            }
        }
    }

    /// MapKit's own renderers keep the stroke a constant screen width under pitch;
    /// a custom `MKOverlayRenderer` fattens it in 3D and seams while panning.
    func testRouteStrokeUsesConstantScreenWidthVectorRenderers() {
        let a = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let b = CLLocationCoordinate2D(latitude: 41.001, longitude: 29.0)
        let line = MKPolyline(coordinates: [a, b], count: 2)

        let single = MKPolylineRenderer(polyline: line)
        LiveFollowRouteStrokeStyle.apply(to: single)
        XCTAssertEqual(single.lineWidth, LiveFollowRouteStrokeStyle.solidWidth)
        XCTAssertEqual(single.strokeColor, LiveFollowRouteStrokeStyle.solidColor)
        XCTAssertEqual(single.lineCap, .round)

        let multi = MKMultiPolylineRenderer(multiPolyline: MKMultiPolyline([line]))
        LiveFollowRouteStrokeStyle.apply(to: multi)
        XCTAssertEqual(multi.lineWidth, LiveFollowRouteStrokeStyle.solidWidth)
        XCTAssertEqual(multi.strokeColor, LiveFollowRouteStrokeStyle.solidColor)
        XCTAssertEqual(multi.lineJoin, .round)
    }

    func testHistoryMultiPolylineHasNonNullBoundsCoveringCoordinates() {
        let a = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let b = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        let pieces = LiveFollowGrowingRoute.historyPieces(from: [[a, b]])
        let polylines = pieces.map { coords -> MKPolyline in
            var copy = coords
            return MKPolyline(coordinates: &copy, count: copy.count)
        }
        let multi = MKMultiPolyline(polylines)
        XCTAssertFalse(multi.boundingMapRect.isNull)
        XCTAssertFalse(multi.boundingMapRect.isEmpty)
        XCTAssertTrue(multi.boundingMapRect.contains(MKMapPoint(a)))
        XCTAssertTrue(multi.boundingMapRect.contains(MKMapPoint(b)))
    }

    func testTipSegmentIsExactlyTwoPointsOrNil() {
        let anchor = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        XCTAssertNil(LiveFollowGrowingRoute.tipSegment(anchor: nil, vehicle: anchor))
        XCTAssertNil(LiveFollowGrowingRoute.tipSegment(anchor: anchor, vehicle: nil))
        XCTAssertNil(LiveFollowGrowingRoute.tipSegment(anchor: anchor, vehicle: anchor))

        let near = LiveFollowCamera.coordinate(from: anchor, headingDegrees: 0, distanceMeters: 8)
        let tip = LiveFollowGrowingRoute.tipSegment(anchor: anchor, vehicle: near)
        XCTAssertEqual(tip?.count, 2)
        XCTAssertEqual(tip?[0].latitude ?? 0, anchor.latitude, accuracy: 0.0000001)
        XCTAssertEqual(tip?[1].latitude ?? 0, near.latitude, accuracy: 0.0000001)

        let far = LiveFollowCamera.coordinate(from: anchor, headingDegrees: 0, distanceMeters: 200)
        XCTAssertNil(LiveFollowGrowingRoute.tipSegment(anchor: anchor, vehicle: far))
    }

    func testTipDoesNotChordAcrossGPSGap() {
        let lastGPS = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let vehicle = CLLocationCoordinate2D(latitude: 41.5, longitude: 29.4)
        XCTAssertNil(LiveFollowGrowingRoute.tipSegment(anchor: lastGPS, vehicle: vehicle))
    }

    func testOverviewMapRectCoversStartAndPuck() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let mid = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.0)
        let puck = CLLocationCoordinate2D(latitude: 41.02, longitude: 29.0)
        let rect = LiveFollowGrowingRoute.overviewMapRect(
            historyPieces: [[start, mid]],
            vehicle: puck
        )
        XCTAssertFalse(rect.isNull)
        XCTAssertTrue(rect.contains(MKMapPoint(start)))
        XCTAssertTrue(rect.contains(MKMapPoint(puck)))
    }

    func testOverviewMapRectPadsAPointSizedStart() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let rect = LiveFollowGrowingRoute.overviewMapRect(historyPieces: [], vehicle: start)
        XCTAssertFalse(rect.isNull)
        XCTAssertTrue(rect.contains(MKMapPoint(start)))
        let metersPerPoint = MKMetersPerMapPointAtLatitude(start.latitude)
        XCTAssertGreaterThan(rect.size.width * metersPerPoint, 100)
    }

    func testLiveActiveCoordinatesKeepsShortRunsRaw() {
        let raw = (0..<20).map { index in
            CLLocationCoordinate2D(latitude: 41.0 + Double(index) * 0.0001, longitude: 29.0)
        }
        let display = LiveFollowGrowingRoute.liveActiveCoordinates(raw)
        XCTAssertEqual(display.count, raw.count)
        XCTAssertEqual(display.last?.latitude ?? 0, raw.last?.latitude ?? -1, accuracy: 0.0000001)
    }

    func testLiveActiveCoordinatesPreservesRawTailOnLongRun() {
        let raw = (0..<1_300).map { index in
            CLLocationCoordinate2D(latitude: 41.0 + Double(index) * 0.0001, longitude: 29.0)
        }
        let display = LiveFollowGrowingRoute.liveActiveCoordinates(raw)
        let tip = Array(raw.suffix(LiveFollowGrowingRoute.liveTailKeep))
        XCTAssertEqual(
            display.suffix(LiveFollowGrowingRoute.liveTailKeep).map(\.latitude),
            tip.map(\.latitude)
        )
        XCTAssertLessThan(display.count, raw.count)
    }

    func testRouteStrokeStyleIsSingleSolidBlue() {
        XCTAssertEqual(LiveFollowRouteStrokeStyle.solidWidth, 7.2, accuracy: 0.01)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        XCTAssertTrue(
            LiveFollowRouteStrokeStyle.solidColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        )
        XCTAssertGreaterThan(blue, red)
        XCTAssertGreaterThan(blue, green)
        XCTAssertEqual(alpha, 1, accuracy: 0.01)
    }

    func testPuckChevronUsesFourVerticesAndLastPoint() {
        let points = LiveFollowPuckAnnotationView.chevronOutlinePoints(size: CGSize(width: 52, height: 38))
        XCTAssertEqual(points.count, 4)
        XCTAssertEqual(points.last?.x ?? 0, 52 * 0.03, accuracy: 0.01)
        XCTAssertEqual(points[points.count - 1].y, 38 * 0.92, accuracy: 0.01)
    }

    func testRouteMapPinKindsMatchTripDetailSymbols() {
        XCTAssertEqual(RouteMapPinKind.start.systemName, "flag.fill")
        XCTAssertEqual(RouteMapPinKind.end.systemName, "mappin.circle.fill")
        XCTAssertEqual(RouteMapPinKind.stop.systemName, "pause.circle.fill")
        XCTAssertTrue(RouteMapPinKind.start.isEndpoint)
        XCTAssertTrue(RouteMapPinKind.end.isEndpoint)
        XCTAssertFalse(RouteMapPinKind.stop.isEndpoint)
    }

    @MainActor
    func testRouteMapPinImageProducesNonEmptyBitmaps() {
        for kind in [RouteMapPinKind.start, .end, .stop] {
            let image = RouteMapPinImage.uiImage(for: kind)
            XCTAssertGreaterThan(image.size.width, 1, "\(kind) width")
            XCTAssertGreaterThan(image.size.height, 1, "\(kind) height")
        }
        let start = RouteMapPinImage.uiImage(for: .start)
        let stop = RouteMapPinImage.uiImage(for: .stop)
        XCTAssertGreaterThan(start.size.width, stop.size.width)
    }
}
