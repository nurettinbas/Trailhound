import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class TripRollupServiceTests: XCTestCase {
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
        distanceMeters: Double = 10_000,
        durationSeconds: TimeInterval = 1_800,
        category: TripCategory = .personal,
        nightMeters: Double = 2_000,
        trackedMeters: Double = 10_000,
        maxSpeedMps: Double = 30
    ) -> Trip {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(durationSeconds),
            distanceMeters: distanceMeters,
            category: category,
            maxSpeedMps: maxSpeedMps
        )
        trip.nightDistanceMeters = nightMeters
        trip.trackedDistanceMeters = trackedMeters
        trip.estimatedFuelCost = 50
        context.insert(trip)
        return trip
    }

    private func rollups() throws -> [TripDailyRollup] {
        try context.fetch(FetchDescriptor<TripDailyRollup>())
    }

    func testAddAccumulatesTripsIntoOneDailyBucket() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let first = insertTrip(startedAt: day)
        let second = insertTrip(startedAt: day.addingTimeInterval(4 * 3_600), distanceMeters: 5_000)

        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        let all = try rollups()
        XCTAssertEqual(all.count, 1, "same day, category and vehicle share one bucket")
        let rollup = try XCTUnwrap(all.first)
        XCTAssertEqual(rollup.tripCount, 2)
        XCTAssertEqual(rollup.distanceMeters, 15_000, accuracy: 0.1)
        XCTAssertEqual(rollup.nightDistanceMeters, 4_000, accuracy: 0.1)
    }

    func testSeparateBucketsPerCategory() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        TripRollupService.add(insertTrip(startedAt: day, category: .personal), in: context)
        TripRollupService.add(insertTrip(startedAt: day, category: .business), in: context)
        try context.save()

        XCTAssertEqual(try rollups().count, 2)
    }

    func testRemoveSubtractsAndDropsEmptyBucket() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let first = insertTrip(startedAt: day)
        let second = insertTrip(startedAt: day, distanceMeters: 5_000)
        TripRollupService.add(first, in: context)
        TripRollupService.add(second, in: context)
        try context.save()

        TripRollupService.remove(second, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.tripCount, 1)
        XCTAssertEqual(rollup.distanceMeters, 10_000, accuracy: 0.1)

        TripRollupService.remove(first, in: context)
        try context.save()

        XCTAssertTrue(try rollups().isEmpty, "a day with no trips left keeps no row")
    }

    func testUpdateMovesContributionToNewDay() throws {
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let trip = insertTrip(startedAt: today)
        TripRollupService.add(trip, in: context)
        try context.save()

        let snapshot = TripRollupService.snapshot(of: trip)
        trip.startedAt = today.addingTimeInterval(-3 * 86_400)
        trip.endedAt = trip.startedAt.addingTimeInterval(1_800)
        TripRollupService.update(trip, from: snapshot, in: context)
        try context.save()

        let all = try rollups()
        XCTAssertEqual(all.count, 1, "the old day's bucket is emptied and removed")
        let expectedDay = Calendar.current.startOfDay(for: trip.startedAt)
        XCTAssertEqual(try XCTUnwrap(all.first).dayStart, expectedDay)
    }

    func testUpdateAdjustsAmountsWithinSameDay() throws {
        let today = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let trip = insertTrip(startedAt: today, distanceMeters: 10_000)
        TripRollupService.add(trip, in: context)
        try context.save()

        let snapshot = TripRollupService.snapshot(of: trip)
        trip.distanceMeters = 25_000
        TripRollupService.update(trip, from: snapshot, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.tripCount, 1, "an edit must not double-count the trip")
        XCTAssertEqual(rollup.distanceMeters, 25_000, accuracy: 0.1)
    }

    func testInProgressTripIsNotRolledUp() throws {
        let active = Trip(startedAt: Date(), endedAt: nil, distanceMeters: 1_000)
        context.insert(active)
        TripRollupService.add(active, in: context)
        try context.save()

        XCTAssertTrue(try rollups().isEmpty)
    }

    func testRebuildAllMatchesIncrementalDeltas() async throws {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        for index in 0..<12 {
            let trip = insertTrip(
                startedAt: base.addingTimeInterval(-Double(index) * 86_400),
                distanceMeters: Double(1_000 * (index + 1)),
                category: index.isMultiple(of: 2) ? .personal : .business
            )
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let incremental = try rollups()
            .map { [$0.dayStart, $0.categoryID, $0.distanceMeters, Double($0.tripCount)] as [AnyHashable] }
            .sorted { String(describing: $0) < String(describing: $1) }

        await TripRollupService.rebuildAll(container: container)

        let rebuilt = try context.fetch(FetchDescriptor<TripDailyRollup>())
            .map { [$0.dayStart, $0.categoryID, $0.distanceMeters, Double($0.tripCount)] as [AnyHashable] }
            .sorted { String(describing: $0) < String(describing: $1) }

        XCTAssertEqual(rebuilt.count, incremental.count)
        XCTAssertEqual(String(describing: rebuilt), String(describing: incremental))
    }

    func testRollupBackedRowsAggregateLikeTrips() throws {
        let calendar = Calendar.current
        let base = calendar.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        var trips: [Trip] = []
        for index in 0..<6 {
            let trip = insertTrip(
                startedAt: base.addingTimeInterval(-Double(index) * 86_400),
                distanceMeters: 8_000
            )
            trips.append(trip)
            TripRollupService.add(trip, in: context)
        }
        try context.save()

        let fromTrips = StatsViewModel.stats(for: trips.map(TripStatsRow.init(trip:)))
        let fromRollups = StatsViewModel.stats(for: try rollups().map(TripStatsRow.init(rollup:)))

        XCTAssertEqual(fromRollups.tripCount, fromTrips.tripCount)
        XCTAssertEqual(fromRollups.totalDistanceMeters, fromTrips.totalDistanceMeters, accuracy: 0.1)
        XCTAssertEqual(fromRollups.totalDuration, fromTrips.totalDuration, accuracy: 0.1)
        XCTAssertEqual(fromRollups.nightDrivingRatio, fromTrips.nightDrivingRatio, accuracy: 0.0001)
        XCTAssertEqual(fromRollups.maxSpeedKmh, fromTrips.maxSpeedKmh, accuracy: 0.1)
    }

    /// A rollup keeps the highest value it ever saw and never lowers it, so one phantom maximum
    /// would poison a whole day's statistics permanently. The contribution must refuse it.
    func testRollupIgnoresAnImplausibleStoredMaximum() throws {
        let day = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3_600)
        let phantom = insertTrip(startedAt: day, maxSpeedMps: 56.4)
        let real = insertTrip(startedAt: day.addingTimeInterval(3_600), maxSpeedMps: 22.22)

        TripRollupService.add(phantom, in: context)
        TripRollupService.add(real, in: context)
        try context.save()

        let rollup = try XCTUnwrap(try rollups().first)
        XCTAssertEqual(rollup.maxSpeedMps, 22.22, accuracy: 0.001)
    }
}
