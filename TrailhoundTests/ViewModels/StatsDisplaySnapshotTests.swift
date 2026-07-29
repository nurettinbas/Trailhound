import XCTest
@testable import Trailhound

@MainActor
final class StatsDisplaySnapshotTests: XCTestCase {
    func testBuilderMatchesDirectDailyDistances() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: Date())

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 4000
        )
        let yesterdayTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(7200),
            distanceMeters: 2500
        )
        let trips = [todayTrip, yesterdayTrip]

        let snapshot = StatsDisplaySnapshotBuilder.build(
            completedTrips: trips,
            categories: [],
            vehicles: [],
            selectedPeriod: .custom,
            customStart: interval.start,
            customEnd: interval.end,
            selectedMonth: today,
            selectedCategoryID: nil,
            selectedVehicleID: nil
        )

        let direct = StatsViewModel.dailyDistances(in: interval, from: trips)

        XCTAssertEqual(snapshot.dailyDistance.count, direct.count)
        XCTAssertEqual(snapshot.dailyDistance.first?.distanceMeters ?? 0, direct.first?.distanceMeters ?? -1, accuracy: 0.1)
        XCTAssertEqual(snapshot.stats.tripCount, 2)
        XCTAssertTrue(snapshot.hasAnyDailyChart)
    }
}
