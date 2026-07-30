import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

/// Regression shield for the bug that silently destroyed long recordings: post-processing used
/// to replace a trip's points with a simplified subset, so a 1922-point drive came back as 143.
@MainActor
final class TripPostProcessorTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainerFactory.makeInMemory()
    }

    func testProcessKeepsEveryRecordedPoint() async throws {
        let pointCount = 1500
        let trip = makeTrip(pointCount: pointCount)
        container.mainContext.insert(trip)
        for point in trip.points { container.mainContext.insert(point) }
        try container.mainContext.save()

        await TripPostProcessor.process(tripUUID: trip.id, container: container)

        let stored = try container.mainContext.fetch(FetchDescriptor<Trip>())
        let reloaded = try XCTUnwrap(stored.first { $0.id == trip.id })
        XCTAssertEqual(reloaded.points.count, pointCount)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<TripPoint>()).count, pointCount)
    }

    func testProcessKeepsSpeedDataIntact() async throws {
        let trip = makeTrip(pointCount: 1200)
        container.mainContext.insert(trip)
        for point in trip.points { container.mainContext.insert(point) }
        try container.mainContext.save()

        await TripPostProcessor.process(tripUUID: trip.id, container: container)

        let stored = try container.mainContext.fetch(FetchDescriptor<Trip>())
        let reloaded = try XCTUnwrap(stored.first { $0.id == trip.id })
        XCTAssertEqual(reloaded.sortedPoints.filter { ($0.speedMps ?? 0) > 0 }.count, 1200)
    }

    private func makeTrip(pointCount: Int) -> Trip {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let trip = Trip(startedAt: start, endedAt: start.addingTimeInterval(Double(pointCount)), distanceMeters: 24_000)

        let latitude = 38.42
        let metersPerDegreeLongitude = 111_320 * cos(latitude * .pi / 180)
        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: start.addingTimeInterval(Double(index)),
                latitude: latitude,
                longitude: 27.14 + (Double(index) * 14) / metersPerDegreeLongitude,
                sequence: index,
                speedMps: 14,
                trip: trip
            )
            trip.points.append(point)
        }
        return trip
    }
}
