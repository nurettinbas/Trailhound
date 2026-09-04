import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class FrequentRouteAggregateTests: XCTestCase {
    func testTwoTripsOnSamePairIncrementCount() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-1800),
            distanceMeters: 12_000,
            estimatedFuelCost: 80,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        first.startLatitude = 41.0
        first.startLongitude = 29.0
        first.endLatitude = 41.1
        first.endLongitude = 29.1
        let second = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 11_000,
            estimatedFuelCost: 70,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        second.startLatitude = 41.0
        second.startLongitude = 29.0
        second.endLatitude = 41.1
        second.endLongitude = 29.1
        context.insert(first)
        context.insert(second)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 2)
        XCTAssertEqual(rows.first?.totalDistanceMeters, 23_000, accuracy: 0.1)
    }

    func testPrivacyZoneUsesSavedPlaceDisplay() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let home = SavedPlace(
            name: "Ev",
            latitude: 41.008,
            longitude: 28.978,
            radiusMeters: 400,
            kind: .home,
            isPrivacyZone: true
        )
        context.insert(home)
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 8_000,
            startPlaceName: "Ev",
            endPlaceName: "Levent"
        )
        trip.startLatitude = 41.0082
        trip.startLongitude = 28.9784
        trip.endLatitude = 41.08
        trip.endLongitude = 29.01
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let row = try context.fetch(FetchDescriptor<FrequentRouteAggregate>()).first
        XCTAssertEqual(row?.startDisplay, L10n.placeNearName("Ev"))
        XCTAssertEqual(row?.startLatitude ?? 0, home.latitude, accuracy: 0.0001)
    }

    func testRemoveDeletesEmptyAggregate() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            distanceMeters: 5_000,
            startPlaceName: "A",
            endPlaceName: "B"
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        TripRollupService.remove(trip, in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<FrequentRouteAggregate>()).count, 0)
    }
}

@MainActor
final class FrequentRouteOverlayBudgetTests: XCTestCase {
    func testCapsOverlayCountAtForty() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        for index in 0..<60 {
            let row = FrequentRouteAggregate(
                pairKey: "place:a\(index)→place:b\(index)",
                startKey: "place:a\(index)",
                endKey: "place:b\(index)"
            )
            row.count = 60 - index
            row.startLatitude = 41
            row.startLongitude = 29
            row.endLatitude = 41.1
            row.endLongitude = 29.1
            context.insert(row)
        }
        try context.save()
        let all = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        let top = FrequentRouteOverlayBudget.topAggregates(all)
        XCTAssertEqual(top.count, 40)
        XCTAssertEqual(top.first?.count, 60)
        XCTAssertEqual(top.last?.count, 21)
    }
}

@MainActor
final class FrequentRouteMergeDeltaTests: XCTestCase {
    func testMergeLeavesSingleAggregate() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let first = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date().addingTimeInterval(-1800),
            distanceMeters: 8_000,
            startPlaceName: "A",
            endPlaceName: "B"
        )
        first.startLatitude = 41
        first.startLongitude = 29
        first.endLatitude = 41.05
        first.endLongitude = 29.05
        let second = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 9_000,
            startPlaceName: "A",
            endPlaceName: "B"
        )
        second.startLatitude = 41
        second.startLongitude = 29
        second.endLatitude = 41.05
        second.endLongitude = 29.05
        context.insert(first)
        context.insert(second)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()
        XCTAssertEqual(try context.fetch(FetchDescriptor<FrequentRouteAggregate>()).first?.count, 2)

        _ = try TripMergeService.merge(trips: [first, second], into: context)
        let rows = try context.fetch(FetchDescriptor<FrequentRouteAggregate>())
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.count, 1)
    }
}
