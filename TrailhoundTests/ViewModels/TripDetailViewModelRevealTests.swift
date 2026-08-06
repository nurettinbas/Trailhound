import CoreLocation
import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class TripDetailViewModelRevealTests: XCTestCase {
    private var container: ModelContainer!

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testRevealProgressZeroIsEmptyOrMinimal() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = makeViewModel(for: trip)

        let segments = viewModel.revealedSpeedColoredSegments(progress: 0)
        XCTAssertTrue(segments.isEmpty || segments.allSatisfy { $0.coordinates.count <= 2 })
    }

    func testRevealProgressOneMatchesFullSegments() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = makeViewModel(for: trip)

        let revealed = viewModel.revealedSpeedColoredSegments(progress: 1)
        let full = viewModel.speedColoredSegments
        XCTAssertEqual(revealed.count, full.count)
    }

    func testRevealProgressIncreasesCoordinateCoverage() throws {
        let trip = try insertTrip(pointCount: 8)
        let viewModel = makeViewModel(for: trip)

        let early = viewModel.revealedSpeedColoredSegments(progress: 0.25)
        let later = viewModel.revealedSpeedColoredSegments(progress: 0.75)

        let earlyPoints = early.reduce(0) { $0 + $1.coordinates.count }
        let laterPoints = later.reduce(0) { $0 + $1.coordinates.count }
        XCTAssertLessThanOrEqual(earlyPoints, laterPoints)
    }

    func testNilDisplayPathDoesNotCrash() throws {
        let trip = try insertTrip(pointCount: 5)
        let viewModel = TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: nil
        )
        XCTAssertTrue(viewModel.revealedSpeedColoredSegments(progress: 1).isEmpty)
        XCTAssertEqual(viewModel.displayPointCount, 0)
    }

    private func makeViewModel(for trip: Trip) -> TripDetailViewModel {
        let pieces = RouteDisplayPath.displaySegments(
            samples: RouteDisplayPath.samples(from: trip.sortedPoints)
        )
        return TripDetailViewModel(
            trip: trip,
            places: [],
            privacyRadius: 500,
            displayPieces: pieces
        )
    }

    @discardableResult
    private func insertTrip(pointCount: Int) throws -> Trip {
        container = try ModelContainerFactory.makeInMemory()
        let context = container.mainContext

        let startedAt = Date()
        let trip = Trip(
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(600),
            distanceMeters: 5_000
        )
        context.insert(trip)

        for index in 0..<pointCount {
            let point = TripPoint(
                timestamp: startedAt.addingTimeInterval(Double(index) * 30),
                latitude: 41.0 + Double(index) * 0.001,
                longitude: 29.0 + Double(index) * 0.001,
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
