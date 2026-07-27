import XCTest
@testable import Trailhound

final class StatsViewModelTests: XCTestCase {
    func testStatsAggregatesCompletedTripsOnly() {
        let completed = Trip(
            startedAt: Date().addingTimeInterval(-3600),
            endedAt: Date(),
            distanceMeters: 5000,
            estimatedFuelCost: 40
        )
        let active = Trip(startedAt: Date(), endedAt: nil, distanceMeters: 1000)

        let stats = StatsViewModel.stats(for: [completed, active])

        XCTAssertEqual(stats.tripCount, 1)
        XCTAssertEqual(stats.totalDistanceMeters, 5000, accuracy: 0.1)
        XCTAssertEqual(stats.estimatedFuelCost, 40, accuracy: 0.1)
        XCTAssertEqual(stats.averageSpeedKmh, 5, accuracy: 0.1)
        XCTAssertEqual(stats.maxSpeedKmh, 0, accuracy: 0.1)
    }

    func testStatsComputesAverageAndMaxSpeed() {
        let fast = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 36_000,
            maxSpeedMps: 33.33
        )
        let slow = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 9_000,
            maxSpeedMps: 22.22
        )

        let stats = StatsViewModel.stats(for: [fast, slow])

        // (36000 + 9000) m over 5400 s = 8.333 m/s = 30 km/h
        XCTAssertEqual(stats.averageSpeedKmh, 30, accuracy: 0.1)
        XCTAssertEqual(stats.maxSpeedKmh, 33.33 * 3.6, accuracy: 0.1)
    }

    func testDailyAverageAndMaxSpeedsBucketByDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: Date())

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 36_000,
            maxSpeedMps: 30
        )
        let yesterdayTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(5400),
            distanceMeters: 9_000,
            maxSpeedMps: 20
        )

        let averages = StatsViewModel.dailyAverageSpeeds(
            in: interval,
            from: [todayTrip, yesterdayTrip]
        )
        let maxSpeeds = StatsViewModel.dailyMaxSpeeds(
            in: interval,
            from: [todayTrip, yesterdayTrip]
        )

        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages.first?.speedKmh ?? 0, 18, accuracy: 0.1)
        XCTAssertEqual(averages.last?.speedKmh ?? 0, 36, accuracy: 0.1)
        XCTAssertEqual(maxSpeeds.first?.speedKmh ?? 0, 72, accuracy: 0.1)
        XCTAssertEqual(maxSpeeds.last?.speedKmh ?? 0, 108, accuracy: 0.1)
    }

    func testStatsFiltersByCategory() {
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 3000,
            category: .business
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal
        )

        let stats = StatsViewModel.stats(for: [business, personal], categoryID: BuiltInCategory.businessID.uuidString)

        XCTAssertEqual(stats.tripCount, 1)
        XCTAssertEqual(stats.totalDistanceMeters, 3000, accuracy: 0.1)
    }

    func testDailyDistancesBucketsByDay() {
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

        let buckets = StatsViewModel.dailyDistances(in: interval, from: [todayTrip, yesterdayTrip])

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets.first?.distanceMeters ?? 0, 2500, accuracy: 0.1)
        XCTAssertEqual(buckets.last?.distanceMeters ?? 0, 4000, accuracy: 0.1)
    }

    func testCategoryBreakdownSortsByDistance() {
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 8000,
            category: .business
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal
        )
        let categories = [
            UserCategory(id: BuiltInCategory.businessID, name: "Business", sortOrder: 0),
            UserCategory(id: BuiltInCategory.personalID, name: "Personal", sortOrder: 1)
        ]

        let breakdown = StatsViewModel.categoryBreakdown(for: [business, personal], categories: categories)

        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown[0].id, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(breakdown[0].distanceMeters, 8000, accuracy: 0.1)
    }

    func testCategoryDurationBreakdownSortsByDuration() {
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 8000,
            category: .business
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal
        )
        let categories = [
            UserCategory(id: BuiltInCategory.businessID, name: "Business", sortOrder: 0),
            UserCategory(id: BuiltInCategory.personalID, name: "Personal", sortOrder: 1)
        ]

        let breakdown = StatsViewModel.categoryDurationBreakdown(for: [business, personal], categories: categories)

        XCTAssertEqual(breakdown.count, 2)
        XCTAssertEqual(breakdown[0].id, BuiltInCategory.businessID.uuidString)
        XCTAssertEqual(breakdown[0].duration, 3600, accuracy: 0.1)
        XCTAssertEqual(breakdown[1].duration, 1800, accuracy: 0.1)
    }

    func testTrendTextWhenPreviousIsZero() {
        XCTAssertEqual(StatsViewModel.trendText(current: 10, previous: 0), StatsViewModel.trendText(current: 10, previous: 0))
        XCTAssertNil(StatsViewModel.trendText(current: 0, previous: 0))
    }

    func testTrendPercentCalculation() {
        XCTAssertEqual(StatsViewModel.trendPercent(current: 150, previous: 100)!, 50, accuracy: 0.1)
        XCTAssertEqual(StatsViewModel.trendPercent(current: 0, previous: 100)!, -100, accuracy: 0.1)
    }

    func testCustomIntervalUsesOrderedBounds() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 5_000)
        let interval = StatsViewModel.interval(for: .custom, customStart: end, customEnd: start)

        XCTAssertEqual(interval.start, start)
        XCTAssertEqual(interval.end, end)
    }
}
