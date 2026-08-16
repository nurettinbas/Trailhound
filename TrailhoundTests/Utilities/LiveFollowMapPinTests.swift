import CoreLocation
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

    func testRouteTipNilWhenMissingEnds() {
        let point = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        XCTAssertNil(LiveFollowRouteTip.coordinates(from: nil, to: point))
        XCTAssertNil(LiveFollowRouteTip.coordinates(from: point, to: nil))
    }

    func testRouteTipNilWhenVehicleOnCommittedPoint() {
        let point = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        XCTAssertNil(LiveFollowRouteTip.coordinates(from: point, to: point))
    }

    func testRouteTipConnectsCommittedToVehicle() {
        let committed = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let vehicle = CLLocationCoordinate2D(latitude: 41.001, longitude: 29.0)
        let coords = LiveFollowRouteTip.coordinates(from: committed, to: vehicle)
        XCTAssertEqual(coords?.count, 2)
        XCTAssertEqual(coords?[0].latitude ?? 0, 41.0, accuracy: 0.0000001)
        XCTAssertEqual(coords?[1].latitude ?? 0, 41.001, accuracy: 0.0000001)
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
        // Endpoints larger than stops (matching trip detail prominence).
        let start = RouteMapPinImage.uiImage(for: .start)
        let stop = RouteMapPinImage.uiImage(for: .stop)
        XCTAssertGreaterThan(start.size.width, stop.size.width)
    }
}
