import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

/// Exercises the V10 derived fields against a real on-disk store, because an empty in-memory
/// container cannot show whether an existing user library survives the schema bump.
@MainActor
final class TripDerivedMetricsMigrationTests: XCTestCase {
    private var storeDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrailhoundMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let storeDirectory {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        storeDirectory = nil
        try super.tearDownWithError()
    }

    private var storeURL: URL {
        storeDirectory.appendingPathComponent("Trailhound.store")
    }

    private func makeDiskContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema([
                Trip.self,
                TripPoint.self,
                SavedPlace.self,
                TripStop.self,
                UserCategory.self,
                MatchedRoutePoint.self,
                VehicleProfile.self,
            ]),
            configurations: ModelConfiguration(url: storeURL)
        )
    }

    /// Seeds a trip whose derived fields are `nil`, exactly how a row written before V10 looks
    /// after SwiftData's lightweight migration adds the new optional columns.
    @discardableResult
    private func seedLegacyTrip(
        in context: ModelContext,
        startedAt: Date,
        pointCount: Int = 12,
        distanceMeters: Double = 4_200
    ) -> UUID {
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: distanceMeters,
            startAddress: "Kadıköy",
            endAddress: "Levent",
            label: "İş"
        )
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 60),
                latitude: 41.0 + Double(index) * 0.001,
                longitude: 29.0 + Double(index) * 0.001,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            trip.points.append(point)
            context.insert(point)
        }

        trip.nightDistanceMeters = nil
        trip.trackedDistanceMeters = nil
        trip.startLatitude = nil
        trip.startLongitude = nil
        trip.endLatitude = nil
        trip.endLongitude = nil
        trip.searchIndex = nil
        return trip.id
    }

    func testExistingOnDiskStoreSurvivesDerivedFieldSchema() throws {
        let seededIDs: [UUID]
        do {
            let container = try makeDiskContainer()
            let context = container.mainContext
            seededIDs = [
                seedLegacyTrip(in: context, startedAt: Date().addingTimeInterval(-86_400)),
                seedLegacyTrip(in: context, startedAt: Date().addingTimeInterval(-172_800)),
            ]
            try context.save()
        }

        // Fresh container over the same file: the app relaunching after the update.
        let reopened = try makeDiskContainer()
        let trips = try reopened.mainContext.fetch(FetchDescriptor<Trip>())

        XCTAssertEqual(trips.count, 2, "existing trips must survive the schema bump")
        XCTAssertEqual(Set(trips.map(\.id)), Set(seededIDs))
        for trip in trips {
            XCTAssertEqual(trip.distanceMeters, 4_200, accuracy: 0.1)
            XCTAssertEqual(trip.points.count, 12, "GPS points must not be dropped")
            XCTAssertEqual(trip.startAddress, "Kadıköy")
            XCTAssertNil(trip.nightDistanceMeters, "pre-V10 rows start out un-backfilled")
        }
    }

    func testBackfillPopulatesDerivedFieldsWithoutTouchingUserData() async throws {
        let container = try makeDiskContainer()
        seedLegacyTrip(in: container.mainContext, startedAt: Date().addingTimeInterval(-86_400))
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let trip = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<Trip>()).first)

        XCTAssertNotNil(trip.nightDistanceMeters)
        XCTAssertNotNil(trip.trackedDistanceMeters)
        XCTAssertEqual(try XCTUnwrap(trip.startLatitude), 41.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.endLatitude), 41.011, accuracy: 0.0001)
        XCTAssertTrue(
            SearchFolding.fold(try XCTUnwrap(trip.searchIndex)).contains(SearchFolding.fold("kadıköy"))
        )

        XCTAssertEqual(trip.distanceMeters, 4_200, accuracy: 0.1, "recorded distance must be untouched")
        XCTAssertEqual(trip.points.count, 12, "backfill must never reduce GPS points")
        XCTAssertEqual(trip.label, "İş")
    }

    func testBackfillIsIdempotentAndResumesAcrossBatches() async throws {
        let container = try makeDiskContainer()
        // Two full batches plus a partial one, so a single pass has to loop.
        let tripCount = 55
        for index in 0..<tripCount {
            seedLegacyTrip(
                in: container.mainContext,
                startedAt: Date().addingTimeInterval(-Double(index + 1) * 86_400),
                pointCount: 4
            )
        }
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let context = ModelContext(container)
        let firstPass = try context.fetch(FetchDescriptor<Trip>())
        XCTAssertEqual(firstPass.count, tripCount)
        XCTAssertTrue(
            firstPass.allSatisfy { $0.nightDistanceMeters != nil },
            "every completed trip should be backfilled in one run"
        )
        let trackedBefore = firstPass.map(\.trackedDistanceMeters)

        // Running again must be a no-op rather than double-counting anything.
        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let secondContext = ModelContext(container)
        let secondPass = try secondContext.fetch(FetchDescriptor<Trip>())
            .sorted { $0.startedAt > $1.startedAt }
        XCTAssertEqual(secondPass.count, tripCount)
        XCTAssertEqual(
            secondPass.map(\.trackedDistanceMeters),
            firstPass.sorted { $0.startedAt > $1.startedAt }.map(\.trackedDistanceMeters)
        )
        XCTAssertEqual(trackedBefore.count, tripCount)
    }

    func testBackfillSkipsInProgressTrips() async throws {
        let container = try makeDiskContainer()
        let active = Trip(startedAt: Date(), endedAt: nil, distanceMeters: 500)
        container.mainContext.insert(active)
        try container.mainContext.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let context = ModelContext(container)
        let trip = try XCTUnwrap(try context.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertNil(trip.nightDistanceMeters, "an unfinished trip is recomputed when it ends")
    }

    func testSearchIndexRefreshRewritesStalePlaceNamesWithoutTouchingUserData() async throws {
        let versionKey = "trailhound.derived.searchIndexVersion"
        let previousVersion = UserDefaults.standard.integer(forKey: versionKey)
        UserDefaults.standard.set(0, forKey: versionKey)
        defer { UserDefaults.standard.set(previousVersion, forKey: versionKey) }

        let container = try makeDiskContainer()
        let context = container.mainContext
        let startedAt = Date().addingTimeInterval(-86_400)
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(1_800),
            distanceMeters: 4_200,
            startAddress: "Old Street",
            note: "Keep this note"
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.endLatitude = 41.01
        trip.endLongitude = 29.01
        trip.nightDistanceMeters = 0
        trip.trackedDistanceMeters = 4_200
        trip.stopDurationSeconds = 0
        trip.dynamicFuelCost = 0
        trip.searchIndex = "old street"
        context.insert(trip)

        let home = SavedPlace(
            name: "Ev",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300,
            kind: .home,
            isPrivacyZone: true
        )
        context.insert(home)
        try context.save()

        await TripDerivedBackfillService.backfillIfNeeded(container: container)

        let verifyContext = ModelContext(container)
        let updated = try XCTUnwrap(try verifyContext.fetch(FetchDescriptor<Trip>()).first)
        XCTAssertEqual(updated.note, "Keep this note")
        XCTAssertEqual(updated.distanceMeters, 4_200, accuracy: 0.1)
        XCTAssertEqual(updated.startPlaceName, "Ev")
        XCTAssertTrue(SearchFolding.fold(try XCTUnwrap(updated.searchIndex)).contains(SearchFolding.fold("Ev")))
        XCTAssertTrue(TripListViewModel.matchesSearch(updated, searchText: "ev"))
    }
}

