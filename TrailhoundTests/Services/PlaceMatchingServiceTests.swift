import CoreLocation
import XCTest
@testable import Trailhound

@MainActor
final class PlaceMatchingServiceTests: XCTestCase {
    func testMatchPlacesAssignsStartAndEndNames() {
        let trip = PreviewData.sampleTrip
        let office = SavedPlace(
            name: "Office",
            latitude: trip.endCoordinate!.latitude,
            longitude: trip.endCoordinate!.longitude,
            radiusMeters: 300
        )
        let home = SavedPlace(
            name: "Home",
            latitude: trip.startCoordinate!.latitude,
            longitude: trip.startCoordinate!.longitude,
            radiusMeters: 300
        )

        PlaceMatchingService.matchPlaces(for: trip, places: [home, office])

        XCTAssertEqual(trip.startPlaceName, "Home")
        XCTAssertEqual(trip.endPlaceName, "Office")
    }

    func testPrivacyDisplayNameWithinRadius() {
        let home = SavedPlace(
            name: "Home",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 200,
            kind: .home,
            isPrivacyZone: true
        )
        let coordinate = CLLocationCoordinate2D(latitude: 41.0005, longitude: 29.0005)

        let displayName = PlaceMatchingService.privacyDisplayName(
            for: coordinate,
            places: [home],
            privacyRadius: 500
        )

        XCTAssertNotNil(displayName)
    }

    func testPrivacyDisplayNameOutsideRadiusReturnsNil() {
        let home = SavedPlace(
            name: "Home",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 100,
            kind: .home,
            isPrivacyZone: true
        )
        let coordinate = CLLocationCoordinate2D(latitude: 42.0, longitude: 30.0)

        let displayName = PlaceMatchingService.privacyDisplayName(
            for: coordinate,
            places: [home],
            privacyRadius: 100
        )

        XCTAssertNil(displayName)
    }

    func testBlurredCoordinateRoundsToTwoDecimals() {
        let blurred = PlaceMatchingService.blurredCoordinate(
            CLLocationCoordinate2D(latitude: 41.00824, longitude: 28.97841)
        )

        XCTAssertEqual(blurred.latitude, 41.01, accuracy: 0.001)
        XCTAssertEqual(blurred.longitude, 28.98, accuracy: 0.001)
    }

    func testMatchPlacesUpdatesStartWhenEndCoordinateMissing() {
        let trip = Trip(startedAt: Date(), startAddress: "Old Street")
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        let home = SavedPlace(
            name: "Home",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300
        )

        PlaceMatchingService.matchPlaces(for: trip, places: [home])

        XCTAssertEqual(trip.startPlaceName, "Home")
        XCTAssertNil(trip.endPlaceName)
    }

    func testRematchTripsAppliesSavedPlaceNameToMatchingEndpoints() {
        let sharedLatitude = 38.42
        let sharedLongitude = 27.13

        let tripA = Trip(
            startedAt: Date().addingTimeInterval(-3_600),
            startAddress: "Isikkent, Bornova",
            endAddress: "Office Street"
        )
        tripA.startLatitude = sharedLatitude
        tripA.startLongitude = sharedLongitude
        tripA.endLatitude = 38.45
        tripA.endLongitude = 27.15

        let tripB = Trip(
            startedAt: Date(),
            startAddress: "Office Street",
            endAddress: "Isikkent, Bornova"
        )
        tripB.startLatitude = 38.45
        tripB.startLongitude = 27.15
        tripB.endLatitude = sharedLatitude
        tripB.endLongitude = sharedLongitude

        let place = SavedPlace(
            name: "Yeşil Döner",
            latitude: sharedLatitude,
            longitude: sharedLongitude,
            radiusMeters: 300
        )

        PlaceMatchingService.rematchTrips(
            [tripA, tripB],
            places: [place],
            privacyRadius: 500
        )

        XCTAssertEqual(tripA.startPlaceName, "Yeşil Döner")
        XCTAssertEqual(tripB.endPlaceName, "Yeşil Döner")
        XCTAssertTrue(tripA.searchIndex?.contains("yeşil döner") == true)
        XCTAssertTrue(tripB.searchIndex?.contains("yeşil döner") == true)
    }
}
