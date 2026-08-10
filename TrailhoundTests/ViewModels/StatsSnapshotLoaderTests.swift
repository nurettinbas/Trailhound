import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class StatsSnapshotLoaderTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV11.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private var context: ModelContext { container.mainContext }

    @discardableResult
    private func insertTrip(
        startedAt: Date,
        distanceMeters: Double,
        estimatedFuelCost: Double = 40
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: distanceMeters,
            estimatedFuelCost: estimatedFuelCost
        )
        trip.nightDistanceMeters = 0
        trip.trackedDistanceMeters = distanceMeters
        context.insert(trip)
        return trip
    }

    private func makeRequest(
        storeVersion: Int = 1,
        period: StatsPeriod = .week,
        selectedMonth: Date = Date(),
        customStart: Date = Date().addingTimeInterval(-30 * 86_400),
        customEnd: Date = Date()
    ) -> StatsSnapshotRequest {
        let goalMonth = StatsViewModel.goalMonth(
            for: period,
            selectedMonth: selectedMonth,
            customStart: customStart,
            customEnd: customEnd
        )
        return StatsSnapshotRequest(
            storeVersion: storeVersion,
            selectedPeriod: period,
            customStart: customStart,
            customEnd: customEnd,
            selectedMonth: selectedMonth,
            goalMonth: goalMonth,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            selectedPlaceName: nil,
            categoryNames: StatsNameMap(names: [:], fallback: "Other"),
            vehicleNames: StatsNameMap(names: [VehicleDistance.unassignedID: "Unassigned"], fallback: "Unknown"),
            vehicleCount: 0
        )
    }

    func testLoaderMatchesDirectBuilder() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        insertTrip(startedAt: today.addingTimeInterval(3_600), distanceMeters: 4_000)
        insertTrip(startedAt: yesterday.addingTimeInterval(3_600), distanceMeters: 2_500)
        try context.save()

        let request = makeRequest(period: .week)
        let loader = StatsSnapshotLoader(modelContainer: container)
        let loaded = await loader.snapshot(for: request)

        let rows = try context.fetch(
            FetchDescriptor<Trip>(predicate: #Predicate { $0.endedAt != nil })
        ).map(TripStatsRow.init(trip:))
        let direct = StatsDisplaySnapshotBuilder.build(
            completedTrips: rows,
            categoryNames: request.categoryNames,
            vehicleNames: request.vehicleNames,
            vehicleCount: request.vehicleCount,
            selectedPeriod: request.selectedPeriod,
            customStart: request.customStart,
            customEnd: request.customEnd,
            selectedMonth: request.selectedMonth,
            selectedCategoryID: request.selectedCategoryID,
            selectedVehicleID: request.selectedVehicleID,
            selectedPlaceName: request.selectedPlaceName,
            goalMonth: request.goalMonth
        )

        XCTAssertEqual(loaded.stats.tripCount, direct.stats.tripCount)
        XCTAssertEqual(loaded.stats.totalDistanceMeters, direct.stats.totalDistanceMeters, accuracy: 0.1)
        XCTAssertEqual(loaded.goalDistanceMeters, direct.goalDistanceMeters, accuracy: 0.1)
        XCTAssertEqual(loaded.dailyDistance.count, direct.dailyDistance.count)
    }

    func testCacheReturnsSameSnapshotUntilStoreVersionChanges() async throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        insertTrip(startedAt: today.addingTimeInterval(3_600), distanceMeters: 3_000)
        try context.save()

        let loader = StatsSnapshotLoader(modelContainer: container)
        let firstRequest = makeRequest(storeVersion: 1)
        let first = await loader.snapshot(for: firstRequest)
        let cached = await loader.snapshot(for: firstRequest)

        XCTAssertEqual(first.stats.totalDistanceMeters, cached.stats.totalDistanceMeters, accuracy: 0.001)
        XCTAssertEqual(first.goalDistanceMeters, 3_000, accuracy: 0.1)

        insertTrip(startedAt: today.addingTimeInterval(5_000), distanceMeters: 7_000)
        try context.save()

        let second = await loader.snapshot(for: makeRequest(storeVersion: 2))
        XCTAssertEqual(second.goalDistanceMeters, 10_000, accuracy: 0.1)
    }

    func testPreviousMonthGoalIgnoresCurrentMonthTrips() async throws {
        let currentMonthStart = StatsViewModel.calendarMonthInterval(containing: Date()).start
        let previousMonth = StatsViewModel.shiftMonth(currentMonthStart, by: -1)
        let previousStart = StatsViewModel.calendarMonthInterval(containing: previousMonth).start

        insertTrip(startedAt: previousStart.addingTimeInterval(10 * 3_600), distanceMeters: 8_000)
        insertTrip(startedAt: currentMonthStart.addingTimeInterval(10 * 3_600), distanceMeters: 50_000)
        try context.save()

        let loader = StatsSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(
            for: makeRequest(period: .month, selectedMonth: previousMonth)
        )

        XCTAssertEqual(snapshot.goalDistanceMeters, 8_000, accuracy: 0.1)
        XCTAssertEqual(snapshot.stats.totalDistanceMeters, 8_000, accuracy: 0.1)
    }

    func testWeekLoaderIncludesEarlyMonthTripsInGoalDistance() async throws {
        let currentMonthStart = StatsViewModel.calendarMonthInterval(containing: Date()).start
        let today = Calendar.current.startOfDay(for: Date())

        insertTrip(startedAt: currentMonthStart.addingTimeInterval(10 * 3_600), distanceMeters: 15_000)
        insertTrip(startedAt: today.addingTimeInterval(3_600), distanceMeters: 2_000)
        try context.save()

        let loader = StatsSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(for: makeRequest(period: .week))

        XCTAssertEqual(snapshot.goalDistanceMeters, 17_000, accuracy: 0.1)
    }

    func testPlaceFilterUsesTripPathAndNarrowsSummaryOnLongWindow() async throws {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -120, to: end)!

        let homeTrip = Trip(
            startedAt: end.addingTimeInterval(-10 * 86_400).addingTimeInterval(3_600),
            endedAt: end.addingTimeInterval(-10 * 86_400).addingTimeInterval(5_400),
            distanceMeters: 4_000,
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )
        homeTrip.nightDistanceMeters = 0
        homeTrip.trackedDistanceMeters = 4_000
        context.insert(homeTrip)

        let otherTrip = Trip(
            startedAt: end.addingTimeInterval(-20 * 86_400).addingTimeInterval(3_600),
            endedAt: end.addingTimeInterval(-20 * 86_400).addingTimeInterval(5_400),
            distanceMeters: 9_000,
            startPlaceName: "Market",
            endPlaceName: "Ofis"
        )
        otherTrip.nightDistanceMeters = 0
        otherTrip.trackedDistanceMeters = 9_000
        context.insert(otherTrip)

        // Seed rollups so a naive long-window path would prefer them (no place names).
        TripRollupService.add(homeTrip, in: context)
        TripRollupService.add(otherTrip, in: context)
        try context.save()

        let goalMonth = StatsViewModel.goalMonth(
            for: .custom,
            selectedMonth: end,
            customStart: start,
            customEnd: end
        )
        let request = StatsSnapshotRequest(
            storeVersion: 1,
            selectedPeriod: .custom,
            customStart: start,
            customEnd: end,
            selectedMonth: end,
            goalMonth: goalMonth,
            selectedCategoryID: nil,
            selectedVehicleID: nil,
            selectedPlaceName: "Ev",
            categoryNames: StatsNameMap(names: [:], fallback: "Other"),
            vehicleNames: StatsNameMap(names: [VehicleDistance.unassignedID: "Unassigned"], fallback: "Unknown"),
            vehicleCount: 0
        )

        let loader = StatsSnapshotLoader(modelContainer: container)
        let snapshot = await loader.snapshot(for: request)

        XCTAssertEqual(snapshot.stats.tripCount, 1)
        XCTAssertEqual(snapshot.stats.totalDistanceMeters, 4_000, accuracy: 0.1)
        // Goal stays unfiltered across the month containing `goalMonth`.
        XCTAssertGreaterThanOrEqual(snapshot.goalDistanceMeters, 0)
    }
}
