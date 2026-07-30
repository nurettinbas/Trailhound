import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class TripMergeServiceTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainerFactory.makeInMemory()
    }

    func testMergeReturnsNilForSingleTrip() throws {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1000
        )
        container.mainContext.insert(trip)
        try container.mainContext.save()

        let merged = try TripMergeService.merge(trips: [trip], into: container.mainContext)

        XCTAssertNil(merged)
    }

    func testMergeCombinesDistanceDurationAndNotes() throws {
        let first = makeTrip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-5400),
            distanceMeters: 3000,
            note: "First leg",
            label: "Morning"
        )
        let second = makeTrip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 4500,
            note: "Second leg",
            label: "Evening"
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let expectedPointCount = first.points.count + second.points.count
        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [first, second], into: container.mainContext)
        )

        XCTAssertEqual(merged.distanceMeters, 7500, accuracy: 0.1)
        XCTAssertEqual(merged.startedAt, first.startedAt)
        XCTAssertEqual(merged.endedAt, second.endedAt)
        XCTAssertEqual(merged.points.count, expectedPointCount)
        XCTAssertTrue(merged.note?.contains("First leg") == true)
        XCTAssertTrue(merged.note?.contains("Second leg") == true)
        XCTAssertTrue(merged.label?.contains("Morning") == true)
        XCTAssertTrue(merged.label?.contains("Evening") == true)
    }

    func testMergeMarksTheGapBetweenLegsAsAStop() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let firstEnd = try XCTUnwrap(first.sortedPoints.last)
        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [first, second], into: container.mainContext)
        )

        XCTAssertEqual(merged.stops.count, 1)
        let junction = try XCTUnwrap(merged.stops.first)
        XCTAssertEqual(junction.startedAt, base.addingTimeInterval(1800))
        XCTAssertEqual(junction.durationSeconds, 1800, accuracy: 0.1)
        XCTAssertEqual(junction.latitude, firstEnd.latitude, accuracy: 0.000_001)
        XCTAssertEqual(junction.longitude, firstEnd.longitude, accuracy: 0.000_001)
    }

    func testMergeSkipsJunctionStopForBackToBackLegs() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(1805),
            endedAt: base.addingTimeInterval(3600),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [first, second], into: container.mainContext)
        )

        XCTAssertTrue(merged.stops.isEmpty)
    }

    /// A leg that was already standing still when it stopped recording must not end up with a
    /// second marker on top of the first.
    func testMergeExtendsAnExistingStopInsteadOfStackingMarkers() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let lastPoint = try XCTUnwrap(first.sortedPoints.last)
        let existing = TripStop(
            latitude: lastPoint.latitude,
            longitude: lastPoint.longitude,
            startedAt: base.addingTimeInterval(1500),
            durationSeconds: 300,
            trip: first
        )
        first.stops = [existing]

        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [first, second], into: container.mainContext)
        )

        XCTAssertEqual(merged.stops.count, 1)
        let stop = try XCTUnwrap(merged.stops.first)
        XCTAssertEqual(stop.startedAt, base.addingTimeInterval(1500))
        // 1500 s through to the moment the second leg starts at 3600 s.
        XCTAssertEqual(stop.durationSeconds, 2100, accuracy: 0.1)
    }

    /// A stop somewhere else on the route is a different standstill and must be left alone.
    func testMergeKeepsUnrelatedStopSeparateFromJunction() throws {
        let base = Date().addingTimeInterval(-7200)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let midRouteStop = TripStop(
            latitude: 40.5,
            longitude: 28.5,
            startedAt: base.addingTimeInterval(300),
            durationSeconds: 240,
            trip: first
        )
        first.stops = [midRouteStop]

        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [first, second], into: container.mainContext)
        )

        XCTAssertEqual(merged.stops.count, 2)
        XCTAssertEqual(merged.stops.filter { $0.durationSeconds == 240 }.count, 1)
        XCTAssertEqual(merged.stops.filter { $0.durationSeconds == 1800 }.count, 1)
    }

    func testMergeAddsAJunctionForEveryGapAcrossThreeLegs() throws {
        let base = Date().addingTimeInterval(-14_400)
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        let second = makeTrip(
            startedAt: base.addingTimeInterval(3600),
            endedAt: base.addingTimeInterval(5400),
            distanceMeters: 4500
        )
        let third = makeTrip(
            startedAt: base.addingTimeInterval(7200),
            endedAt: base.addingTimeInterval(9000),
            distanceMeters: 1500
        )
        for trip in [first, second, third] {
            container.mainContext.insert(trip)
        }
        try container.mainContext.save()

        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [third, first, second], into: container.mainContext)
        )

        XCTAssertEqual(merged.stops.count, 2)
        XCTAssertEqual(merged.stops.filter { $0.durationSeconds == 1800 }.count, 2)
    }

    /// The legs are deleted by the merge, so a vehicle dropped here is gone for good.
    func testMergeKeepsTheVehicleAssignment() throws {
        let base = Date().addingTimeInterval(-7200)
        let vehicleID = UUID()
        let first = makeTrip(startedAt: base, endedAt: base.addingTimeInterval(1800), distanceMeters: 3000)
        first.vehicleID = vehicleID
        let second = makeTrip(
            startedAt: base.addingTimeInterval(1800),
            endedAt: base.addingTimeInterval(3600),
            distanceMeters: 4500
        )
        second.vehicleID = vehicleID
        container.mainContext.insert(first)
        container.mainContext.insert(second)
        try container.mainContext.save()

        let merged = try XCTUnwrap(
            TripMergeService.merge(trips: [first, second], into: container.mainContext)
        )

        XCTAssertEqual(merged.vehicleID, vehicleID)
    }

    private func makeTrip(
        startedAt: Date,
        endedAt: Date,
        distanceMeters: Double,
        note: String? = nil,
        label: String? = nil
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: distanceMeters,
            note: note,
            label: label,
            category: .personal
        )
        let start = TripPoint(
            timestamp: startedAt,
            latitude: 41.0,
            longitude: 29.0,
            sequence: 0,
            trip: trip
        )
        let end = TripPoint(
            timestamp: endedAt,
            latitude: 41.01,
            longitude: 29.01,
            sequence: 1,
            trip: trip
        )
        trip.points = [start, end]
        return trip
    }
}
