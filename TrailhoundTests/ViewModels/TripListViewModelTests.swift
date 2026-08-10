import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

final class TripListViewModelTests: XCTestCase {
    func testRouteSummaryUsesPlaceNames() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1200,
            startPlaceName: "Home",
            endPlaceName: "Office"
        )

        let summary = TripListViewModel.routeSummary(for: trip)

        XCTAssertTrue(summary.contains("Home"))
        XCTAssertTrue(summary.contains("Office"))
    }

    func testRouteSummaryAppliesPrivacyDisplayName() {
        let home = SavedPlace(
            name: "Home",
            latitude: 41.0082,
            longitude: 28.9784,
            radiusMeters: 500,
            kind: .home,
            isPrivacyZone: true
        )
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1200,
            startPlaceName: "Exact Home",
            endPlaceName: "Office"
        )
        trip.points = [
            TripPoint(timestamp: trip.startedAt, latitude: 41.0082, longitude: 28.9784, sequence: 0, trip: trip),
            TripPoint(timestamp: trip.endedAt!, latitude: 41.05, longitude: 29.0, sequence: 1, trip: trip)
        ]

        let summary = TripListViewModel.routeSummary(for: trip, places: [home], privacyRadius: 500)

        XCTAssertFalse(summary.contains("Exact Home"))
        XCTAssertTrue(summary.contains("Office") || summary.contains("→"))
    }

    func testMatchesSearchByLabel() {
        let trip = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 1000,
            label: "Commute"
        )

        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "comm"))
        XCTAssertFalse(TripListViewModel.matchesSearch(trip, searchText: "holiday"))
    }

    func testMatchesSearchEmptyQueryMatchesAll() {
        let trip = Trip(startedAt: Date(), endedAt: Date(), distanceMeters: 100)

        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: ""))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "   "))
    }

    func testDurationAndDistanceTextForCompletedTrip() {
        let startedAt = Date().addingTimeInterval(-3900)
        let endedAt = Date()
        let trip = Trip(startedAt: startedAt, endedAt: endedAt, distanceMeters: 12_400)

        XCTAssertFalse(TripListViewModel.durationText(for: trip).isEmpty)
        XCTAssertFalse(TripListViewModel.distanceText(for: trip).isEmpty)
        XCTAssertNotNil(TripListViewModel.fuelText(for: trip))
    }
}

@MainActor
final class TripListPageVehicleFilterTests: XCTestCase {
    func testDescriptorFiltersByVehicleID() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let vehicleA = UUID()
        let vehicleB = UUID()
        let now = Date()

        let tripA = Trip(
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000),
            distanceMeters: 1_000,
            vehicleID: vehicleA
        )
        let tripB = Trip(
            startedAt: now.addingTimeInterval(-2_400),
            endedAt: now.addingTimeInterval(-1_800),
            distanceMeters: 2_000,
            vehicleID: vehicleB
        )
        let tripNone = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500
        )
        context.insert(tripA)
        context.insert(tripB)
        context.insert(tripNone)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(vehicleFilter: .vehicle(vehicleA)),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(filtered.map(\.id), [tripA.id])
    }

    func testDescriptorFiltersUnassignedVehicle() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let vehicleA = UUID()
        let now = Date()
        let tripA = Trip(
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000),
            distanceMeters: 1_000,
            vehicleID: vehicleA
        )
        let tripNone = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500
        )
        context.insert(tripA)
        context.insert(tripNone)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(vehicleFilter: .unassigned),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(filtered.map(\.id), [tripNone.id])
    }

    func testFiltersIsActiveWhenVehicleSelected() {
        XCTAssertTrue(TripListPage.Filters(vehicleFilter: .vehicle(UUID())).isActive)
        XCTAssertTrue(TripListPage.Filters(vehicleFilter: .unassigned).isActive)
        XCTAssertFalse(TripListPage.Filters().isActive)
    }
}

@MainActor
final class TripListPagePlaceFilterTests: XCTestCase {
    func testDescriptorIncludesStartOrEndPlaceMatch() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()

        let startMatch = Trip(
            startedAt: now.addingTimeInterval(-3_600),
            endedAt: now.addingTimeInterval(-3_000),
            distanceMeters: 1_000,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let endMatch = Trip(
            startedAt: now.addingTimeInterval(-2_400),
            endedAt: now.addingTimeInterval(-1_800),
            distanceMeters: 2_000,
            startPlaceName: "Market",
            endPlaceName: "Ev"
        )
        let neither = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500,
            startPlaceName: "Market",
            endPlaceName: "Ofis"
        )
        context.insert(startMatch)
        context.insert(endMatch)
        context.insert(neither)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(placeName: "Ev"),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(Set(filtered.map(\.id)), Set([startMatch.id, endMatch.id]))
    }

    func testDescriptorWithoutPlaceReturnsAllCompleted() throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()
        let trip = Trip(
            startedAt: now.addingTimeInterval(-1_200),
            endedAt: now.addingTimeInterval(-600),
            distanceMeters: 500,
            startPlaceName: "Ev"
        )
        context.insert(trip)
        try context.save()

        let filtered = try context.fetch(
            TripListPage.descriptor(
                filters: TripListPage.Filters(),
                limit: TripListPage.pageSize
            )
        )

        XCTAssertEqual(filtered.map(\.id), [trip.id])
    }

    func testFiltersIsActiveWhenPlaceSelected() {
        XCTAssertTrue(TripListPage.Filters(placeName: "Ev").isActive)
        XCTAssertFalse(TripListPage.Filters().isActive)
    }

    func testTripPlaceFilterMatchesStartOrEnd() {
        XCTAssertTrue(
            TripPlaceFilter.matches(
                startPlaceName: "Ev",
                endPlaceName: "Ofis",
                placeName: "Ev"
            )
        )
        XCTAssertTrue(
            TripPlaceFilter.matches(
                startPlaceName: "Market",
                endPlaceName: "Ev",
                placeName: "Ev"
            )
        )
        XCTAssertFalse(
            TripPlaceFilter.matches(
                startPlaceName: "Market",
                endPlaceName: "Ofis",
                placeName: "Ev"
            )
        )
        XCTAssertTrue(
            TripPlaceFilter.matches(
                startPlaceName: "Market",
                endPlaceName: "Ofis",
                placeName: nil
            )
        )
    }
}
