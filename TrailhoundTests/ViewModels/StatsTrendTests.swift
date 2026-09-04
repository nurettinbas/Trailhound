import XCTest
@testable import Trailhound

final class StatsTrendTests: XCTestCase {
    func testHigherIsBetterColors() {
        let up = StatsTrend.make(current: 150, previous: 100, polarity: .higherIsBetter)!
        XCTAssertEqual(up.direction, .up)
        XCTAssertEqual(up.isFavorable, true)
        XCTAssertEqual(up.systemImage, "arrow.up.right")

        let down = StatsTrend.make(current: 50, previous: 100, polarity: .higherIsBetter)!
        XCTAssertEqual(down.direction, .down)
        XCTAssertEqual(down.isFavorable, false)
        XCTAssertEqual(down.systemImage, "arrow.down.right")
    }

    func testLowerIsBetterExpenseIncreaseIsUnfavorable() {
        let up = StatsTrend.make(current: 120, previous: 100, polarity: .lowerIsBetter)!
        XCTAssertEqual(up.direction, .up)
        XCTAssertEqual(up.isFavorable, false)

        let down = StatsTrend.make(current: 80, previous: 100, polarity: .lowerIsBetter)!
        XCTAssertEqual(down.isFavorable, true)
    }

    func testNeutralHasNoFavorableTint() {
        let up = StatsTrend.make(current: 120, previous: 100, polarity: .neutral)!
        XCTAssertNil(up.isFavorable)
        XCTAssertEqual(up.systemImage, "arrow.up.right")
    }

    func testNovelWhenPreviousIsZero() {
        let novel = StatsTrend.make(current: 10, previous: 0, polarity: .higherIsBetter)!
        XCTAssertTrue(novel.isNovel)
        XCTAssertNil(novel.percent)
        XCTAssertNil(novel.systemImage)
        XCTAssertNil(StatsTrend.make(current: 0, previous: 0, polarity: .higherIsBetter))
    }

    func testVehicleCompareBuilderSortsByAmountAndJoinsDistance() {
        let seeds = [
            VehicleCompareSeed(
                id: "b",
                storedName: "Beta",
                iconName: "car.fill",
                photoFileName: nil,
                isElectric: false,
                amount: 50,
                fuel: 50,
                service: 0,
                insurance: 0,
                casco: 0,
                other: 0
            ),
            VehicleCompareSeed(
                id: "a",
                storedName: "Alpha",
                iconName: "car.fill",
                photoFileName: nil,
                isElectric: false,
                amount: 200,
                fuel: 100,
                service: 100,
                insurance: 0,
                casco: 0,
                other: 0
            )
        ]
        let distances = [
            VehicleDistance(id: "a", name: "Alpha", distanceMeters: 100_000),
            VehicleDistance(id: "b", name: "Beta", distanceMeters: 50_000)
        ]
        let rows = StatsVehicleCompareBuilder.rows(seeds: seeds, distances: distances)
        XCTAssertEqual(rows.map(\.id), ["a", "b"])
        XCTAssertTrue(rows[0].isMostExpensive)
        XCTAssertFalse(rows[1].isMostExpensive)
        XCTAssertEqual(rows[0].costPerKm ?? 0, 2.0, accuracy: 0.01)
        XCTAssertNil(
            StatsVehicleCompareBuilder.rows(
                seeds: [
                    VehicleCompareSeed(
                        id: "c",
                        storedName: "Empty km",
                        iconName: "car.fill",
                        photoFileName: nil,
                        isElectric: false,
                        amount: 10,
                        fuel: 10,
                        service: 0,
                        insurance: 0,
                        casco: 0,
                        other: 0
                    )
                ],
                distances: []
            ).first?.costPerKm
        )
    }
}
