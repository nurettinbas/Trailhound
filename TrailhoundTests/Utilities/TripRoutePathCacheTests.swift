import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class TripRoutePathCacheTests: XCTestCase {
    private var container: ModelContainer!

    override func tearDown() {
        if let container {
            // Best-effort cleanup of any disk files written during the test.
            let trips = (try? container.mainContext.fetch(FetchDescriptor<Trip>())) ?? []
            for trip in trips {
                TripRoutePathCache.shared.remove(for: trip.id)
            }
        }
        TripRoutePathCache.shared.clearMemory()
        TripRoutePathCache.shared.resetWorkerInvocationCount()
        container = nil
        super.tearDown()
    }

    func testMemoryHitSkipsWorkerOnSecondCall() async throws {
        let trip = try insertTrip(pointCount: 40)
        let cache = TripRoutePathCache.shared
        cache.resetWorkerInvocationCount()

        let first = await cache.path(for: trip, container: container)
        XCTAssertFalse(first.isEmpty)
        let invocationsAfterFirst = cache.workerInvocationCount

        let second = await cache.path(for: trip, container: container)
        XCTAssertEqual(cache.workerInvocationCount, invocationsAfterFirst)
        XCTAssertEqual(second.count, first.count)
        XCTAssertEqual(second.first?.count, first.first?.count)
    }

    func testDiskRoundTripRestoresCoordinates() async throws {
        let trip = try insertTrip(pointCount: 30)
        let cache = TripRoutePathCache.shared
        let fingerprint = TripRoutePathFingerprint.make(from: trip)

        let samples = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let payload = TripRoutePathPayload.from(samples: samples, fingerprint: fingerprint)
        cache.storeForTesting(payload, for: trip.id)
        cache.clearMemory()

        // Give the serial disk queue a moment to finish the atomic write.
        try await Task.sleep(for: .milliseconds(50))

        let restored = await cache.path(for: trip, container: container)
        XCTAssertEqual(restored.count, samples.count)
        XCTAssertEqual(
            restored.first?.map(\.coordinate.latitude),
            samples.first?.map(\.coordinate.latitude)
        )
    }

    func testFingerprintMismatchRejectsDiskCache() async throws {
        let trip = try insertTrip(pointCount: 20)
        let cache = TripRoutePathCache.shared
        var fingerprint = TripRoutePathFingerprint.make(from: trip)
        fingerprint = TripRoutePathFingerprint(
            distanceMeters: fingerprint.distanceMeters + 500,
            startedAt: fingerprint.startedAt,
            endedAt: fingerprint.endedAt,
            startLatitude: fingerprint.startLatitude,
            startLongitude: fingerprint.startLongitude,
            endLatitude: fingerprint.endLatitude,
            endLongitude: fingerprint.endLongitude
        )

        let stale = TripRoutePathPayload(
            fingerprint: fingerprint,
            pieces: [[
                CachedRoutePoint(latitude: 1, longitude: 2, timestamp: 0, speedMps: 1)
            ]]
        )
        cache.storeForTesting(stale, for: trip.id)
        cache.clearMemory()
        try await Task.sleep(for: .milliseconds(50))
        cache.resetWorkerInvocationCount()

        let path = await cache.path(for: trip, container: container)
        XCTAssertGreaterThan(cache.workerInvocationCount, 0)
        XCTAssertNotEqual(path.first?.first?.coordinate.latitude, 1)
    }

    func testRemoveClearsMemoryAndDisk() async throws {
        let trip = try insertTrip(pointCount: 15)
        let cache = TripRoutePathCache.shared
        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        let payload = TripRoutePathPayload(
            fingerprint: fingerprint,
            pieces: [[
                CachedRoutePoint(latitude: 41, longitude: 29, timestamp: 1, speedMps: 10),
                CachedRoutePoint(latitude: 41.01, longitude: 29.01, timestamp: 2, speedMps: 10)
            ]]
        )
        cache.storeForTesting(payload, for: trip.id)
        try await Task.sleep(for: .milliseconds(50))

        cache.remove(for: trip.id)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertNil(cache.cachedPath(for: trip.id, fingerprint: fingerprint))
        let disk = await cache.readDiskForTesting(tripID: trip.id)
        XCTAssertNil(disk)
    }

    func testPrewarmSkipsWorkerWhenMemoryHit() async throws {
        let trip = try insertTrip(pointCount: 25)
        let cache = TripRoutePathCache.shared
        cache.resetWorkerInvocationCount()

        _ = await cache.path(for: trip, container: container)
        let invocationsAfterPath = cache.workerInvocationCount
        XCTAssertGreaterThan(invocationsAfterPath, 0)

        cache.prewarm(tripID: trip.id, container: container)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(cache.workerInvocationCount, invocationsAfterPath)
    }

    func testPrewarmSkipsWorkerWhenDiskHit() async throws {
        let trip = try insertTrip(pointCount: 22)
        let cache = TripRoutePathCache.shared
        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        let samples = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        let payload = TripRoutePathPayload.from(samples: samples, fingerprint: fingerprint)
        cache.storeForTesting(payload, for: trip.id)
        try await Task.sleep(for: .milliseconds(50))
        cache.clearMemory()
        cache.resetWorkerInvocationCount()

        cache.prewarm(tripID: trip.id, container: container)
        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(cache.workerInvocationCount, 0)
        let restored = await cache.path(for: trip, container: container)
        XCTAssertEqual(cache.workerInvocationCount, 0)
        XCTAssertEqual(restored.count, samples.count)
        XCTAssertEqual(
            restored.first?.map(\.coordinate.latitude),
            samples.first?.map(\.coordinate.latitude)
        )
    }

    func testCorruptDiskFileIsTreatedAsMiss() async throws {
        let trip = try insertTrip(pointCount: 12)
        let cache = TripRoutePathCache.shared
        cache.resetWorkerInvocationCount()

        // Write garbage into the expected file location by storing then overwriting via remove+rebuild.
        let fingerprint = TripRoutePathFingerprint.make(from: trip)
        cache.storeForTesting(
            TripRoutePathPayload(fingerprint: fingerprint, pieces: []),
            for: trip.id
        )
        try await Task.sleep(for: .milliseconds(50))

        // Corrupt by writing truncated bytes through the public remove + direct file write.
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = appSupport
            .appendingPathComponent("TripRoutePaths", isDirectory: true)
            .appendingPathComponent("\(trip.id.uuidString).bin")
        try Data([0x00, 0x01, 0x02]).write(to: url, options: .atomic)

        cache.clearMemory()
        let path = await cache.path(for: trip, container: container)
        XCTAssertGreaterThan(cache.workerInvocationCount, 0)
        XCTAssertFalse(path.isEmpty)
    }

    @discardableResult
    private func insertTrip(pointCount: Int) throws -> Trip {
        container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext
        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(Double(pointCount) * 5),
            distanceMeters: Double(pointCount) * 12
        )
        trip.startLatitude = 41.0
        trip.startLongitude = 29.0
        trip.endLatitude = 41.0 + Double(pointCount) * 0.0001
        trip.endLongitude = 29.0 + Double(pointCount) * 0.0001
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 5),
                latitude: 41.0 + Double(index) * 0.0001,
                longitude: 29.0 + Double(index) * 0.0001,
                sequence: index,
                speedMps: 12,
                trip: trip
            )
            context.insert(point)
        }
        try context.save()
        return trip
    }
}
