import CoreLocation
import XCTest
@testable import Trailhound

final class DistanceCalculatorTests: XCTestCase {
    func testTotalDistanceWithTwoPoints() {
        let a = CLLocation(latitude: 0, longitude: 0)
        let b = CLLocation(latitude: 0, longitude: 0.01)
        let distance = DistanceCalculator.totalDistance(for: [a, b])
        XCTAssertGreaterThan(distance, 0)
    }

    func testSimplifyReducesPoints() {
        let points = (0..<20).map { index in
            CLLocationCoordinate2D(latitude: Double(index) * 0.001, longitude: Double(index) * 0.001)
        }
        let simplified = DistanceCalculator.simplify(coordinates: points)
        XCTAssertLessThan(simplified.count, points.count)
    }

    func testMeterToleranceKeepsDeviationsAboveIt() {
        // 100 m eastward leg with a ~20 m northward bulge in the middle.
        let latitude = 38.42
        let metersPerDegreeLatitude: Double = 111_132
        let metersPerDegreeLongitude = 111_320 * cos(latitude * .pi / 180)
        let points = [
            CLLocationCoordinate2D(latitude: latitude, longitude: 27.0),
            CLLocationCoordinate2D(
                latitude: latitude + 20 / metersPerDegreeLatitude,
                longitude: 27.0 + 50 / metersPerDegreeLongitude
            ),
            CLLocationCoordinate2D(latitude: latitude, longitude: 27.0 + 100 / metersPerDegreeLongitude)
        ]

        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 5).count, 3)
        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 40).count, 2)
    }

    func testMeterToleranceMeasuresLongitudeInMetersNotDegrees() {
        // Same 20 m bulge, but expressed eastward. A degree-space tolerance would judge this
        // deviation ~27% smaller at this latitude; the meter-based one must not.
        let latitude = 38.42
        let metersPerDegreeLatitude: Double = 111_132
        let metersPerDegreeLongitude = 111_320 * cos(latitude * .pi / 180)
        let points = [
            CLLocationCoordinate2D(latitude: latitude, longitude: 27.0),
            CLLocationCoordinate2D(
                latitude: latitude + 50 / metersPerDegreeLatitude,
                longitude: 27.0 + 20 / metersPerDegreeLongitude
            ),
            CLLocationCoordinate2D(latitude: latitude + 100 / metersPerDegreeLatitude, longitude: 27.0)
        ]

        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 15).count, 3)
        XCTAssertEqual(DistanceCalculator.simplify(coordinates: points, toleranceMeters: 25).count, 2)
    }

    func testSimplifiedIndicesKeepEndpoints() {
        let points = (0..<50).map { index in
            CLLocationCoordinate2D(latitude: 38.42, longitude: 27.0 + Double(index) * 0.0001)
        }
        let indices = DistanceCalculator.simplifiedIndices(coordinates: points, toleranceMeters: 3)

        XCTAssertEqual(indices.first, 0)
        XCTAssertEqual(indices.last, points.count - 1)
        XCTAssertEqual(indices, indices.sorted())
    }
}

final class RoutePrivacyClipperTests: XCTestCase {
    func testClipsStartAndEndWithinRadius() {
        let start = CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0)
        let mid = CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        let end = CLLocationCoordinate2D(latitude: 41.02, longitude: 29.02)
        let nearStart = CLLocationCoordinate2D(latitude: 41.0001, longitude: 29.0001)
        let nearEnd = CLLocationCoordinate2D(latitude: 41.0199, longitude: 29.0199)
        let clipped = RoutePrivacyClipper.clip(
            [start, nearStart, mid, nearEnd, end],
            privacyRadiusMeters: 500
        )
        XCTAssertLessThan(clipped.count, 5)
        XCTAssertGreaterThanOrEqual(clipped.count, 2)
    }
}

final class TripDateGroupingTests: XCTestCase {
    func testGroupsTodayTrip() {
        let trip = Trip(startedAt: Date(), endedAt: Date())
        let sections = TripDateGrouping.groupedSections(from: [trip])
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.section, .today)
    }
}

@MainActor
final class TabSelectionTests: XCTestCase {
    func testOpenPairingSelectsPairingTab() {
        let tabs = TabSelection.shared
        tabs.selectedTab = .trips
        tabs.openPairing()
        XCTAssertEqual(tabs.selectedTab, .pairing)
    }
}

final class DeviceTestChecklistTests: XCTestCase {
    func testChecklistHasNineItems() {
        XCTAssertEqual(DeviceTestChecklist.items.count, 9)
    }
}

final class FuelCostCalculatorTests: XCTestCase {
    func testEstimateCostPositive() {
        let defaults = UserDefaults(suiteName: "group.com.trailhound.app") ?? .standard
        defaults.set(10.0, forKey: "fuelLitersPer100km")
        defaults.set(40.0, forKey: "fuelPricePerLiter")
        let cost = FuelCostCalculator.estimateCost(distanceMeters: 100_000)
        XCTAssertEqual(cost, 400, accuracy: 0.1)
    }

    func testElectricVehicleUsesKWhPrice() {
        let vehicle = VehicleProfile(name: "EV", fuelType: .electric, consumption: 20, chargePricePerKWh: 10)
        let cost = FuelCostCalculator.estimateCost(distanceMeters: 100_000, vehicle: vehicle)
        XCTAssertEqual(cost, 200, accuracy: 0.1)
    }
}