@MainActor
final class TripDerivedMetricsTests: XCTestCase {
    private func makeTrip(startedAt: Date, coordinates: [(Double, Double)]) -> Trip {
        let trip = Trip(startedAt: startedAt, endedAt: startedAt.addingTimeInterval(3_600))
        for (index, coordinate) in coordinates.enumerated() {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 60),
                latitude: coordinate.0,
                longitude: coordinate.1,
                sequence: index,
                trip: trip
            )
            trip.points.append(point)
        }
        return trip
    }

    /// The pre-optimisation implementation, kept here as the reference the fast loop must match.
    private func legacyNightRatio(for trips: [Trip]) -> Double {
        var nightMeters = 0.0
        var totalMeters = 0.0
        let calendar = Calendar.current

        for trip in trips {
            let points = trip.sortedPoints
            guard points.count >= 2 else { continue }
            for index in 1..<points.count {
                let previous = points[index - 1]
                let current = points[index]
                let segment = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: current.latitude, longitude: current.longitude))
                guard segment > 0 else { continue }
                let midpoint = previous.timestamp.addingTimeInterval(
                    current.timestamp.timeIntervalSince(previous.timestamp) / 2
                )
                totalMeters += segment
                let hour = calendar.component(.hour, from: midpoint)
                if hour >= 22 || hour < 6 {
                    nightMeters += segment
                }
            }
        }

        guard totalMeters > 0 else { return 0 }
        return nightMeters / totalMeters
    }

    func testFastNightRatioMatchesLegacyImplementation() throws {
        let calendar = Calendar.current
        let nightStart = try XCTUnwrap(
            calendar.date(bySettingHour: 23, minute: 0, second: 0, of: Date().addingTimeInterval(-86_400))
        )
        let dayStart = try XCTUnwrap(
            calendar.date(bySettingHour: 13, minute: 0, second: 0, of: Date().addingTimeInterval(-86_400))
        )

        let coordinates: [(Double, Double)] = (0..<40).map { index in
            let offset = Double(index)
            return (41.0 + offset * 0.002, 29.0 + offset * 0.0015)
        }
        let nightTrip = makeTrip(startedAt: nightStart, coordinates: coordinates)
        let dayTrip = makeTrip(startedAt: dayStart, coordinates: coordinates)

        let expected = legacyNightRatio(for: [nightTrip, dayTrip])
        let actual = StatsViewModel.nightDrivingRatio(for: [nightTrip, dayTrip])

        XCTAssertEqual(actual, expected, accuracy: 0.01)
    }

    func testApproximateDistanceTracksGeodesicForShortSegments() {
        let distance = StatsViewModel.approximateDistanceMeters(
            fromLatitude: 41.0,
            fromLongitude: 29.0,
            toLatitude: 41.0005,
            toLongitude: 29.0005
        )
        let geodesic = CLLocation(latitude: 41.0, longitude: 29.0)
            .distance(from: CLLocation(latitude: 41.0005, longitude: 29.0005))

        XCTAssertEqual(distance, geodesic, accuracy: geodesic * 0.01)
    }

    func testNightRatioPrefersStoredValuesOverWalkingPoints() {
        let trip = makeTrip(startedAt: Date(), coordinates: [(41.0, 29.0), (41.01, 29.01)])
        trip.nightDistanceMeters = 300
        trip.trackedDistanceMeters = 1_000

        XCTAssertEqual(StatsViewModel.nightDrivingRatio(for: [trip]), 0.3, accuracy: 0.0001)
    }

    func testRecomputeWritesEndpointsAndNightDistance() throws {
        let calendar = Calendar.current
        let nightStart = try XCTUnwrap(
            calendar.date(bySettingHour: 23, minute: 30, second: 0, of: Date().addingTimeInterval(-86_400))
        )
        let trip = makeTrip(
            startedAt: nightStart,
            coordinates: [(41.0, 29.0), (41.005, 29.005), (41.01, 29.01)]
        )

        TripDerivedMetrics.recompute(for: trip)

        XCTAssertEqual(try XCTUnwrap(trip.startLatitude), 41.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.startLongitude), 29.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.endLatitude), 41.01, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(trip.endLongitude), 29.01, accuracy: 0.0001)
        let tracked: Double = try XCTUnwrap(trip.trackedDistanceMeters)
        let night: Double = try XCTUnwrap(trip.nightDistanceMeters)
        XCTAssertEqual(tracked, 1_400, accuracy: 200)
        XCTAssertEqual(night, tracked, accuracy: 0.1, "a trip driven entirely after 22:00 is fully night driving")
        XCTAssertNotNil(trip.stopDurationSeconds)
        XCTAssertNotNil(trip.cruiseSpeedKmh)
        XCTAssertNotNil(trip.cruiseDurationSeconds)
        XCTAssertNotNil(trip.mostCommonSpeedKmh)
        XCTAssertNotNil(trip.dynamicFuelCost)
    }

    func testRecomputeFuelDoesNotRewriteAvgCost() {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        trip.distanceMeters = 5_000
        trip.fuelConsumptionPer100 = 7.5
        trip.fuelUnitPrice = 65
        trip.estimatedFuelCost = 243.75

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .petrol)

        XCTAssertEqual(trip.estimatedFuelCost ?? 0, 243.75, accuracy: 0.01)
        XCTAssertNotNil(trip.dynamicFuelCost)
        XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, 0)
    }

    /// Stored avg cost is the display source of truth — Settings / vehicle averages must not
    /// replace it when recompute runs again under a different fuel type.
    func testStoredAvgFuelSurvivesRecomputeAndStatsFuelCost() {
        let trip = makeTrip(
            startedAt: Date().addingTimeInterval(-3_600),
            coordinates: [(41.0, 29.0), (41.01, 29.02), (41.02, 29.04)]
        )
        trip.distanceMeters = 5_000
        trip.fuelConsumptionPer100 = 7.5
        trip.fuelUnitPrice = 65
        trip.estimatedFuelCost = 243.75

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .petrol)
        let firstDynamic = trip.dynamicFuelCost ?? 0
        XCTAssertGreaterThan(firstDynamic, 0)

        TripDerivedMetrics.recomputeFuel(for: trip, fuelType: .diesel)
        XCTAssertEqual(trip.estimatedFuelCost ?? 0, 243.75, accuracy: 0.01)
        XCTAssertEqual(StatsViewModel.fuelCost(for: trip), 243.75, accuracy: 0.01)
        XCTAssertNotNil(trip.dynamicFuelCost)
        XCTAssertGreaterThan(trip.dynamicFuelCost ?? 0, 0)
    }

    func testRecomputeOnPointlessTripClearsEndpoints() {
        let trip = Trip(startedAt: Date(), endedAt: Date())
        trip.startLatitude = 1
        trip.endLatitude = 2

        TripDerivedMetrics.recompute(for: trip)

        XCTAssertNil(trip.startLatitude)
        XCTAssertNil(trip.endLatitude)
        XCTAssertEqual(trip.trackedDistanceMeters, 0)
        XCTAssertEqual(trip.stopDurationSeconds, 0)
        XCTAssertEqual(trip.cruiseSpeedKmh, 0)
        XCTAssertEqual(trip.mostCommonSpeedKmh, 0)
    }

    func testStoredCoordinatesAvoidPointLookup() {
        let trip = Trip(startedAt: Date(), endedAt: Date())
        trip.startLatitude = 40.5
        trip.startLongitude = 28.5
        trip.endLatitude = 41.5
        trip.endLongitude = 29.5

        XCTAssertEqual(trip.startCoordinate?.latitude ?? 0, 40.5, accuracy: 0.0001)
        XCTAssertEqual(trip.endCoordinate?.longitude ?? 0, 29.5, accuracy: 0.0001)
    }

    func testSearchIndexMatchesLegacyFieldScan() {
        let trip = Trip(
            startedAt: Date(),
            endedAt: Date(),
            note: "Havalimanı transferi",
            label: "İş",
            startPlaceName: "Ev",
            endPlaceName: "Ofis"
        )

        TripDerivedMetrics.refreshSearchIndex(for: trip, places: [], privacyRadius: 500)

        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "ofis"))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "havalimanı"))
        XCTAssertTrue(TripListViewModel.matchesSearch(trip, searchText: "ev"))
        XCTAssertFalse(TripListViewModel.matchesSearch(trip, searchText: "bakkal"))
        XCTAssertTrue(SearchFolding.fold(try XCTUnwrap(trip.searchIndex)).contains(SearchFolding.fold("Ev")))
    }
}
