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

    /// A trip recorded before speeds were vetted can carry a maximum no car reached. Statistics
    /// cannot afford to load its points to check, so the value is hidden rather than headlined.
    func testStatsHidesAnImplausibleStoredMaximum() {
        let phantom = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 36_000,
            maxSpeedMps: 56.4 // 203 km/h
        )
        let real = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 9_000,
            maxSpeedMps: 22.22
        )

        let stats = StatsViewModel.stats(for: [phantom, real])

        XCTAssertEqual(stats.maxSpeedKmh, 22.22 * 3.6, accuracy: 0.1)
    }

    func testDailyMaxSpeedsHideAnImplausibleStoredMaximum() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let interval = DateInterval(start: today, end: Date())
        let phantom = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 36_000,
            maxSpeedMps: 56.4
        )

        let daily = StatsViewModel.dailyMaxSpeeds(in: interval, from: [phantom])

        XCTAssertEqual(daily.first?.speedKmh ?? -1, 0, accuracy: 0.001)
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

    func testStatsFiltersByPlaceNameMatchingStartOrEnd() {
        let startHome = Trip(
            startedAt: Date().addingTimeInterval(-7_200),
            endedAt: Date().addingTimeInterval(-3_600),
            distanceMeters: 3_000,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        let endHome = Trip(
            startedAt: Date().addingTimeInterval(-1_800),
            endedAt: Date(),
            distanceMeters: 2_000,
            startPlaceName: "Market",
            endPlaceName: "Ev"
        )
        let other = Trip(
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date().addingTimeInterval(-300),
            distanceMeters: 1_000,
            startPlaceName: "Market",
            endPlaceName: "Ofis"
        )

        let stats = StatsViewModel.stats(for: [startHome, endHome, other], placeName: "Ev")

        XCTAssertEqual(stats.tripCount, 2)
        XCTAssertEqual(stats.totalDistanceMeters, 5_000, accuracy: 0.1)
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

    func testDailyFuelCostsBucketByDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let interval = DateInterval(start: yesterday, end: Date())

        let todayTrip = Trip(
            startedAt: today.addingTimeInterval(3600),
            endedAt: today.addingTimeInterval(7200),
            distanceMeters: 4000,
            estimatedFuelCost: 80
        )
        let yesterdayTrip = Trip(
            startedAt: yesterday.addingTimeInterval(3600),
            endedAt: yesterday.addingTimeInterval(7200),
            distanceMeters: 2500,
            estimatedFuelCost: 50
        )
        let secondToday = Trip(
            startedAt: today.addingTimeInterval(8000),
            endedAt: today.addingTimeInterval(9000),
            distanceMeters: 1000,
            estimatedFuelCost: 20
        )

        let daily = StatsViewModel.dailyFuelCosts(
            in: interval,
            from: [todayTrip, yesterdayTrip, secondToday]
        )

        XCTAssertEqual(daily.count, 2)
        XCTAssertEqual(daily.first?.cost ?? 0, 50, accuracy: 0.1)
        XCTAssertEqual(daily.last?.cost ?? 0, 100, accuracy: 0.1)
    }

    func testCategoryAndVehicleFuelBreakdown() {
        let vehicleA = UUID()
        let vehicleB = UUID()
        let business = Trip(
            startedAt: Date().addingTimeInterval(-7200),
            endedAt: Date().addingTimeInterval(-3600),
            distanceMeters: 3000,
            category: .business,
            estimatedFuelCost: 60,
            vehicleID: vehicleA
        )
        let personal = Trip(
            startedAt: Date().addingTimeInterval(-1800),
            endedAt: Date(),
            distanceMeters: 2000,
            category: .personal,
            estimatedFuelCost: 40,
            vehicleID: vehicleB
        )
        let categories = [
            UserCategory(id: BuiltInCategory.businessID, name: "Business", sortOrder: 0),
            UserCategory(id: BuiltInCategory.personalID, name: "Personal", sortOrder: 1)
        ]
        let vehicles = [
            VehicleProfile(id: vehicleA, name: "Car A"),
            VehicleProfile(id: vehicleB, name: "Car B")
        ]

        let categoryFuel = StatsViewModel.categoryFuelBreakdown(for: [business, personal], categories: categories)
        let vehicleFuel = StatsViewModel.vehicleFuelBreakdown(for: [business, personal], vehicles: vehicles)

        XCTAssertEqual(categoryFuel.count, 2)
        XCTAssertEqual(categoryFuel[0].cost, 60, accuracy: 0.1)
        XCTAssertEqual(categoryFuel[1].cost, 40, accuracy: 0.1)
        XCTAssertEqual(vehicleFuel.count, 2)
        XCTAssertEqual(vehicleFuel[0].cost, 60, accuracy: 0.1)
        XCTAssertEqual(vehicleFuel[1].cost, 40, accuracy: 0.1)
    }

    func testCostPerKmAndAverageCostPerTrip() {
        let stats = TripStats(
            tripCount: 2,
            totalDistanceMeters: 10_000,
            totalDuration: 3600,
            averageDuration: 1800,
            estimatedFuelCost: 100
        )

        XCTAssertEqual(stats.costPerKm, 10, accuracy: 0.01)
        XCTAssertEqual(stats.averageCostPerTrip, 50, accuracy: 0.01)

        let empty = TripStats(
            tripCount: 0,
            totalDistanceMeters: 0,
            totalDuration: 0,
            averageDuration: 0,
            estimatedFuelCost: 0
        )
        XCTAssertEqual(empty.costPerKm, 0, accuracy: 0.001)
        XCTAssertEqual(empty.averageCostPerTrip, 0, accuracy: 0.001)
        XCTAssertEqual(empty.costPerKmText, "—")
        XCTAssertEqual(empty.averageCostPerTripText, "—")
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

    func testMonthIntervalUsesCalendarMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let selected = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18))!
        let interval = StatsViewModel.calendarMonthInterval(containing: selected, calendar: calendar)

        XCTAssertEqual(calendar.component(.day, from: interval.start), 1)
        XCTAssertEqual(calendar.component(.month, from: interval.start), 6)
        XCTAssertEqual(calendar.component(.month, from: interval.end), 7)
        XCTAssertEqual(calendar.component(.day, from: interval.end), 1)
    }

    func testSelectableMonthsSpansFirstTripToNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let earliest = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let months = StatsViewModel.selectableMonths(
            earliestTripStart: earliest,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(months.count, 3)
        XCTAssertEqual(calendar.component(.month, from: months[0]), 7)
        XCTAssertEqual(calendar.component(.month, from: months[1]), 6)
        XCTAssertEqual(calendar.component(.month, from: months[2]), 5)
    }

    func testSelectableMonthsWithoutTripsIsCurrentMonthOnly() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let months = StatsViewModel.selectableMonths(
            earliestTripStart: nil,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(months.count, 1)
        XCTAssertEqual(calendar.component(.month, from: months[0]), 7)
    }

    func testClampedMonthDeduplicatesToSelectableStart() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!
        let earliest = calendar.date(from: DateComponents(year: 2026, month: 5, day: 3))!
        let midJune = calendar.date(from: DateComponents(year: 2026, month: 6, day: 18, hour: 15))!
        let clamped = StatsViewModel.clampedMonth(
            midJune,
            earliestTripStart: earliest,
            now: now,
            calendar: calendar
        )
        let juneStart = StatsViewModel.calendarMonthInterval(containing: midJune, calendar: calendar).start

        XCTAssertEqual(clamped, juneStart)
    }
}
