import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class YearRecapSnapshotTests: XCTestCase {
    func testYearBoundaryExcludesAdjacentYear() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let inYear = calendar.date(from: DateComponents(year: 2026, month: 6, day: 10, hour: 8))!
        let previousYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 31, hour: 23))!
        let nextYear = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 1))!
        for date in [inYear, previousYear, nextYear] {
            let trip = Trip(
                startedAt: date,
                endedAt: date.addingTimeInterval(1800),
                distanceMeters: 10_000,
                estimatedFuelCost: 40,
                startLocality: date == inYear ? "Istanbul" : "Ankara"
            )
            context.insert(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: 2026, storeVersion: 1, now: inYear)
        XCTAssertEqual(snapshot.tripCount, 1)
        XCTAssertEqual(snapshot.distanceMeters, 10_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.cityCount, 1)
        XCTAssertEqual(snapshot.topCities, ["Istanbul"])
    }

    func testSkipsCityPageWhenEveryLocalityIsNil() async throws {
        let container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        let trip = Trip(
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now,
            distanceMeters: 8_000
        )
        context.insert(trip)
        TripRollupService.add(trip, in: context)
        try context.save()

        let loader = YearRecapSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(year: year, storeVersion: 1, now: now)
        XCTAssertEqual(snapshot.cityCount, 0)
        XCTAssertTrue(snapshot.topCities.isEmpty)
        XCTAssertTrue(snapshot.hasData)
    }

    func testRecapMotionTokensVanishWhenReduceMotionIsOn() {
        XCTAssertNil(TrailhoundMotion.recapPage(reduceMotion: true))
        XCTAssertNil(TrailhoundMotion.recapCountUp(reduceMotion: true))
        XCTAssertNil(TrailhoundMotion.badgeUnlock(reduceMotion: true))
        XCTAssertNotNil(TrailhoundMotion.recapPage(reduceMotion: false))
    }
}

@MainActor
final class PremiumWidgetBridgeTests: XCTestCase {
    func testPayloadSurvivesMissingAppGroupKeys() {
        let defaults = UserDefaults(suiteName: "trailhound.tests.widget.\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? "")
        let payload = PremiumWidgetPayload.load(from: defaults)
        XCTAssertEqual(payload.projectedTotal, 0, accuracy: 0.1)
        XCTAssertTrue(payload.showRoutePreview)
        XCTAssertNil(payload.lastTripID)
    }
}
