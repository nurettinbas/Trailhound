import CoreLocation
import XCTest
@testable import Trailhound

final class TripFuelEstimateTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let origin = CLLocationCoordinate2D(latitude: 38.42, longitude: 27.14)
    private let c0 = 7.5
    private let price = 65.0

    func testSteadyHighwayDynamicBelowAvg() {
        // ~50 km at 90 km/h ≈ 2_000 s
        let seconds = 2_000
        let speeds = Array(repeating: 90.0 / 3.6, count: seconds + 1)
        let route = samples(speedsMps: speeds)
        let distance = 90.0 / 3.6 * Double(seconds)

        let result = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertGreaterThan(result.avgVolume, 0)
        XCTAssertGreaterThan(result.dynamicVolume, 0)
        XCTAssertLessThan(result.dynamicVolume, result.avgVolume)
        XCTAssertLessThan(result.dynamicCost, result.avgCost)
    }

    func testCityIdleAndHardAccelDynamicAboveAvg() {
        // Short distance with long idle and repeated hard accelerations.
        var speeds: [Double] = []
        speeds += Array(repeating: 0.2, count: 601) // 10 min idle
        for _ in 0..<8 {
            speeds += ramp(fromKmh: 0, toKmh: 50, seconds: 8)
            speeds += Array(repeating: 50.0 / 3.6, count: 20)
            speeds += ramp(fromKmh: 50, toKmh: 0, seconds: 10)
            speeds += Array(repeating: 0.2, count: 40)
        }

        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            partial + pair.0.location.distance(from: pair.1.location)
        }

        let result = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertGreaterThan(result.avgVolume, 0)
        XCTAssertGreaterThan(result.dynamicVolume, result.avgVolume)
    }

    func testZeroDistanceYieldsZeroDynamic() {
        let result = TripFuelEstimate.compute(
            samples: samples(speedsMps: [10, 10]),
            distanceMeters: 0,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertEqual(result.avgVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(result.dynamicVolume, 0, accuracy: 0.0001)
        XCTAssertEqual(result.dynamicCost, 0, accuracy: 0.0001)
    }

    func testFewerThanTwoSamplesYieldsZeroDynamic() {
        let alone = [
            RouteSample(coordinate: origin, timestamp: start, speedMps: 20)
        ]
        let result = TripFuelEstimate.compute(
            samples: alone,
            distanceMeters: 5_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        XCTAssertEqual(result.dynamicVolume, 0, accuracy: 0.0001)
        XCTAssertGreaterThan(result.avgVolume, 0)
    }

    func testMergeGapDoesNotInflateAccelFuel() {
        let first = samples(speedsMps: Array(repeating: 40.0 / 3.6, count: 61))
        let gapStart = start.addingTimeInterval(60)
        let afterGap = samples(
            speedsMps: Array(repeating: 40.0 / 3.6, count: 61),
            startAt: gapStart.addingTimeInterval(2 * 3_600)
        )
        let route = first + afterGap
        let distance = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            let dt = pair.0.timestamp.timeIntervalSince(pair.1.timestamp)
            if dt > TripFuelEstimate.maximumStopGapSeconds { return partial }
            return partial + pair.0.location.distance(from: pair.1.location)
        }

        let withGap = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let continuous = TripFuelEstimate.compute(
            samples: samples(speedsMps: Array(repeating: 40.0 / 3.6, count: 121)),
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertEqual(withGap.dynamicVolume, continuous.dynamicVolume, accuracy: continuous.dynamicVolume * 0.08)
    }

    func testEVIdleMuchLessThanPetrol() {
        var speeds = Array(repeating: 0.2, count: 601)
        speeds += Array(repeating: 40.0 / 3.6, count: 121)
        let route = samples(speedsMps: speeds)
        let distance = zip(route.dropFirst(), route).reduce(0.0) { partial, pair in
            partial + pair.0.location.distance(from: pair.1.location)
        }

        let petrol = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let electric = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: 18,
            unitPrice: 8.5,
            fuelType: .electric
        )

        // Compare idle contribution by using the same C₀ scale on a stop-only stretch.
        let stopOnly = samples(speedsMps: Array(repeating: 0.2, count: 601))
        let petrolStop = TripFuelEstimate.compute(
            samples: stopOnly,
            distanceMeters: 1_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .petrol
        )
        let evStop = TripFuelEstimate.compute(
            samples: stopOnly,
            distanceMeters: 1_000,
            consumptionPer100: c0,
            unitPrice: price,
            fuelType: .electric
        )

        XCTAssertLessThan(evStop.dynamicVolume, petrolStop.dynamicVolume * 0.2)
        XCTAssertGreaterThan(petrol.dynamicVolume, 0)
        XCTAssertGreaterThan(electric.dynamicVolume, 0)
    }

    func testDoubleConsumptionNearlyDoublesDynamicVolume() {
        let speeds = Array(repeating: 70.0 / 3.6, count: 601)
        let route = samples(speedsMps: speeds)
        let distance = 70.0 / 3.6 * 600

        let base = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: 7.5,
            unitPrice: price,
            fuelType: .petrol
        )
        let double = TripFuelEstimate.compute(
            samples: route,
            distanceMeters: distance,
            consumptionPer100: 15,
            unitPrice: price,
            fuelType: .petrol
        )

        XCTAssertEqual(double.dynamicVolume / base.dynamicVolume, 2, accuracy: 0.05)
        XCTAssertEqual(double.avgVolume / base.avgVolume, 2, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func ramp(fromKmh: Double, toKmh: Double, seconds: Int) -> [Double] {
        guard seconds > 0 else { return [] }
        return (0...seconds).map { step in
            let t = Double(step) / Double(seconds)
            return (fromKmh + (toKmh - fromKmh) * t) / 3.6
        }
    }

    private func samples(
        speedsMps: [Double],
        storeSpeeds: Bool = true,
        startAt: Date? = nil,
        startFrom: CLLocationCoordinate2D? = nil
    ) -> [RouteSample] {
        let originTime = startAt ?? start
        let from = startFrom ?? origin
        var travelled = 0.0
        return speedsMps.enumerated().map { index, speed in
            if index > 0 { travelled += speed }
            return RouteSample(
                coordinate: offset(from: from, metersEast: travelled),
                timestamp: originTime.addingTimeInterval(Double(index)),
                speedMps: storeSpeeds ? speed : nil
            )
        }
    }

    private func offset(from coordinate: CLLocationCoordinate2D, metersEast: Double) -> CLLocationCoordinate2D {
        let metersPerDegreeLongitude = 111_320 * cos(coordinate.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude + metersEast / metersPerDegreeLongitude
        )
    }
}
