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
}
