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
    func testChecklistHasSixItems() {
        XCTAssertEqual(DeviceTestChecklist.items.count, 6)
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
